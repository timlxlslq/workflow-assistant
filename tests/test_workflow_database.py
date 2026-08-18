import sqlite3
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

from traveler_assistant.backup import _apply_retention, backup_status, perform_backup
from traveler_assistant.core import Config
from traveler_assistant.database import ensure_schema, migrate_legacy_databases
from traveler_assistant.order_details import order_detail
from traveler_assistant.order_index import OrderIndexStore


class WorkflowDatabaseTests(unittest.TestCase):
    def test_material_table_migrates_to_order_scope_and_removes_allocations(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "workflow.sqlite3"
            connection = sqlite3.connect(path)
            connection.executescript(
                """
                create table material_items(
                    id integer primary key,
                    order_id text not null default '',
                    factory_order text not null default '',
                    scope text not null default 'factory_order',
                    material_type text not null default '',
                    color text not null default '',
                    thickness text not null default '',
                    quantity real not null default 0,
                    unit text not null default '',
                    edge text not null default '',
                    source_type text not null default '',
                    source_path text not null default '',
                    source_fingerprint text not null default '',
                    updated_at text not null
                );
                create table material_allocations(id integer primary key);
                insert into material_items(order_id, factory_order, scope, material_type, quantity, unit, updated_at)
                    values('PP9999', '', 'order', 'panel', 4, 'pcs', 'now');
                insert into material_items(order_id, factory_order, scope, material_type, quantity, unit, updated_at)
                    values('PP9999', 'F100', 'factory_order', 'panel', 2, 'pcs', 'now');
                """
            )
            connection.commit()
            connection.close()

            ensure_schema(path)

            connection = sqlite3.connect(path)
            columns = [row[1] for row in connection.execute("pragma table_info(material_items)")]
            self.assertNotIn("factory_order", columns)
            self.assertNotIn("scope", columns)
            self.assertEqual(connection.execute("select quantity from material_items").fetchone()[0], 4)
            self.assertIsNone(connection.execute("select 1 from sqlite_master where name='material_allocations'").fetchone())
            connection.close()

    def test_legacy_order_database_migrates_without_reading_inventory_database(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp) / "state"
            state.mkdir()
            legacy_order = state / "order-index.sqlite3"
            connection = sqlite3.connect(legacy_order)
            connection.execute("create table orders(order_id text primary key, order_type text)")
            connection.execute("insert into orders values('PP9999','owned')")
            connection.commit(); connection.close()
            legacy_inventory = state / "inventory" / "inventory.sqlite3"
            legacy_inventory.parent.mkdir()
            connection = sqlite3.connect(legacy_inventory)
            connection.execute("create table products(code text primary key, name text)")
            connection.execute("insert into products values('M1','Test')")
            connection.commit(); connection.close()

            result = migrate_legacy_databases(state)
            central = state / "workflow.sqlite3"
            self.assertEqual(result["status"], "completed")
            connection = sqlite3.connect(central)
            self.assertEqual(connection.execute("select order_id from orders").fetchone()[0], "PP9999")
            self.assertIsNone(
                connection.execute(
                    "select 1 from sqlite_master where type='table' and name='products'"
                ).fetchone()
            )
            connection.close()
            self.assertTrue(list((state / "migration-archives").rglob("*.sqlite3")))
            self.assertTrue(legacy_inventory.is_file())

    def test_one_factory_order_gets_one_batch_and_conflict_raises_open_issue(self):
        with tempfile.TemporaryDirectory() as temp:
            config = Config(state_dir=Path(temp) / "state")
            config.prepare_storage()
            store = OrderIndexStore(config.workflow_database)
            store.upsert_aimes_factory("F1", order_id="PP9999", factory_name="PP9999-KITCHEN", sales_order_name="PP9999", split_time="", seen_at="now")
            store.update_source_file_identity(Path("/tmp/PC124429962607080001/report.xlsx"), order_id="PP9999", factory_order="F1")
            store.record_batch_evidence("F1", "PC124429962607080001", Path("/tmp/PC124429962607080001/report.xlsx"), "PP9999")
            store.record_batch_evidence("F1", "PC124429962606270001", Path("/tmp/PC124429962606270001/report.xlsx"), "PP9999")
            store.commit()
            row = store.connection.execute("select production_batch_id from factory_orders where factory_order='F1'").fetchone()
            self.assertIsNone(row[0])
            self.assertTrue(any(item["kind"] == "batch_conflict" for item in store.active_issues()))
            store.close()

    def test_backup_status_requires_user_action_without_successful_record(self):
        with tempfile.TemporaryDirectory() as temp:
            config = Config(state_dir=Path(temp) / "state", backup_root=Path(temp) / "server" / "database-backups")
            config.prepare_storage()
            status = backup_status(config, date.today())
            self.assertTrue(status["requires_user_attention"])

    def test_retention_keeps_recent_daily_and_sunday_weekly_backups(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            today = date(2026, 8, 15)
            for day in (
                today - timedelta(days=1),
                today - timedelta(days=2),
                today - timedelta(days=3),
                today - timedelta(days=4),
                today - timedelta(days=20),
                today - timedelta(days=21),
                today - timedelta(days=100),
            ):
                (root / f"workflow-{day.isoformat()}.sqlite3").touch()
            _apply_retention(root, today)
            self.assertTrue((root / "workflow-2026-08-14.sqlite3").exists())
            self.assertTrue((root / "workflow-2026-08-12.sqlite3").exists())  # latest in the week
            self.assertFalse((root / "workflow-2026-08-11.sqlite3").exists())
            self.assertTrue((root / "workflow-2026-07-26.sqlite3").exists())  # latest in the week
            self.assertFalse((root / "workflow-2026-05-07.sqlite3").exists())

    def test_perform_backup_uses_local_database_backup_directory(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp) / "state"
            config = Config(state_dir=state, backup_root=Path(temp) / "traveler-backups")
            config.prepare_storage()
            result = perform_backup(config)

            destination = Path(result["path"])
            self.assertEqual(destination.parent, state / "database-backups")
            self.assertTrue(destination.is_file())
            self.assertEqual(
                sqlite3.connect(destination).execute("pragma integrity_check").fetchone()[0],
                "ok",
            )


if __name__ == "__main__":
    unittest.main()
