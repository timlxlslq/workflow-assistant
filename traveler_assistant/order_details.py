"""Read-only order detail projections for the desktop dashboard and future web API."""

from __future__ import annotations

import sqlite3
from pathlib import Path

from .core import Config
from .database import ensure_schema
from .inventory import InventoryMappings, ignored_hardware_reason


def order_detail(config: Config, order_id: str) -> dict:
    ensure_schema(config.workflow_database)
    connection = sqlite3.connect(config.workflow_database)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute(
            """
            create table if not exists order_installation_days(
                order_id text not null,
                date_type text not null check(date_type in ('planned', 'actual')),
                install_date text not null,
                installer text not null default '',
                updated_at text not null,
                primary key(order_id, date_type, install_date)
            )
            """
        )
        order = connection.execute(
            "select * from orders where order_id=?", (order_id.upper(),)
        ).fetchone()
        installation_rows = connection.execute(
            """
            select date_type, install_date, installer
            from order_installation_days
            where order_id=?
            order by date_type, install_date
            """,
            (order_id.upper(),),
        ).fetchall()
        installation = {"planned": [], "actual": []}
        for row in installation_rows:
            installation[row[0]].append({"date": row[1], "installer": row[2]})
        factories = connection.execute(
            """
            select factory_order, factory_name, sales_order_name, split_time,
                   report_state, ownership_status, has_hardware, optimized,
                   outbound_status, outbound_document, outbound_mode,
                   outbound_fingerprint, production_batch_id
            from factory_orders where order_id=? and aimes_status='active' order by factory_order
            """, (order_id.upper(),)
        ).fetchall()
        materials = connection.execute(
            """
            select material_type, color, thickness,
                   quantity, unit, edge, source_type, source_path, updated_at
            from material_items where order_id=? order by material_type, color, thickness
            """, (order_id.upper(),)
        ).fetchall()
        hardware_rows = connection.execute(
            """
            select factory_order, scope, product_code, name, spec, quantity,
                   unit, source_type, active, remarks, updated_at
            from hardware_items
            where order_id=? and active=1
              and exists (
                  select 1 from factory_orders
                  where factory_orders.factory_order=hardware_items.factory_order
                    and factory_orders.order_id=hardware_items.order_id
                    and factory_orders.aimes_status='active'
              )
            order by factory_order, product_code, name
            """, (order_id.upper(),)
        ).fetchall()
        mappings = InventoryMappings(config.workflow_database)
        hardware = [
            row for row in hardware_rows
            if ignored_hardware_reason(mappings, row[3], row[2]) is None
        ]
        outbound = connection.execute(
            """
            select od.document_number, od.document_type,
                   coalesce(
                       (
                           select group_concat(linked.factory_order, ',')
                           from outbound_document_factories linked
                           where linked.document_number = od.document_number
                           order by linked.factory_order
                       ),
                       od.factory_order
                   ) as factory_order,
                   od.status, od.source, od.issued_at, od.source_path, od.updated_at
            from outbound_documents od
            where od.order_id=? order by od.issued_at desc, od.document_number
            """, (order_id.upper(),)
        ).fetchall()
        issues = connection.execute(
            """
            select issue_key, kind, factory_order, path, message, status, last_seen
            from active_issues where order_id=? and status='open' order by last_seen desc
            """, (order_id.upper(),)
        ).fetchall()
        return {
            "order": dict(order) if order else {"order_id": order_id.upper()},
            "installation": installation,
            "factory_orders": [dict(row) for row in factories],
            "materials": [dict(row) for row in materials],
            "hardware": [dict(row) for row in hardware],
            "outbound_documents": [dict(row) for row in outbound],
            "issues": [dict(row) for row in issues],
        }
    finally:
        connection.close()
