from __future__ import annotations

import fcntl
import json
import os
import re
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any


OPERATION_LOG_ENV = "WORKFLOW_OPERATION_LOG"
OPERATION_LOG_ENABLED_ENV = "WORKFLOW_OPERATION_LOG_ENABLED"
OPERATION_SESSION_ENV = "WORKFLOW_OPERATION_SESSION_ID"
OPERATION_ID_ENV = "WORKFLOW_OPERATION_ID"

_SENSITIVE_KEY_PARTS = (
    "password",
    "passwd",
    "secret",
    "token",
    "api_key",
    "apikey",
    "authorization",
    "cookie",
    "keychain",
    "credential",
    "username",
    "user_name",
    "remarks",
    "query",
    "input_value",
)
_SENSITIVE_TEXT_RE = re.compile(r"(?i)(password|passwd|secret|token|api[_-]?key|authorization|cookie)\s*[:=]\s*[^\s,;]+")
_SQL_WRITE_RE = re.compile(r"^\s*(insert(?:\s+or\s+\w+)?\s+into|update|delete\s+from|replace\s+into)\s+([\"`\[]?\w+[\"`\]]?)", re.IGNORECASE)


def _is_sensitive_key(key: str) -> bool:
    lowered = key.replace("-", "_").lower()
    return any(part in lowered for part in _SENSITIVE_KEY_PARTS)


def _redact_text(value: str) -> str:
    value = _SENSITIVE_TEXT_RE.sub(lambda match: f"{match.group(1)}=[REDACTED]", value)
    # Home paths are useful for diagnosing which file was touched, but the
    # account name is not needed in a persistent audit record.
    home = str(Path.home())
    if home:
        value = value.replace(home, "~")
    return value


def redact(value: Any, key: str | None = None) -> Any:
    """Keep audit context useful while preventing secrets and raw inputs."""
    if key is not None and _is_sensitive_key(key):
        return "[REDACTED]"
    if isinstance(value, dict):
        return {str(name): redact(item, str(name)) for name, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [redact(item) for item in value]
    if isinstance(value, str):
        return _redact_text(value)
    if value is None or isinstance(value, (bool, int, float)):
        return value
    return _redact_text(str(value))


def operation_log_enabled_from_environment() -> bool:
    return os.environ.get(OPERATION_LOG_ENABLED_ENV, "1").strip().lower() not in {"0", "false", "no", "off"}


def write_operation_log(
    path: Path,
    event: str,
    message: str,
    *,
    actor: str = "app",
    component: str = "python",
    details: dict[str, Any] | None = None,
    enabled: bool = True,
    session_id: str | None = None,
    operation_id: str | None = None,
) -> None:
    """Append one JSON object to the shared, process-safe audit log.

    Logging is deliberately best-effort: a full disk or a permission problem
    must not prevent the business operation from completing.
    """
    if not enabled:
        return
    payload = {
        "timestamp": datetime.now().astimezone().isoformat(timespec="milliseconds"),
        "event": event,
        "actor": actor,
        "component": component,
        "message": redact(message),
        "session_id": session_id or os.environ.get(OPERATION_SESSION_ENV, ""),
        "operation_id": operation_id or os.environ.get(OPERATION_ID_ENV, ""),
        "details": redact(details or {}),
    }
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        line = (json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")
        fd = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            os.write(fd, line)
            os.fsync(fd)
        finally:
            try:
                fcntl.flock(fd, fcntl.LOCK_UN)
            finally:
                os.close(fd)
    except (OSError, ValueError):
        return


class OperationLogger:
    def __init__(self, path: Path, enabled: bool = True, session_id: str | None = None):
        self.path = path
        self.enabled = enabled
        self.session_id = session_id or os.environ.get(OPERATION_SESSION_ENV) or str(uuid.uuid4())

    def event(
        self,
        event: str,
        message: str,
        *,
        actor: str = "app",
        component: str = "python",
        details: dict[str, Any] | None = None,
        operation_id: str | None = None,
    ) -> None:
        write_operation_log(
            self.path,
            event,
            message,
            actor=actor,
            component=component,
            details=details,
            enabled=self.enabled,
            session_id=self.session_id,
            operation_id=operation_id,
        )


def configure_operation_log(config: Any) -> OperationLogger:
    logger = OperationLogger(config.state_dir / "operation-log.jsonl", bool(config.operation_log_enabled))
    os.environ[OPERATION_LOG_ENV] = str(logger.path)
    os.environ[OPERATION_LOG_ENABLED_ENV] = "1" if logger.enabled else "0"
    os.environ[OPERATION_SESSION_ENV] = logger.session_id
    os.environ.setdefault(OPERATION_ID_ENV, str(uuid.uuid4()))
    return logger


def log_progress_payload(payload: dict[str, Any]) -> None:
    """Persist a Playwright progress payload without echoing it a second time."""
    message = payload.get("message")
    if not isinstance(message, str) or not message:
        return
    details = {key: value for key, value in payload.items() if key not in {"event", "message"}}
    path_text = os.environ.get(OPERATION_LOG_ENV, "").strip()
    if not path_text:
        return
    write_operation_log(
        Path(path_text),
        "backend.progress",
        message,
        component="playwright",
        details=details,
        enabled=operation_log_enabled_from_environment(),
    )


def log_database_statement(path: Path, statement: str) -> None:
    """Record the database operation shape, never its bound values."""
    match = _SQL_WRITE_RE.match(statement)
    if not match:
        return
    table = match.group(2).strip('"`[]')
    log_path_text = os.environ.get(OPERATION_LOG_ENV, "").strip()
    if not log_path_text:
        return
    write_operation_log(
        Path(log_path_text),
        "database.write",
        "写入本地数据库",
        component="sqlite",
        details={"database": str(path), "operation": match.group(1).lower(), "table": table},
        enabled=operation_log_enabled_from_environment(),
    )
