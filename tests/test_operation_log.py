import json
import os
import tempfile
import unittest
from pathlib import Path

from traveler_assistant.operation_log import OperationLogger, log_database_statement, write_operation_log


class OperationLogTests(unittest.TestCase):
    def test_append_log_has_timestamp_and_never_stores_sensitive_values(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "operation-log.jsonl"
            logger = OperationLogger(path, session_id="session-1")
            logger.event(
                "user.action",
                "用户点击保存密码",
                details={"input_present": True, "password": "do-not-store", "username": "do-not-store"},
            )
            row = json.loads(path.read_text(encoding="utf-8"))
            self.assertTrue(row["timestamp"])
            self.assertEqual(row["session_id"], "session-1")
            self.assertEqual(row["details"]["password"], "[REDACTED]")
            self.assertNotIn("do-not-store", path.read_text(encoding="utf-8"))

    def test_disabled_logger_does_not_create_or_append_file(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "operation-log.jsonl"
            write_operation_log(path, "user.action", "点击查询", enabled=False)
            self.assertFalse(path.exists())

    def test_database_trace_records_operation_shape_without_bound_values(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "operation-log.jsonl"
            old_path = os.environ.get("WORKFLOW_OPERATION_LOG")
            old_enabled = os.environ.get("WORKFLOW_OPERATION_LOG_ENABLED")
            os.environ["WORKFLOW_OPERATION_LOG"] = str(path)
            os.environ["WORKFLOW_OPERATION_LOG_ENABLED"] = "1"
            try:
                log_database_statement(Path(temp) / "orders.sqlite3", "INSERT INTO orders(order_id) VALUES ('PP0001')")
            finally:
                if old_path is None:
                    os.environ.pop("WORKFLOW_OPERATION_LOG", None)
                else:
                    os.environ["WORKFLOW_OPERATION_LOG"] = old_path
                if old_enabled is None:
                    os.environ.pop("WORKFLOW_OPERATION_LOG_ENABLED", None)
                else:
                    os.environ["WORKFLOW_OPERATION_LOG_ENABLED"] = old_enabled
            content = path.read_text(encoding="utf-8")
            self.assertIn('"table": "orders"', content)
            self.assertNotIn("PP0001", content)


if __name__ == "__main__":
    unittest.main()
