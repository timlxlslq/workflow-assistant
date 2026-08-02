from __future__ import annotations

import argparse
import copy
import json
import math
import os
import re
import shutil
import tempfile
from collections import defaultdict
from dataclasses import asdict, dataclass
from decimal import Decimal, ROUND_HALF_UP
from datetime import date, datetime
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.cell.cell import MergedCell
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import range_boundaries

from .core import Config, FittingItem, RuleError, lookup_aimes_names, parse_fittings_groups, progress
from .inventory import InventoryMappings


ORDER_FOLDER_RE = re.compile(r"^(PP\d{4}(?:-\d+)?|CS\d{3})$", re.IGNORECASE)
FACTORY_RE = re.compile(r"^F\d+$", re.IGNORECASE)
EPSILON = 1e-9


@dataclass(frozen=True)
class MaterialItem:
    kind: str
    thickness: float
    color: str
    quantity: float


@dataclass(frozen=True)
class PreviewFitting:
    key: str
    name: str
    code: str
    size: str
    unit: str
    quantity: float
    ignored: bool


@dataclass
class FactoryPreview:
    factory_order: str
    order_name: str
    fittings: list[PreviewFitting]


@dataclass
class OrderPreview:
    order_id: str
    folder: Path
    materials_path: Path
    materials_sheet_name: str
    materials: list[MaterialItem]
    edge_banding: dict[str, float]
    factories: list[FactoryPreview]
    warnings: list[str]


def _text(value) -> str:
    return "" if value is None else str(value).strip()


def _number(value, field: str) -> float:
    if value in (None, "") or (isinstance(value, str) and not value.strip()):
        return 0.0
    try:
        return float(value)
    except (TypeError, ValueError) as exc:
        raise RuleError("invalid_number", f"{field} 不是有效数字：{value}") from exc


def _integer(value, field: str) -> float:
    number = _number(value, field)
    if not math.isfinite(number) or abs(number - round(number)) > EPSILON:
        raise RuleError("fractional_material", f"{field} 数量为 {number:g}，板材数量必须为整数，请人工检查")
    if number < 0:
        raise RuleError("negative_material", f"{field} 数量为负数：{number:g}")
    return float(round(number))


def _integer_cell(cell, field: str) -> float:
    """Read the integer Excel displays, while still rejecting visible decimals."""
    number = _number(cell.value, field)
    if not math.isfinite(number) or number < 0:
        raise RuleError("negative_material", f"{field} 数量无效：{number:g}")
    if abs(number - round(number)) <= EPSILON:
        return float(round(number))
    first_section = _text(cell.number_format).split(";", 1)[0]
    if first_section.lower() != "general" and "." not in first_section and re.search(r"[0#?]", first_section):
        displayed = Decimal(str(number)).quantize(Decimal("1"), rounding=ROUND_HALF_UP)
        return float(displayed)
    raise RuleError("fractional_material", f"{field} 数量为 {number:g}，板材数量必须为整数，请人工检查")


def _fmt(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else f"{value:g}"


def _normalized_label(value) -> str:
    return re.sub(r"\s+", "", _text(value)).lower()


def _canonical_color(value: str) -> str:
    color = _text(value)
    if re.fullmatch(r"khaki(?:\s*\(7x9\))?", color, re.IGNORECASE):
        return "Penelope FA44"
    return color


def _state_file(config: Config) -> Path:
    return config.state_dir / "order-workflow-cache.json"


def _load_state(config: Config) -> dict:
    path = _state_file(config)
    if not path.is_file():
        return {"factory_names": {}, "ignored_fittings": {}}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"factory_names": {}, "ignored_fittings": {}}
    value.setdefault("factory_names", {})
    value.setdefault("ignored_fittings", {})
    return value


def _save_state(config: Config, state: dict) -> None:
    path = _state_file(config)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    os.replace(temporary, path)


def resolve_source_root(configured: Path) -> Path:
    if configured.is_dir():
        return configured
    parts = configured.parts
    if len(parts) >= 4 and parts[1] == "Volumes":
        volume_name = parts[2]
        relative = Path(*parts[3:])
        volumes = Path("/Volumes")
        if volumes.is_dir():
            candidates = sorted(
                (
                    item / relative
                    for item in volumes.iterdir()
                    if item.is_dir() and re.fullmatch(re.escape(volume_name) + r"(?:-\d+)?", item.name, re.IGNORECASE)
                ),
                key=lambda item: (item.parent.name.lower() != volume_name.lower(), item.parent.name.lower()),
            )
            for candidate in candidates:
                if candidate.is_dir():
                    return candidate
    raise RuleError("server_unavailable", f"服务器目录不可访问：{configured}")


def list_order_folders(config: Config) -> list[dict]:
    root = resolve_source_root(config.source_root)
    rows = []
    for folder in root.iterdir():
        if not folder.is_dir() or not ORDER_FOLDER_RE.fullmatch(folder.name):
            continue
        rows.append({
            "order_id": folder.name.upper(),
            "path": str(folder),
            "modified_at": datetime.fromtimestamp(folder.stat().st_mtime).isoformat(timespec="seconds"),
        })
    return sorted(rows, key=lambda row: row["order_id"], reverse=True)


def _find_label_row(ws, label: str) -> int:
    wanted = _normalized_label(label)
    for row in range(1, ws.max_row + 1):
        if any(_normalized_label(ws.cell(row, col).value) == wanted for col in range(1, ws.max_column + 1)):
            return row
    raise RuleError("materials_schema", f"materials 文件缺少“{label}”")


def _label_column(ws, row: int, label: str) -> int:
    wanted = _normalized_label(label)
    for col in range(1, ws.max_column + 1):
        if _normalized_label(ws.cell(row, col).value) == wanted:
            return col
    raise RuleError("materials_schema", f"materials 文件缺少“{label}”")


def parse_order_materials(order_id: str, path: Path) -> tuple[str, list[MaterialItem], dict[str, float]]:
    wb = load_workbook(path, data_only=True, read_only=True)
    if len(wb.sheetnames) != 1:
        raise RuleError("materials_schema", f"materials 文件必须只有一个工作簿，当前为：{wb.sheetnames}")
    ws = wb[wb.sheetnames[0]]
    total_row = _find_label_row(ws, "Total Qty:")
    color_title_row = _find_label_row(ws, "Color Table")
    header_row = 2
    header_map = {
        _normalized_label(ws.cell(header_row, col).value): col
        for col in range(1, ws.max_column + 1)
        if _text(ws.cell(header_row, col).value)
    }
    required = ["3/4 Plywood", "5/8 Plywood", "1/4 Plywood"]
    if any(_normalized_label(label) not in header_map for label in required):
        raise RuleError("materials_schema", "materials 文件缺少 Plywood 数量列")

    plywood = []
    for label, thickness in zip(required, (18.0, 14.5, 5.4)):
        col = header_map[_normalized_label(label)]
        plywood.append(MaterialItem("plywood", thickness, "", _integer_cell(ws.cell(total_row, col), label)))

    color_header_row = None
    for row in range(color_title_row + 1, min(ws.max_row, color_title_row + 5) + 1):
        if any(_normalized_label(ws.cell(row, col).value) == "color:" for col in range(1, ws.max_column + 1)):
            color_header_row = row
            break
    if color_header_row is None:
        raise RuleError("materials_schema", "materials Color Table 缺少 Color 行")
    row_34 = _find_label_row(ws, "Sheets (3/4):")
    row_14 = _find_label_row(ws, "Sheets (1/4):")
    row_edge = _find_label_row(ws, "Edge Banding (m):")

    colors: list[tuple[int, str]] = []
    for col in range(1, ws.max_column + 1):
        color = _text(ws.cell(color_header_row, col).value)
        if color and _normalized_label(color) != "color:":
            colors.append((col, color))

    panels: list[MaterialItem] = []
    edges: dict[str, float] = {}
    if colors:
        for col, source_color in colors:
            color = _canonical_color(source_color)
            qty_34 = _integer_cell(ws.cell(row_34, col), f"{source_color} Sheets (3/4)")
            qty_14 = _integer_cell(ws.cell(row_14, col), f"{source_color} Sheets (1/4)")
            edge = _number(ws.cell(row_edge, col).value, f"{source_color} Edge Banding")
            if qty_34:
                panels.append(MaterialItem("panel", 19.1, color, qty_34))
            if qty_14:
                panels.append(MaterialItem("panel", 8.0, color, qty_14))
            if qty_34 or qty_14:
                if edge <= 0:
                    raise RuleError("missing_edge", f"{source_color} 有 Panel 数量，但封边条为空或为 0")
                edges[color] = edge
    else:
        finish_34 = header_map.get(_normalized_label("3/4 Finish Panel"))
        finish_14 = header_map.get(_normalized_label("1/4 Finish Panel"))
        edge_col = header_map.get(_normalized_label("Edge Banding (m)"))
        color_col = header_map.get(_normalized_label("Color"))
        if not all((finish_34, finish_14, edge_col, color_col)):
            raise RuleError("materials_schema", "单颜色 materials 缺少 Panel、封边或 Color 列")
        source_color = _text(ws.cell(total_row, color_col).value)
        qty_34 = _integer_cell(ws.cell(total_row, finish_34), "Sheets (3/4)")
        qty_14 = _integer_cell(ws.cell(total_row, finish_14), "Sheets (1/4)")
        edge = _number(ws.cell(total_row, edge_col).value, "Edge Banding")
        if qty_34 or qty_14:
            if not source_color:
                raise RuleError("materials_schema", "单颜色 materials 的 Total Qty 行缺少 Color")
            if edge <= 0:
                raise RuleError("missing_edge", f"{source_color} 有 Panel 数量，但封边条为空或为 0")
            color = _canonical_color(source_color)
            if qty_34:
                panels.append(MaterialItem("panel", 19.1, color, qty_34))
            if qty_14:
                panels.append(MaterialItem("panel", 8.0, color, qty_14))
            edges[color] = edge
    return wb.sheetnames[0], plywood + panels, edges


def _next_value_on_row(ws, row: int, col: int) -> str:
    for candidate in range(col + 1, ws.max_column + 1):
        value = _text(ws.cell(row, candidate).value)
        if value:
            return value
    return ""


def parse_board_identity(path: Path) -> tuple[str, str]:
    wb = load_workbook(path, data_only=True, read_only=True)
    ws = wb[wb.sheetnames[0]]
    factory = ""
    name = ""
    for row in range(1, ws.max_row + 1):
        for col in range(1, ws.max_column + 1):
            label = _normalized_label(ws.cell(row, col).value)
            if label == "订单号":
                factory = _next_value_on_row(ws, row, col).upper()
            elif label == "订单名称":
                name = _next_value_on_row(ws, row, col)
        if factory and name:
            break
    if not FACTORY_RE.fullmatch(factory) or not name:
        raise RuleError("board_identity", f"板材清单无法取得工厂单号或名称：{path}")
    return factory, name


def _fitting_signature(items: list[FittingItem]) -> tuple:
    return tuple(sorted(
        (
            _text(item.name),
            _text(item.code).upper(),
            _text(item.size),
            _text(item.unit),
            round(float(item.quantity), 6),
        )
        for item in items
    ))


def _has_positive_fitting_quantity(path: Path) -> bool | None:
    """Return None when the workbook cannot be opened, so corruption is never ignored."""
    try:
        wb = load_workbook(path, data_only=True, read_only=True)
    except Exception:
        # Empty AICNC reports can carry the same invalid A1:?0 worksheet
        # dimension as usable reports. Normal mode ignores that optional
        # dimension and lets us distinguish an empty report from corruption.
        try:
            wb = load_workbook(path, data_only=True, read_only=False)
        except Exception:
            return None
    for ws in wb.worksheets:
        for row in ws.iter_rows(min_col=11, max_col=11, values_only=True):
            value = row[0]
            if isinstance(value, (int, float)) and math.isfinite(float(value)) and float(value) > 0:
                return True
    return False


def _choose_fittings(folder: Path) -> tuple[dict[str, list[FittingItem]], list[str]]:
    occurrences: dict[str, list[tuple[Path, float, list[FittingItem], tuple]]] = defaultdict(list)
    warnings = []
    found_files = False
    for path in folder.rglob("*.xlsx"):
        if path.name.startswith("~$") or not path.name.lower().startswith("fittingslist"):
            continue
        found_files = True
        try:
            groups = parse_fittings_groups(path)
        except RuleError:
            has_quantity = _has_positive_fitting_quantity(path)
            if has_quantity is False:
                warnings.append(
                    f"{path.name} 无有效五金数量，已按无五金报表跳过；Traveler 仍可生成"
                )
                continue
            raise
        for factory, items in groups:
            if not any(item.quantity > 0 for item in items):
                warnings.append(
                    f"{path.name} 的 {factory} 没有有效五金数量，已按无五金处理"
                )
                continue
            occurrences[factory].append((path, path.stat().st_mtime, items, _fitting_signature(items)))
    if not occurrences:
        if not found_files:
            warnings.append("未找到 Fittingslist Excel，本订单将按无五金继续生成 Traveler")
        elif not warnings:
            warnings.append("所有 Fittingslist 均没有有效五金数量，本订单将按无五金继续生成 Traveler")
        return {}, warnings

    selected: dict[str, list[FittingItem]] = {}
    for factory, matches in sorted(occurrences.items()):
        newest_time = max(item[1] for item in matches)
        newest = [item for item in matches if abs(item[1] - newest_time) < EPSILON]
        newest_signatures = {item[3] for item in newest}
        if len(newest_signatures) > 1:
            raise RuleError(
                "fittings_timestamp_tie",
                f"{factory} 的多个最新 Fittingslist 修改时间相同但五金内容不同，请人工检查",
                files=[str(item[0]) for item in newest],
            )
        chosen = newest[0]
        selected[factory] = chosen[2]
        all_signatures = {item[3] for item in matches}
        if len(all_signatures) > 1:
            older = [str(item[0]) for item in matches if item[0] != chosen[0]]
            warnings.append(
                f"{factory} 在不同 Fittingslist 中内容不一致；已采用修改时间最新的 {chosen[0].name}"
                f"（{datetime.fromtimestamp(chosen[1]).isoformat(timespec='seconds')}），较旧文件：{'、'.join(older)}"
            )
        elif len(matches) > 1:
            warnings.append(f"{factory} 在 {len(matches)} 份 Fittingslist 中重复且内容一致，已自动去重")
    return selected, warnings


def _ignored_key(name: str, code: str, size: str, unit: str) -> str:
    payload = "\x1f".join((_text(name).lower(), _text(code).upper(), _text(size).lower(), _text(unit).lower()))
    import hashlib
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:20]


def _normalize_fittings(items: list[FittingItem], mappings: InventoryMappings) -> list[PreviewFitting]:
    direct = {"WJ-CBT": ("Shelf Holder", "pcs/个"), "71T950A": ("Hinge", "pcs/个")}
    rails = {"H-RAIL": ("H-Rail", "set/套"), "L-RAIL": ("L-Rail", "set/套")}
    aggregate: dict[tuple[str, str, str, str], float] = defaultdict(float)
    rail_sides: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    for item in items:
        code = _text(item.code).upper()
        if code in direct:
            name, unit = direct[code]
            aggregate[(name, code, "", unit)] += item.quantity
        elif code in rails:
            side = "right" if "right" in item.name.lower() else "left" if "left" in item.name.lower() else "unknown"
            rail_sides[code][side] += item.quantity
        else:
            aggregate[(_text(item.name), code, _text(item.size), _text(item.unit) or "pcs/个")] += item.quantity
    for code, sides in rail_sides.items():
        name, unit = rails[code]
        if set(sides) != {"left", "right"} or abs(sides["left"] - sides["right"]) > EPSILON:
            raise RuleError("rail_mismatch", f"{name} 左右数量不一致：{dict(sides)}")
        aggregate[(name, code, "", unit)] += sides["left"]
    result = []
    for (name, code, size, unit), quantity in sorted(aggregate.items()):
        key = _ignored_key(name, code, size, unit)
        result.append(PreviewFitting(
            key, name, code, size, unit, quantity,
            mappings.ignored_reason(name) is not None,
        ))
    return result


def _factory_names(config: Config, folder: Path, factories: set[str]) -> tuple[dict[str, str], list[str]]:
    names: dict[str, str] = {}
    for path in folder.rglob("*.xlsx"):
        if path.name.startswith("~$") or "板材清单" not in path.name:
            continue
        factory, name = parse_board_identity(path)
        previous = names.get(factory)
        if previous and previous != name:
            raise RuleError("factory_name_conflict", f"{factory} 在板材清单中对应多个名称：{previous} / {name}")
        names[factory] = name
    state = _load_state(config)
    cache = state["factory_names"]
    warnings = []
    missing = sorted(factories - set(names))
    cached = [factory for factory in missing if _text(cache.get(factory))]
    for factory in cached:
        names[factory] = _text(cache[factory])
    if cached:
        warnings.append(f"从本机缓存补充 {len(cached)} 个工厂单名称：{', '.join(cached)}")
    missing = sorted(factories - set(names))
    if missing:
        progress(f"板材清单缺少 {len(missing)} 个工厂单名称，正在查询 AIMES", factory_orders=missing)
        found = lookup_aimes_names(config, missing)
        names.update(found)
        cache.update(found)
        _save_state(config, state)
        warnings.append(f"从 AIMES 补充并缓存 {len(found)} 个工厂单名称：{', '.join(sorted(found))}")
    return names, warnings


def preview_order(config: Config, folder: Path) -> OrderPreview:
    if not folder.is_dir():
        raise RuleError("missing_order_folder", f"订单文件夹不存在：{folder}")
    match = ORDER_FOLDER_RE.fullmatch(folder.name)
    if not match:
        raise RuleError("invalid_order_folder", f"订单文件夹名称不符合 PP####、PP####-# 或 CS###：{folder.name}")
    order_id = match.group(1).upper()
    materials_files = sorted(
        path for path in folder.iterdir()
        if path.is_file() and path.suffix.lower() == ".xlsx"
        and "material" in path.name.lower() and not path.name.startswith("~$")
    )
    if not materials_files:
        raise RuleError("missing_materials", f"{order_id} 根目录找不到文件名包含 material 的 Excel")
    if len(materials_files) > 1:
        raise RuleError("multiple_materials", f"{order_id} 找到多个 material Excel，请只保留一个", files=[str(x) for x in materials_files])
    materials_path = materials_files[0]
    sheet_name, materials, edges = parse_order_materials(order_id, materials_path)
    if order_id.startswith("CS"):
        return OrderPreview(
            order_id, folder, materials_path, sheet_name, materials, edges, [],
            ["来料加工订单只读取板材和封边数量，不读取或写入五金"],
        )
    fittings, warnings = _choose_fittings(folder)
    names, name_warnings = _factory_names(config, folder, set(fittings))
    warnings.extend(name_warnings)
    board_only = sorted(set(names) - set(fittings))
    for factory in board_only:
        fittings[factory] = []
    if board_only:
        warnings.append(
            f"{', '.join(board_only)} 在板材清单中存在但没有有效五金数量，已按无五金工厂单处理"
        )
    if not fittings:
        raise RuleError("missing_factory_orders", "板材清单和五金文件都无法取得工厂单号，不能生成 Traveler")
    state = _load_state(config)
    legacy_ignored = state["ignored_fittings"]
    mappings = InventoryMappings(config.state_dir / "inventory" / "mappings.json")
    normalized = {
        factory: _normalize_fittings(items, mappings)
        for factory, items in sorted(fittings.items())
    }
    migrated = []
    for items in normalized.values():
        for item in items:
            if legacy_ignored.get(item.key):
                if mappings.ignored_reason(item.name) is None:
                    mappings.save_ignored(item.name, "用户在生产文件预览中选择忽略")
                migrated.append(item.key)
    if migrated:
        for key in migrated:
            legacy_ignored.pop(key, None)
        _save_state(config, state)
        normalized = {
            factory: _normalize_fittings(items, mappings)
            for factory, items in sorted(fittings.items())
        }
    factories = [
        FactoryPreview(factory, names[factory], normalized[factory])
        for factory in sorted(fittings)
    ]
    return OrderPreview(order_id, folder, materials_path, sheet_name, materials, edges, factories, warnings)


def _traveler_path(config: Config, order_id: str) -> Path:
    return config.order_root / order_id / f"Work Order Traveler({order_id}).xlsx"


def find_existing_traveler(config: Config, order_id: str) -> Path | None:
    """Return only the canonical one-order Traveler, never an ambiguous legacy file."""
    expected = _traveler_path(config, order_id)
    if expected.is_file():
        return expected
    folder = expected.parent
    if not folder.is_dir():
        return None
    expected_name = expected.name.casefold()
    matches = [
        path for path in folder.iterdir()
        if path.is_file() and path.name.casefold() == expected_name
    ]
    return matches[0] if len(matches) == 1 else None


def preview_payload(config: Config, preview: OrderPreview) -> dict:
    existing = find_existing_traveler(config, preview.order_id)
    return {
        "order_id": preview.order_id,
        "folder": str(preview.folder),
        "materials_file": str(preview.materials_path),
        "materials_sheet": preview.materials_sheet_name,
        "materials": [asdict(item) for item in preview.materials],
        "edge_banding": preview.edge_banding,
        "factories": [
            {
                "factory_order": factory.factory_order,
                "order_name": factory.order_name,
                "fittings": [asdict(item) for item in factory.fittings],
            }
            for factory in preview.factories
        ],
        "warnings": preview.warnings,
        "existing_traveler": str(existing) if existing else "",
    }


def set_ignored(
    config: Config,
    key: str,
    ignored: bool,
    name: str = "",
) -> None:
    state = _load_state(config)
    if key:
        if ignored and not name:
            # Compatibility path for preferences saved before the shared list existed.
            state["ignored_fittings"][key] = True
        else:
            state["ignored_fittings"].pop(key, None)
    _save_state(config, state)
    if name:
        mappings = InventoryMappings(config.state_dir / "inventory" / "mappings.json")
        if ignored:
            mappings.save_ignored(name, "用户在生产文件预览中选择忽略")
        else:
            mappings.remove_ignored(name)


def _copy_cell(source, target) -> None:
    if isinstance(source, MergedCell):
        return
    target.value = source.value
    if source.has_style:
        target._style = copy.copy(source._style)
    target.number_format = source.number_format
    target.font = copy.copy(source.font)
    target.fill = copy.copy(source.fill)
    target.border = copy.copy(source.border)
    target.alignment = copy.copy(source.alignment)
    target.protection = copy.copy(source.protection)


def _copy_worksheet(source, target_wb, title: str, index: int):
    target = target_wb.create_sheet(title, index)
    for row in source.iter_rows():
        for cell in row:
            _copy_cell(cell, target.cell(cell.row, cell.column))
    for merged in source.merged_cells.ranges:
        target.merge_cells(str(merged))
    for key, dimension in source.column_dimensions.items():
        target.column_dimensions[key] = copy.copy(dimension)
    for key, dimension in source.row_dimensions.items():
        target.row_dimensions[key] = copy.copy(dimension)
    target.sheet_format = copy.copy(source.sheet_format)
    target.sheet_properties = copy.copy(source.sheet_properties)
    target.page_margins = copy.copy(source.page_margins)
    target.page_setup = copy.copy(source.page_setup)
    target.print_options = copy.copy(source.print_options)
    target.freeze_panes = source.freeze_panes
    return target


def _copy_materials_sheet(source_path: Path, target_wb, after_index: int) -> str:
    source_wb = load_workbook(source_path, data_only=False)
    source = source_wb[source_wb.sheetnames[0]]
    title = "Usage List"
    if title in target_wb.sheetnames:
        target_wb.remove(target_wb[title])
    _copy_worksheet(source, target_wb, title, after_index + 1)
    return title


def _restore_template_pickinglist(config: Config, wb) -> None:
    template_wb = load_workbook(config.template, data_only=False)
    if "Pickinglist" not in template_wb.sheetnames:
        raise RuleError("template_schema", "Traveler 模板缺少 Pickinglist")
    index = wb.sheetnames.index("Pickinglist") if "Pickinglist" in wb.sheetnames else min(2, len(wb.sheetnames))
    if "Pickinglist" in wb.sheetnames:
        wb.remove(wb["Pickinglist"])
    _copy_worksheet(template_wb["Pickinglist"], wb, "Pickinglist", index)


def _write_merged(ws, row: int, col: int, value) -> None:
    cell = ws.cell(row, col)
    if not isinstance(cell, MergedCell):
        cell.value = value
        return
    for merged in ws.merged_cells.ranges:
        if merged.min_row <= row <= merged.max_row and merged.min_col <= col <= merged.max_col:
            ws.cell(merged.min_row, merged.min_col).value = value
            return


def _write_initial_traveler_date(ws) -> None:
    for row in ws.iter_rows():
        for cell in row:
            if _normalized_label(cell.value) == _normalized_label("Date/日期："):
                target = ws.cell(cell.row, cell.column + 1)
                if isinstance(target, MergedCell):
                    _write_merged(ws, cell.row, cell.column + 1, date.today())
                    for merged in ws.merged_cells.ranges:
                        if merged.min_row <= cell.row <= merged.max_row and merged.min_col <= cell.column + 1 <= merged.max_col:
                            target = ws.cell(merged.min_row, merged.min_col)
                            break
                else:
                    target.value = date.today()
                target.number_format = "yyyy.m.d"
                return
    raise RuleError("template_schema", "Traveler 模板缺少 Date/日期 字段")


def _snapshot_rows(ws, first: int, last: int) -> dict:
    return {
        "cells": {
            (row, col): copy.copy(ws.cell(row, col))
            for row in range(first, last + 1)
            for col in range(1, ws.max_column + 1)
            if not isinstance(ws.cell(row, col), MergedCell)
        },
        "heights": {row: ws.row_dimensions[row].height for row in range(first, last + 1)},
        "merges": [
            tuple(range_boundaries(str(merged)))
            for merged in ws.merged_cells.ranges
            if merged.min_row >= first and merged.max_row <= last
        ],
        "first": first,
        "last": last,
        "max_col": ws.max_column,
    }


def _paste_snapshot(ws, snapshot: dict, destination_row: int) -> None:
    offset = destination_row - snapshot["first"]
    for (row, col), source in snapshot["cells"].items():
        _copy_cell(source, ws.cell(row + offset, col))
    for row, height in snapshot["heights"].items():
        ws.row_dimensions[row + offset].height = height
    for min_col, min_row, max_col, max_row in snapshot["merges"]:
        ws.merge_cells(
            start_row=min_row + offset, start_column=min_col,
            end_row=max_row + offset, end_column=max_col,
        )


def _style_merged_row(ws, row: int, last_col: int, color: str) -> None:
    merges = [
        str(merged) for merged in ws.merged_cells.ranges
        if merged.min_row == merged.max_row == row
    ]
    for merged in merges:
        ws.unmerge_cells(merged)
    fill = PatternFill("solid", fgColor=color)
    for col in range(1, last_col + 1):
        cell = ws.cell(row, col)
        cell.fill = fill
        cell.font = copy.copy(cell.font)
        cell.font = Font(
            name=cell.font.name,
            size=cell.font.size,
            bold=True,
            italic=cell.font.italic,
            color=cell.font.color,
        )
        cell.alignment = copy.copy(cell.alignment)
        cell.alignment = Alignment(
            horizontal=cell.alignment.horizontal or "center",
            vertical="center",
            wrap_text=cell.alignment.wrap_text,
        )
    for merged in merges:
        ws.merge_cells(merged)


def _style_pickinglist_title(ws, last_col: int) -> None:
    for merged in list(ws.merged_cells.ranges):
        if merged.min_row <= 1 <= merged.max_row:
            ws.unmerge_cells(str(merged))
    ws["A1"] = "Picking List领料单"
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=last_col)
    ws["A1"].alignment = Alignment(horizontal="center", vertical="center")
    ws["A1"].font = copy.copy(ws["A1"].font)
    ws["A1"].font = Font(
        name=ws["A1"].font.name,
        size=max(ws["A1"].font.size or 0, 24),
        bold=True,
        color=ws["A1"].font.color,
    )
    ws.row_dimensions[1].height = max(ws.row_dimensions[1].height or 0, 32)


def _prepare_pickinglist(wb, preview: OrderPreview) -> None:
    ws = wb["Pickinglist"]
    original_merges = [tuple(range_boundaries(str(merged))) for merged in ws.merged_cells.ranges]
    table_last_col = max(
        [max_col for min_col, min_row, max_col, max_row in original_merges if max_row >= 3]
        or [ws.max_column]
    )
    for merged in list(ws.merged_cells.ranges):
        ws.unmerge_cells(str(merged))
    ws.delete_rows(4, 7)  # Remove the obsolete Panel section; rows now match the approved screenshot.
    for min_col, min_row, max_col, max_row in original_merges:
        if max_row < 3:
            ws.merge_cells(
                start_row=min_row, start_column=min_col,
                end_row=max_row, end_column=max_col,
            )
        elif min_row == max_row == 3:
            ws.merge_cells(
                start_row=min_row, start_column=min_col,
                end_row=max_row, end_column=max_col,
            )
        elif min_row >= 11:
            ws.merge_cells(
                start_row=min_row - 7, start_column=min_col,
                end_row=max_row - 7, end_column=max_col,
            )
    base = _snapshot_rows(ws, 3, 13)
    for merged in list(ws.merged_cells.ranges):
        if merged.min_row >= 3:
            ws.unmerge_cells(str(merged))
    ws.delete_rows(3, max(ws.max_row - 2, 1))

    _style_pickinglist_title(ws, table_last_col)
    cursor = 3
    block_colors = ("DDEBF7", "E2F0D9", "FFF2CC", "E4DFEC")
    for factory_index, factory in enumerate(preview.factories):
        if factory_index:
            ws.insert_rows(cursor, 1)
            ws.row_dimensions[cursor].height = 9
            cursor += 1
        included = [item for item in factory.fittings if not item.ignored]
        slots = max(4, len(included))
        block_height = 11 + (slots - 4)
        ws.insert_rows(cursor, block_height)
        _paste_snapshot(ws, base, cursor)
        if slots > 4:
            insertion = cursor + 7
            ws.insert_rows(insertion, slots - 4)
            template_row = cursor + 6
            for row in range(insertion, insertion + slots - 4):
                ws.row_dimensions[row].height = ws.row_dimensions[template_row].height
                for col in range(1, ws.max_column + 1):
                    _copy_cell(ws.cell(template_row, col), ws.cell(row, col))
                ws.merge_cells(start_row=row, start_column=3, end_row=row, end_column=4)
                ws.merge_cells(start_row=row, start_column=5, end_row=row, end_column=6)
        _write_merged(ws, cursor, 4, factory.order_name)
        _style_merged_row(ws, cursor, table_last_col, block_colors[factory_index % len(block_colors)])
        first_item_row = cursor + 3
        for index in range(slots):
            row = first_item_row + index
            item = included[index] if index < len(included) else None
            ws.cell(row, 1).value = index + 1
            # The source report's code identifies its own component; it is
            # not an inventory SKU and must never be written into SKU NO.
            ws.cell(row, 2).value = None
            _write_merged(ws, row, 3, item.name if item else None)
            _write_merged(ws, row, 5, item.unit if item else None)
            ws.cell(row, 7).value = item.quantity if item else None
        cursor += block_height


def generate_order_traveler(config: Config, preview: OrderPreview) -> Path:
    destination = _traveler_path(config, preview.order_id)
    destination_dir = destination.parent
    if destination.exists():
        raise RuleError("destination_exists", f"目标 Traveler 已存在，拒绝覆盖：{destination}")
    destination_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="order-traveler-") as temporary:
        draft = Path(temporary) / destination.name
        shutil.copy2(config.template, draft)
        wb = load_workbook(draft)
        if "WorkOrderTraveler" not in wb.sheetnames or "Pickinglist" not in wb.sheetnames:
            raise RuleError("template_schema", "Traveler 模板缺少 WorkOrderTraveler 或 Pickinglist")
        wb["WorkOrderTraveler"]["B5"] = preview.order_id
        _write_initial_traveler_date(wb["WorkOrderTraveler"])
        _copy_materials_sheet(preview.materials_path, wb, wb.sheetnames.index("WorkOrderTraveler"))
        _prepare_pickinglist(wb, preview)
        wb.save(draft)
        check = load_workbook(draft, data_only=False, read_only=True)
        if check.sheetnames[1] == "Pickinglist":
            raise RuleError("write_verification", "materials 工作簿未插入到第一个工作簿之后")
        os.replace(draft, destination)
    return destination


def update_order_traveler(config: Config, preview: OrderPreview) -> tuple[Path, Path]:
    existing = find_existing_traveler(config, preview.order_id)
    if not existing:
        raise RuleError("traveler_not_found", f"找不到可更新的 Traveler：{_traveler_path(config, preview.order_id)}")
    backup_dir = config.backup_root / preview.order_id
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y-%m-%d %H%M%S")
    backup = backup_dir / f"{existing.stem} backup {stamp}{existing.suffix}"
    shutil.copy2(existing, backup)
    with tempfile.TemporaryDirectory(prefix="order-traveler-update-") as temporary:
        draft = Path(temporary) / existing.name
        shutil.copy2(existing, draft)
        wb = load_workbook(draft)
        if "WorkOrderTraveler" not in wb.sheetnames:
            raise RuleError("traveler_schema", "现有 Traveler 缺少 WorkOrderTraveler")
        wb["WorkOrderTraveler"]["B5"] = preview.order_id
        removable = [
            name for name in wb.sheetnames
            if name == "Usage List" or (
                wb.sheetnames.index(name) == 1
                and (name == preview.materials_sheet_name or name.casefold().startswith("sheet1"))
            )
        ]
        for name in removable:
            wb.remove(wb[name])
        _copy_materials_sheet(preview.materials_path, wb, wb.sheetnames.index("WorkOrderTraveler"))
        _restore_template_pickinglist(config, wb)
        _prepare_pickinglist(wb, preview)
        wb.save(draft)
        check = load_workbook(draft, data_only=False, read_only=True)
        if check.sheetnames[1] != "Usage List" or "Pickinglist" not in check.sheetnames:
            raise RuleError("write_verification", "更新后复查 Usage List 或 Pickinglist 失败")
        os.replace(draft, existing)
    return existing, backup


def _config_from_args(args) -> Config:
    config = Config()
    config.load_settings()
    for name in ("source_root", "order_root", "template", "backup_root", "state_dir"):
        value = getattr(args, name, None)
        if value:
            setattr(config, name, value)
    return config


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="traveler-assistant order")
    parser.add_argument("command", choices=("list", "preview", "set-ignore", "generate", "update"))
    parser.add_argument("--folder", type=Path)
    parser.add_argument("--key")
    parser.add_argument("--name", action="append", default=[])
    parser.add_argument("--ignored", choices=("true", "false"))
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--order-root", type=Path)
    parser.add_argument("--template", type=Path)
    parser.add_argument("--backup-root", type=Path)
    parser.add_argument("--state-dir", type=Path)
    args = parser.parse_args(argv)
    config = _config_from_args(args)
    try:
        if args.command == "list":
            result = {"orders": list_order_folders(config)}
        elif args.command == "set-ignore":
            if (not args.key and not args.name) or args.ignored is None:
                raise RuleError("invalid_arguments", "set-ignore 需要 --name（或旧版 --key）和 --ignored")
            ignored = args.ignored == "true"
            for name in args.name:
                set_ignored(config, "", ignored, name)
            if args.key:
                set_ignored(config, args.key, ignored)
            result = {
                "saved": True,
                "key": args.key or "",
                "names": args.name,
                "ignored": ignored,
            }
        else:
            if not args.folder:
                raise RuleError("invalid_arguments", f"{args.command} 需要 --folder")
            preview = preview_order(config, args.folder)
            result = preview_payload(config, preview)
            if args.command == "generate":
                result["created"] = str(generate_order_traveler(config, preview))
                result["existing_traveler"] = result["created"]
            elif args.command == "update":
                updated, backup = update_order_traveler(config, preview)
                result["updated"] = str(updated)
                result["backup"] = str(backup)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except RuleError as exc:
        print(json.dumps({"fatal": {"code": exc.code, "message": str(exc), **exc.context}}, ensure_ascii=False, indent=2))
        return 2
    except Exception as exc:
        print(json.dumps({
            "fatal": {
                "code": "unexpected_excel_error",
                "message": f"Excel 文件无法读取，请检查文件是否损坏或仍在编辑：{exc}",
            }
        }, ensure_ascii=False, indent=2))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
