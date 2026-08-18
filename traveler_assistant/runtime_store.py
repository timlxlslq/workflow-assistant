from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

from .operation_log import log_database_statement


SCHEMA_VERSION = 3
RUNTIME_DATABASE_NAME = "assistant-runtime.sqlite3"


def runtime_database_path(state_dir: Path) -> Path:
    """Return the private database used for assistant usage and learned commands."""
    return state_dir / RUNTIME_DATABASE_NAME


@dataclass(frozen=True)
class TokenUsage:
    input_tokens: int
    output_tokens: int

    @property
    def total_tokens(self) -> int:
        return self.input_tokens + self.output_tokens


class RuntimeStore:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        self.connection = sqlite3.connect(path)
        self.connection.set_trace_callback(lambda statement: log_database_statement(self.path, statement))
        version = self.connection.execute("pragma user_version").fetchone()[0]
        if version not in (0, SCHEMA_VERSION):
            self.connection.close()
            raise RuntimeError(
                f"助手运行库版本不受支持：{version}；为避免误删业务数据，未重建 {path}"
            )
        self.connection.executescript(
            f"""
            create table if not exists agent_usage(
                id integer primary key,
                created_at text not null,
                model text not null,
                input_tokens integer not null check(input_tokens >= 0),
                output_tokens integer not null check(output_tokens >= 0)
            );
            create table if not exists learned_commands(
                normalized_text text primary key,
                action text not null,
                arguments_json text not null,
                created_at text not null
            );
            pragma user_version = {SCHEMA_VERSION};
            """
        )
        self.connection.commit()

    def record_agent_usage(self, model: str, usage: TokenUsage) -> None:
        self.connection.execute(
            "insert into agent_usage(created_at, model, input_tokens, output_tokens) values(?,?,?,?)",
            (datetime.now().isoformat(timespec="seconds"), model, usage.input_tokens, usage.output_tokens),
        )
        self.connection.commit()

    def remember_command(self, normalized_text: str, action: str, arguments: dict[str, str]) -> None:
        self.connection.execute(
            """
            insert into learned_commands(normalized_text, action, arguments_json, created_at)
            values(?,?,?,?)
            on conflict(normalized_text) do update set
                action=excluded.action,
                arguments_json=excluded.arguments_json,
                created_at=excluded.created_at
            """,
            (
                normalized_text,
                action,
                json.dumps(arguments, ensure_ascii=False, sort_keys=True),
                datetime.now().isoformat(timespec="seconds"),
            ),
        )
        self.connection.commit()

    def learned_command(self, normalized_text: str) -> tuple[str, dict[str, str]] | None:
        row = self.connection.execute(
            "select action, arguments_json from learned_commands where normalized_text = ?",
            (normalized_text,),
        ).fetchone()
        if row is None:
            return None
        arguments = json.loads(row[1])
        if not isinstance(arguments, dict) or any(
            not isinstance(key, str) or not isinstance(value, str)
            for key, value in arguments.items()
        ):
            return None
        return str(row[0]), arguments

    def token_summary(self, now: datetime | None = None) -> dict[str, int]:
        now = now or datetime.now()
        week_start = now - timedelta(days=now.weekday())
        week_start = week_start.replace(hour=0, minute=0, second=0, microsecond=0)
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        def total_since(start: datetime | None) -> int:
            if start is None:
                row = self.connection.execute(
                    "select coalesce(sum(input_tokens + output_tokens), 0) from agent_usage"
                ).fetchone()
            else:
                row = self.connection.execute(
                    "select coalesce(sum(input_tokens + output_tokens), 0) from agent_usage where created_at >= ?",
                    (start.isoformat(timespec="seconds"),),
                ).fetchone()
            return int(row[0])

        return {
            "week": total_since(week_start),
            "month": total_since(month_start),
            "total": total_since(None),
        }
