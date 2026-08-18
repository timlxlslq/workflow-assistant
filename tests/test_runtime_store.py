import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime
from io import StringIO
from pathlib import Path

from traveler_assistant.assistant_cli import main as assistant_main
from traveler_assistant.database import ensure_schema
from traveler_assistant.runtime_store import RuntimeStore, TokenUsage, runtime_database_path


class RuntimeStoreTests(unittest.TestCase):
    def test_runtime_database_uses_a_private_file(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp)
            self.assertEqual(runtime_database_path(state), state / "assistant-runtime.sqlite3")

    def test_unknown_database_version_is_not_deleted(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "workflow.sqlite3"
            connection = __import__("sqlite3").connect(path)
            connection.execute("pragma user_version = 7")
            connection.commit()
            connection.close()
            with self.assertRaises(RuntimeError):
                RuntimeStore(path)
            self.assertTrue(path.exists())

    def test_assistant_usage_does_not_touch_workflow_database(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp)
            workflow = state / "workflow.sqlite3"
            ensure_schema(workflow)
            connection = __import__("sqlite3").connect(workflow)
            connection.execute(
                """insert into material_items(
                    order_id, material_type, color, thickness,
                    quantity, unit, edge, source_type, source_path, source_fingerprint, updated_at
                ) values(?,?,?,?,?,?,?,?,?,?,?)""",
                ("CS005", "panel", "Woodline 4", "19.1", 4, "pcs", "", "aihouse", "fixture.xlsx", "fp", "now"),
            )
            connection.commit()
            connection.close()

            with redirect_stdout(StringIO()):
                self.assertEqual(assistant_main(["--usage", "--state-dir", str(state)]), 0)

            connection = __import__("sqlite3").connect(workflow)
            self.assertEqual(connection.execute("select count(*) from material_items").fetchone()[0], 1)
            connection.close()
            self.assertTrue(runtime_database_path(state).exists())

    def test_agent_usage_has_week_month_and_total_summaries(self):
        with tempfile.TemporaryDirectory() as temp:
            store = RuntimeStore(Path(temp) / "workflow.sqlite3")
            store.record_agent_usage("test-model", TokenUsage(120, 30))
            self.assertEqual(
                store.token_summary(datetime.now()),
                {"week": 150, "month": 150, "total": 150},
            )

    def test_agent_route_is_learned_as_an_exact_normalized_phrase(self):
        with tempfile.TemporaryDirectory() as temp:
            store = RuntimeStore(Path(temp) / "workflow.sqlite3")
            store.remember_command("帮我瞅瞅pp0063", "preview_order", {"order_id": "PP0063"})
            self.assertEqual(
                store.learned_command("帮我瞅瞅pp0063"),
                ("preview_order", {"order_id": "PP0063"}),
            )
            self.assertIsNone(store.learned_command("帮我瞅瞅pp0064"))

    def test_learned_command_preserves_typed_arguments(self):
        with tempfile.TemporaryDirectory() as temp:
            store = RuntimeStore(Path(temp) / "workflow.sqlite3")
            arguments = {
                "order_id": "PP1234-2",
                "factory_name": "PP1234-2-LAUNDRY",
                "product_code": "M0144",
                "quantity": "2",
            }
            store.remember_command("洗衣房补两个", "add_manual_hardware", arguments)
            self.assertEqual(
                store.learned_command("洗衣房补两个"),
                ("add_manual_hardware", arguments),
            )


if __name__ == "__main__":
    unittest.main()
