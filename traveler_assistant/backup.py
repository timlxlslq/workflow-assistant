"""Local database backup and retention policy."""

from __future__ import annotations

import hashlib
import os
import sqlite3
import tempfile
from datetime import date, datetime, timedelta
from pathlib import Path

from .core import Config
from .database import ensure_schema


def _fingerprint(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def backup_status(config: Config, today: date | None = None) -> dict:
    today = today or date.today()
    ensure_schema(config.workflow_database)
    connection = sqlite3.connect(config.workflow_database)
    try:
        row = connection.execute(
            "select finished_at, backup_path from backup_records where status='success' and substr(finished_at,1,10)=? order by id desc limit 1",
            (today.isoformat(),),
        ).fetchone()
    finally:
        connection.close()
    return {
        "backup_root": str(config.database_backup_root),
        "database": str(config.workflow_database),
        "successful_today": row is not None,
        "last_success": {"finished_at": row[0], "path": row[1]} if row else None,
        "requires_user_attention": row is None,
        "storage_available": config.database_backup_root.parent.exists(),
    }


def perform_backup(config: Config) -> dict:
    status = backup_status(config)
    started = datetime.now().astimezone().isoformat(timespec="seconds")
    root = config.database_backup_root
    root.mkdir(parents=True, exist_ok=True)
    destination = root / f"workflow-{datetime.now():%Y-%m-%d}.sqlite3"
    temporary_fd, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.stem}-", suffix=".tmp", dir=root
    )
    os.close(temporary_fd)
    temporary = Path(temporary_name)
    try:
        connection = sqlite3.connect(config.workflow_database)
        try:
            target = sqlite3.connect(temporary)
            try:
                connection.backup(target)
            finally:
                target.close()
        finally:
            connection.close()
        os.replace(temporary, destination)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise
    finished = datetime.now().astimezone().isoformat(timespec="seconds")
    connection = sqlite3.connect(config.workflow_database)
    try:
        connection.execute(
            "insert into backup_records(backup_path,backup_kind,started_at,finished_at,status,database_fingerprint) values(?,?,?,?,?,?)",
            (str(destination), "daily", started, finished, "success", _fingerprint(destination)),
        )
        connection.commit()
    finally:
        connection.close()
    _apply_retention(root, datetime.now().date())
    return {"status": "success", "path": str(destination), "finished_at": finished}


def _apply_retention(root: Path, today: date) -> None:
    candidates: list[tuple[Path, date]] = []
    for path in root.glob("workflow-*.sqlite3"):
        try:
            backup_date = date.fromisoformat(path.stem.removeprefix("workflow-"))
        except ValueError:
            continue
        candidates.append((path, backup_date))

    weekly: dict[tuple[int, int], tuple[Path, date]] = {}
    keep: set[Path] = set()
    for path, backup_date in candidates:
        age = (today - backup_date).days
        if age < 0:
            # Do not delete a future-dated file; it may be a clock-adjustment
            # artifact and is safer to retain until the next run.
            keep.add(path)
        elif age <= 2:
            keep.add(path)
        elif age <= 30:
            key = backup_date.isocalendar()[:2]
            current = weekly.get(key)
            if current is None or backup_date > current[1]:
                weekly[key] = (path, backup_date)

    keep.update(path for path, _ in weekly.values())
    for path, backup_date in candidates:
        age = (today - backup_date).days
        if age > 30 or path not in keep:
            path.unlink(missing_ok=True)
