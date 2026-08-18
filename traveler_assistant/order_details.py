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
        order = connection.execute(
            "select * from orders where order_id=?", (order_id.upper(),)
        ).fetchone()
        factories = connection.execute(
            """
            select factory_order, factory_name, sales_order_name, split_time,
                   report_state, ownership_status, has_hardware, optimized,
                   outbound_status, outbound_document, production_batch_id
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
            select document_number, document_type, factory_order, status,
                   source, issued_at, source_path, updated_at
            from outbound_documents where order_id=? order by issued_at desc, document_number
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
            "factory_orders": [dict(row) for row in factories],
            "materials": [dict(row) for row in materials],
            "hardware": [dict(row) for row in hardware],
            "outbound_documents": [dict(row) for row in outbound],
            "issues": [dict(row) for row in issues],
        }
    finally:
        connection.close()
