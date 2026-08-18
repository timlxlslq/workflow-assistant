"""Central workflow database and safe migration helpers.

The application owns one local SQLite file for business data.  Source files
from AIHouse/AIMES/AICNC/Kingdee remain external; this module stores the
normalized facts, provenance and user corrections needed by the dashboard.
"""

from __future__ import annotations

import json
import re
import shutil
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any


def database_path(state_dir: Path) -> Path:
    return state_dir / "workflow.sqlite3"


def _now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def ensure_schema(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path)
    try:
        connection.executescript(
            """
            create table if not exists workflow_metadata(
                key text primary key,
                value text not null default '',
                updated_at text not null
            );
            create table if not exists business_cache(
                cache_name text not null,
                cache_key text not null,
                value_json text not null,
                updated_at text not null,
                primary key(cache_name, cache_key)
            );
            create table if not exists production_batches(
                batch_id integer primary key,
                batch_number text not null unique,
                production_date text not null default '',
                source text not null default '',
                status text not null default 'active',
                first_seen text not null default '',
                last_seen text not null default '',
                created_at text not null,
                updated_at text not null
            );
            create table if not exists material_items(
                id integer primary key,
                order_id text not null default '',
                material_type text not null default '',
                color text not null default '',
                thickness text not null default '',
                quantity real not null default 0,
                unit text not null default '',
                edge text not null default '',
                source_type text not null default '',
                source_path text not null default '',
                source_fingerprint text not null default '',
                updated_at text not null,
                unique(order_id, material_type, color, thickness, unit, edge, source_type, source_path)
            );
            create index if not exists idx_material_items_order on material_items(order_id);
            create table if not exists hardware_items(
                id integer primary key,
                order_id text not null default '',
                factory_order text not null default '',
                scope text not null default 'factory_order',
                product_code text not null default '',
                name text not null default '',
                spec text not null default '',
                quantity real not null default 0,
                unit text not null default '',
                source_type text not null default 'aicnc',
                source_path text not null default '',
                active integer not null default 1,
                remarks text not null default '',
                updated_at text not null
            );
            create index if not exists idx_hardware_items_order on hardware_items(order_id, factory_order, active);
            create table if not exists outbound_documents(
                id integer primary key,
                document_number text not null unique,
                document_type text not null default '',
                order_id text not null default '',
                factory_order text not null default '',
                status text not null default 'recorded',
                source text not null default '',
                issued_at text not null default '',
                source_path text not null default '',
                updated_at text not null
            );
            create index if not exists idx_outbound_documents_order on outbound_documents(order_id, factory_order);
            create table if not exists backup_records(
                id integer primary key,
                backup_path text not null,
                backup_kind text not null default 'daily',
                started_at text not null,
                finished_at text not null,
                status text not null,
                database_fingerprint text not null default '',
                error text not null default ''
            );
            create index if not exists idx_backup_records_finished on backup_records(finished_at desc);
            create table if not exists inventory_resolution_rules(
                id integer primary key,
                rule_type text not null check(rule_type in ('mapping', 'ignore')),
                source_name text not null,
                normalized_name text not null unique,
                product_code text,
                reason text not null default '',
                created_at text not null,
                updated_at text not null,
                check(
                    (rule_type = 'mapping' and product_code is not null and trim(product_code) <> '')
                    or
                    (rule_type = 'ignore' and product_code is null)
                )
            );
            create index if not exists idx_inventory_rules_type
                on inventory_resolution_rules(rule_type, normalized_name);
            create table if not exists outbound_scope_decisions(
                id integer primary key,
                order_id text not null,
                scope_type text not null check(scope_type in ('material', 'hardware')),
                factory_order text not null default '',
                requirement text not null check(requirement in ('required', 'customer_supplied', 'remainder', 'not_required')),
                reason text not null default '',
                source_fingerprint text not null default '',
                created_at text not null,
                updated_at text not null,
                unique(order_id, scope_type, factory_order)
            );
            create index if not exists idx_outbound_scope_order
                on outbound_scope_decisions(order_id, scope_type, factory_order);
            """
        )
        material_columns = {
            row[1] for row in connection.execute("pragma table_info(material_items)").fetchall()
        }
        if {"factory_order", "scope"}.intersection(material_columns):
            connection.execute("drop index if exists idx_material_items_order")
            connection.execute("alter table material_items rename to material_items_legacy")
            connection.execute(
                """
                create table material_items(
                    id integer primary key,
                    order_id text not null default '',
                    material_type text not null default '',
                    color text not null default '',
                    thickness text not null default '',
                    quantity real not null default 0,
                    unit text not null default '',
                    edge text not null default '',
                    source_type text not null default '',
                    source_path text not null default '',
                    source_fingerprint text not null default '',
                    updated_at text not null,
                    unique(order_id, material_type, color, thickness, unit, edge, source_type, source_path)
                )
                """
            )
            connection.execute(
                """
                insert or replace into material_items(
                    id, order_id, material_type, color, thickness, quantity, unit, edge,
                    source_type, source_path, source_fingerprint, updated_at
                )
                select id, order_id, material_type, color, thickness, quantity, unit, edge,
                       source_type, source_path, source_fingerprint, updated_at
                from material_items_legacy
                where trim(coalesce(factory_order, '')) = ''
                  and trim(coalesce(scope, '')) in ('', 'order')
                """
            )
            connection.execute("drop table material_items_legacy")
            connection.execute("create index idx_material_items_order on material_items(order_id)")
        connection.execute("drop table if exists material_allocations")
        factory_table = connection.execute(
            "select 1 from sqlite_master where type='table' and name='factory_orders'"
        ).fetchone()
        if factory_table is not None:
            factory_columns = {
                row[1] for row in connection.execute("pragma table_info(factory_orders)").fetchall()
            }
            for column, definition in (
                ("aimes_status", "text not null default 'active'"),
                ("aimes_deleted_at", "text not null default ''"),
                ("aimes_last_verified_at", "text not null default ''"),
            ):
                if column not in factory_columns:
                    connection.execute(
                        f"alter table factory_orders add column {column} {definition}"
                    )
        connection.commit()
    finally:
        connection.close()


def _normalize_inventory_rule_name(value: str) -> str:
    return re.sub(r"[\s_-]+", "", str(value)).upper()


_LEGACY_MAPPING_DISPLAY_NAMES = {
    "EDGEBANDINGWOODLINE4": "Edge banding--Woodline 4",
    "ADJUSTABLESHELFHOLDER": "Adjustable shelf holder",
    "EDGEBANDINGPENELOPEFA44": "Edge banding--Penelope FA44",
    "19.1MMPENELOPEFA44": "19.1mm--Penelope FA44",
    "8MMWOODLINE3": "8mm--Woodline 3",
    "19.1MMWALNUT": "19.1mm--Walnut",
    "EDGEBANDINGWALNUT": "Edge banding--Walnut",
    "CLOTHRODBRACKETFITTING": "Cloth rod bracket - Fitting",
}


def migrate_inventory_mapping_file(state_dir: Path) -> dict[str, Any]:
    """Move the legacy mapping JSON into the central database once.

    The JSON is archived only after the transaction commits.  Runtime code
    does not use the archived file; it exists solely as a recoverable record
    of the pre-database configuration.
    """
    central = database_path(state_dir)
    ensure_schema(central)
    source = state_dir / "inventory" / "mappings.json"
    connection = sqlite3.connect(central)
    try:
        # App startup can prepare storage from more than one background task.
        # Serialize this one-time migration so two callers cannot both observe
        # a missing marker and then race on workflow_metadata's primary key.
        connection.execute("begin immediate")
        marker = connection.execute(
            "select value from workflow_metadata where key='inventory_mapping_migration_v1'"
        ).fetchone()
        if marker is not None:
            return {"status": "already_migrated", "central": str(central)}
        if not source.is_file():
            connection.execute(
                "insert into workflow_metadata(key,value,updated_at) values(?,?,?)",
                ("inventory_mapping_migration_v1", json.dumps({"manual": 0, "ignored": 0}), _now()),
            )
            connection.commit()
            return {"status": "no_legacy_file", "central": str(central)}
        try:
            payload = json.loads(source.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ValueError(f"库存映射文件无法读取：{source}") from exc
        if not isinstance(payload, dict):
            raise ValueError(f"库存映射文件格式无效：{source}")
        manual = payload.get("manual", {})
        ignored = payload.get("ignored", {})
        if not isinstance(manual, dict) or not isinstance(ignored, dict):
            raise ValueError(f"库存映射文件缺少 manual/ignored 对象：{source}")

        rows: list[tuple[str, str, str | None, str]] = []
        for raw_name, raw_code in manual.items():
            normalized = _normalize_inventory_rule_name(raw_name)
            code = str(raw_code or "").strip().upper()
            if not normalized or not code:
                raise ValueError(f"库存映射文件包含空名称或空 SKU：{raw_name}")
            display_name = _LEGACY_MAPPING_DISPLAY_NAMES.get(normalized, str(raw_name).strip())
            rows.append(("mapping", display_name, code, ""))
        for raw_name, raw_reason in ignored.items():
            normalized = _normalize_inventory_rule_name(raw_name)
            if not normalized:
                raise ValueError(f"库存忽略文件包含空名称：{raw_name}")
            display_name = _LEGACY_MAPPING_DISPLAY_NAMES.get(normalized, str(raw_name).strip())
            rows.append(("ignore", display_name, None, str(raw_reason or "").strip() or "用户确认全局忽略"))

        has_products = connection.execute(
            "select 1 from sqlite_master where type='table' and name='products'"
        ).fetchone() is not None
        if has_products and connection.execute("select count(*) from products").fetchone()[0]:
            for rule_type, display_name, product_code, _ in rows:
                if rule_type != "mapping":
                    continue
                product = connection.execute(
                    "select code, status from products where normalized_code=?",
                    (_normalize_inventory_rule_name(product_code or ""),),
                ).fetchall()
                if len(product) != 1:
                    raise ValueError(f"库存映射的 SKU 不存在或不唯一：{display_name} → {product_code}")
                if product[0][1] and product[0][1] != "启用":
                    raise ValueError(f"库存映射的商品已停用：{display_name} → {product_code}")

        now = _now()
        for rule_type, display_name, product_code, reason in rows:
            normalized = _normalize_inventory_rule_name(display_name)
            existing = connection.execute(
                "select rule_type, product_code from inventory_resolution_rules where normalized_name=?",
                (normalized,),
            ).fetchone()
            if existing is not None:
                if existing[0] != rule_type or (product_code and existing[1] != product_code):
                    raise ValueError(f"库存映射规则冲突：{display_name}")
                continue
            connection.execute(
                """insert into inventory_resolution_rules(
                    rule_type, source_name, normalized_name, product_code, reason, created_at, updated_at
                ) values(?,?,?,?,?,?,?)""",
                (rule_type, display_name, normalized, product_code, reason, now, now),
            )
        connection.execute(
            "insert into workflow_metadata(key,value,updated_at) values(?,?,?)",
            ("inventory_mapping_migration_v1", json.dumps({"manual": len(manual), "ignored": len(ignored)}, ensure_ascii=False), now),
        )
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()

    # The legacy merge can create a central factory_orders table from an old
    # schema after the first ensure_schema call. Run the lightweight migration
    # once more so direct detail reads are safe before OrderIndexStore opens.
    ensure_schema(central)

    archive = state_dir / "migration-archives" / datetime.now().strftime("%Y%m%d-%H%M%S")
    archive.mkdir(parents=True, exist_ok=True)
    destination = archive / source.name
    if not destination.exists():
        shutil.move(str(source), str(destination))
    return {
        "status": "completed",
        "central": str(central),
        "source": str(source),
        "archived": str(destination),
        "manual": len(manual),
        "ignored": len(ignored),
    }


def _copy_table(source: sqlite3.Connection, target: sqlite3.Connection, table: str) -> bool:
    exists = source.execute(
        "select sql from sqlite_master where type='table' and name=?", (table,)
    ).fetchone()
    if exists is None:
        return False
    target.execute(f"drop table if exists {table}")
    target.execute(exists[0])
    columns = [row[1] for row in source.execute(f"pragma table_info({table})").fetchall()]
    if columns:
        names = ",".join('"' + column.replace('"', '""') + '"' for column in columns)
        target.executemany(
            f"insert into {table}({names}) values({','.join('?' for _ in columns)})",
            source.execute(f"select {names} from {table}").fetchall(),
        )
    return True


def migrate_legacy_databases(state_dir: Path) -> dict[str, Any]:
    """Merge the old order-index DB into the central DB without deletion.

    The operation is idempotent.  Legacy files are copied to a timestamped
    archive only after their data has been committed to the central database.
    """
    central = database_path(state_dir)
    ensure_schema(central)
    legacy_paths = [state_dir / "order-index.sqlite3"]
    existing = [path for path in legacy_paths if path.is_file() and path != central]
    outbound_json = state_dir / "inventory-outbound-records.json"
    if not existing and not outbound_json.is_file():
        return {"central": str(central), "migrated": [], "status": "no_legacy_files"}

    connection = sqlite3.connect(central)
    migrated: list[str] = []
    try:
        for legacy in existing:
            source = sqlite3.connect(legacy)
            try:
                tables = [
                    "orders", "factory_orders", "source_files", "sync_runs", "sync_changes",
                    "ignored_aimes_factory_orders", "aimes_order_assignments", "aimes_review_rows",
                    "ignored_server_folders", "active_issues", "temporary_orders",
                ]
                for table in tables:
                    # Existing central tables are preserved; row-level merge is
                    # handled by INSERT OR IGNORE for stable primary keys.
                    sql = source.execute(
                        "select sql from sqlite_master where type='table' and name=?", (table,)
                    ).fetchone()
                    if sql is None:
                        continue
                    columns = [row[1] for row in source.execute(f"pragma table_info({table})").fetchall()]
                    if not columns:
                        continue
                    target_exists = connection.execute(
                        "select 1 from sqlite_master where type='table' and name=?", (table,)
                    ).fetchone()
                    if target_exists is None:
                        connection.execute(sql[0])
                    names = ",".join('"' + column.replace('"', '""') + '"' for column in columns)
                    rows = source.execute(f"select {names} from {table}").fetchall()
                    placeholders = ",".join("?" for _ in columns)
                    for row in rows:
                        try:
                            connection.execute(
                                f"insert or ignore into {table}({names}) values({placeholders})", row
                            )
                        except sqlite3.Error:
                            # A newer central schema may intentionally omit a
                            # historical column. The source remains archived.
                            continue
                migrated.append(str(legacy))
            finally:
                source.close()
        connection.execute(
            "insert into workflow_metadata(key,value,updated_at) values('legacy_migration',?,?) "
            "on conflict(key) do update set value=excluded.value, updated_at=excluded.updated_at",
            (json.dumps(migrated, ensure_ascii=False), _now()),
        )
        if outbound_json.is_file():
            try:
                payload = json.loads(outbound_json.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                payload = {}
            records = payload.get("records", {}) if isinstance(payload, dict) else {}
            for record in records.values() if isinstance(records, dict) else []:
                document = str(record.get("document_number", "")).strip()
                if not document:
                    continue
                connection.execute(
                    """insert or ignore into outbound_documents(
                        document_number,document_type,order_id,factory_order,status,source,issued_at,source_path,updated_at
                    ) values(?,?,?,?,?,?,?,?,?)""",
                    (document, str(record.get("kind", "")), str(record.get("order_id", "")),
                     str(record.get("remark", "")), str(record.get("status", "已出库")), "legacy-json",
                     str(record.get("synced_at", "")), str(record.get("traveler_path", "")), _now()),
                )
        connection.commit()
    finally:
        connection.close()

    archive = state_dir / "migration-archives" / datetime.now().strftime("%Y%m%d-%H%M%S")
    archive.mkdir(parents=True, exist_ok=True)
    archived: list[str] = []
    for legacy in existing:
        destination = archive / legacy.name
        if not destination.exists():
            shutil.copy2(legacy, destination)
            archived.append(str(destination))
    return {"central": str(central), "migrated": migrated, "archived": archived, "status": "completed"}


def _cache_rows(path: Path, cache_name: str) -> dict[str, Any]:
    ensure_schema(path)
    connection = sqlite3.connect(path)
    try:
        return {
            row[0]: json.loads(row[1])
            for row in connection.execute(
                "select cache_key,value_json from business_cache where cache_name=?", (cache_name,)
            ).fetchall()
        }
    finally:
        connection.close()


def read_cache(path: Path, cache_name: str, legacy: Path | None = None, default: Any = None) -> Any:
    values = _cache_rows(path, cache_name)
    if values:
        return values.get("value", default)
    if legacy and legacy.is_file():
        try:
            value = json.loads(legacy.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return default
        write_cache(path, cache_name, value)
        return value
    return default


def write_cache(path: Path, cache_name: str, value: Any) -> None:
    ensure_schema(path)
    connection = sqlite3.connect(path)
    try:
        connection.execute(
            "insert into business_cache(cache_name,cache_key,value_json,updated_at) values(?,?,?,?) "
            "on conflict(cache_name,cache_key) do update set value_json=excluded.value_json, updated_at=excluded.updated_at",
            (cache_name, "value", json.dumps(value, ensure_ascii=False, sort_keys=True), _now()),
        )
        connection.commit()
    finally:
        connection.close()
