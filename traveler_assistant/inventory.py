from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
from collections import Counter
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Iterable

from openpyxl import load_workbook

from .core import Config, RuleError, _normalize_name, _text, progress


TRAVELER_RE = re.compile(r"^Work Order Traveler\(.+\)\.xlsx$", re.IGNORECASE)
PP_FOLDER_RE = re.compile(r"^(?:PP\d{4}(?:-\d+)?|CS\d{3})$", re.IGNORECASE)
TB_RE = re.compile(r"^TB(\d+)$", re.IGNORECASE)
PANEL_RE = re.compile(r"^(\d+(?:\.\d+)?)mm--(.+)$", re.IGNORECASE)
EDGE_RE = re.compile(r"^Edge banding-+(.+)$", re.IGNORECASE)
REQUIRED_PRODUCT_HEADERS = {"商品类别", "*商品编号", "商品名称", "规格型号", "状态"}


@dataclass
class TravelerItem:
    row: int
    section: str
    name: str
    quantity: float
    document_remark: str = ""


@dataclass
class TravelerData:
    path: Path
    pp_folder: str
    order_id: str
    order_name: str
    items: list[TravelerItem]
    zero_items: list[TravelerItem]
    documents: dict[str, list[TravelerItem]]
    modified_at: str
    fingerprint: str

    def content_snapshot(self) -> dict:
        return {
            "order_id": self.order_id,
            "documents": {
                remark: [asdict(item) for item in items]
                for remark, items in sorted(self.documents.items())
            },
            "items": [asdict(item) for item in self.items],
            "zero_items": [asdict(item) for item in self.zero_items],
        }


@dataclass
class Product:
    category: str
    code: str
    name: str
    spec: str
    status: str
    remark: str = ""
    unit: str = ""


@dataclass
class OutboundItem:
    traveler_name: str
    product_code: str
    product_name: str
    quantity: float
    section: str
    match_source: str
    document_remark: str = ""


@dataclass
class InventoryPreview:
    traveler: TravelerData
    outbound_items: list[OutboundItem]
    ignored_items: list[dict] = field(default_factory=list)
    missing_items: list[dict] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def ready(self) -> bool:
        return not self.missing_items

    def payload(self) -> dict:
        documents = self.document_payloads()
        return {
            "traveler": {
                "path": str(self.traveler.path),
                "pp_folder": self.traveler.pp_folder,
                "order_id": self.traveler.order_id,
                "order_name": self.traveler.order_name,
                "modified_at": self.traveler.modified_at,
                "fingerprint": self.traveler.fingerprint,
            },
            "outbound_items": [asdict(item) for item in self.outbound_items],
            "zero_items": [asdict(item) for item in self.traveler.zero_items],
            "ignored_items": self.ignored_items,
            "missing_items": self.missing_items,
            "warnings": self.warnings,
            "documents": documents,
            "ready": self.ready,
        }

    def document_payloads(self) -> list[dict]:
        mapped: dict[str, list[OutboundItem]] = {}
        for item in self.outbound_items:
            mapped.setdefault(item.document_remark, []).append(item)
        ignored_by_remark: dict[str, list[dict]] = {}
        for item in self.ignored_items:
            ignored_by_remark.setdefault(str(item.get("document_remark", "")), []).append(item)
        return [
            {
                "remark": remark,
                "kind": "materials" if remark == self.traveler.order_id else "hardware",
                "items": [asdict(item) for item in mapped.get(remark, [])],
                "ignored_items": ignored_by_remark.get(remark, []),
            }
            for remark in self.traveler.documents
        ]


def _fingerprint(payload: dict) -> str:
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def _find_header(row: Iterable, label: str) -> int | None:
    matches = [index for index, value in enumerate(row, 1) if _text(value) == label]
    if len(matches) > 1:
        raise RuleError("traveler_schema", f"Pickinglist 同一行出现多个“{label}”表头")
    return matches[0] if matches else None


def _order_name_candidates(ws) -> list[str]:
    candidates = []
    for row in ws.iter_rows():
        for index, cell in enumerate(row):
            if _text(cell.value) == "Name/工厂单名称":
                for neighbor in row[index + 1:]:
                    value = _text(neighbor.value)
                    if value:
                        candidates.append(value)
                        break
    return candidates


def _normalized_label(value) -> str:
    return re.sub(r"\s+", "", _text(value)).lower()


def _find_label_row(ws, label: str) -> int:
    wanted = _normalized_label(label)
    for row in range(1, ws.max_row + 1):
        if any(_normalized_label(ws.cell(row, col).value) == wanted for col in range(1, ws.max_column + 1)):
            return row
    raise RuleError("traveler_usage_schema", f"Usage List 缺少“{label}”")


def _displayed_integer(cell, label: str) -> float:
    value = cell.value
    if value in (None, ""):
        return 0.0
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise RuleError("traveler_quantity", f"{label} 不是有效数字：{value}")
    number = float(value)
    if number < 0:
        raise RuleError("traveler_quantity", f"{label} 不能为负数：{number:g}")
    if abs(number - round(number)) <= 1e-9:
        return float(round(number))
    first_format = _text(cell.number_format).split(";", 1)[0]
    if first_format.lower() != "general" and "." not in first_format and re.search(r"[0#?]", first_format):
        return float(Decimal(str(number)).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    raise RuleError("traveler_quantity", f"{label} 数量为 {number:g}，板材数量必须为整数")


def _nonnegative_number(cell, label: str) -> float:
    value = cell.value
    if value in (None, ""):
        return 0.0
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
        raise RuleError("traveler_quantity", f"{label} 不是有效数字：{value}")
    number = float(value)
    if number < 0:
        raise RuleError("traveler_quantity", f"{label} 不能为负数：{number:g}")
    return number


def _canonical_usage_color(value: str) -> str:
    color = _text(value)
    if re.fullmatch(r"khaki(?:\s*\(7x9\))?", color, re.IGNORECASE):
        return "Penelope FA44"
    return color


def _usage_list_items(ws, order_id: str) -> tuple[list[TravelerItem], list[TravelerItem]]:
    total_row = _find_label_row(ws, "Total Qty:")
    color_title_row = _find_label_row(ws, "Color Table")
    header_map = {
        _normalized_label(ws.cell(2, col).value): col
        for col in range(1, ws.max_column + 1)
        if _text(ws.cell(2, col).value)
    }
    positive = []
    zero = []

    def add(row: int, name: str, quantity: float) -> None:
        item = TravelerItem(row, "板材与封边", name, quantity, order_id)
        (positive if quantity > 0 else zero).append(item)

    for label, name in (
        ("3/4 Plywood", "18mm--Plywood"),
        ("5/8 Plywood", "14.5mm--Plywood"),
        ("1/4 Plywood", "5.4mm--Plywood"),
    ):
        col = header_map.get(_normalized_label(label))
        if not col:
            raise RuleError("traveler_usage_schema", f"Usage List 缺少 {label} 列")
        add(total_row, name, _displayed_integer(ws.cell(total_row, col), label))

    color_row = None
    for row in range(color_title_row + 1, min(ws.max_row, color_title_row + 5) + 1):
        if any(_normalized_label(ws.cell(row, col).value) == "color:" for col in range(1, ws.max_column + 1)):
            color_row = row
            break
    if color_row is None:
        raise RuleError("traveler_usage_schema", "Usage List 的 Color Table 缺少 Color 行")
    row_34 = _find_label_row(ws, "Sheets (3/4):")
    row_14 = _find_label_row(ws, "Sheets (1/4):")
    row_edge = _find_label_row(ws, "Edge Banding (m):")
    colors = [
        (col, _text(ws.cell(color_row, col).value))
        for col in range(1, ws.max_column + 1)
        if _text(ws.cell(color_row, col).value)
        and _normalized_label(ws.cell(color_row, col).value) != "color:"
    ]
    single_total_headers = all(
        header_map.get(_normalized_label(label))
        for label in ("3/4 Finish Panel", "1/4 Finish Panel", "Edge Banding (m)")
    )
    if len(colors) > 1 or (colors and not single_total_headers):
        for col, source_color in colors:
            color = _canonical_usage_color(source_color)
            qty_34 = _displayed_integer(ws.cell(row_34, col), f"{color} Sheets (3/4)")
            qty_14 = _displayed_integer(ws.cell(row_14, col), f"{color} Sheets (1/4)")
            edge = _nonnegative_number(ws.cell(row_edge, col), f"{color} Edge Banding")
            add(row_34, f"19.1mm--{color}", qty_34)
            add(row_14, f"8mm--{color}", qty_14)
            add(row_edge, f"Edge banding--{color}", edge)
    else:
        required = {
            "3/4 Finish Panel": "19.1mm",
            "1/4 Finish Panel": "8mm",
        }
        color_col = header_map.get(_normalized_label("Color"))
        edge_col = header_map.get(_normalized_label("Edge Banding (m)"))
        if not color_col or not edge_col:
            raise RuleError("traveler_usage_schema", "单颜色 Usage List 缺少 Color 或 Edge Banding 列")
        color = _canonical_usage_color(
            colors[0][1] if colors else _text(ws.cell(total_row, color_col).value)
        )
        if not color:
            raise RuleError("traveler_usage_schema", "单颜色 Usage List 缺少颜色名称")
        for label, thickness in required.items():
            col = header_map.get(_normalized_label(label))
            if not col:
                raise RuleError("traveler_usage_schema", f"单颜色 Usage List 缺少 {label} 列")
            add(total_row, f"{thickness}--{color}", _displayed_integer(ws.cell(total_row, col), label))
        edge = _nonnegative_number(ws.cell(total_row, edge_col), f"{color} Edge Banding")
        add(total_row, f"Edge banding--{color}", edge)
    return positive, zero


def parse_traveler(path: Path) -> TravelerData:
    if not path.is_file() or path.suffix.lower() != ".xlsx":
        raise RuleError("traveler_missing", f"Traveler 文件不存在或格式不是 xlsx：{path}")
    try:
        wb = load_workbook(path, data_only=True, read_only=True)
    except Exception as exc:
        raise RuleError("traveler_open", f"无法打开 Traveler：{path.name}") from exc
    required = {"WorkOrderTraveler", "Usage List", "Pickinglist"}
    if not required.issubset(wb.sheetnames):
        raise RuleError("traveler_schema", f"Traveler 缺少必要工作表：{sorted(required - set(wb.sheetnames))}")
    work_names = _order_name_candidates(wb["WorkOrderTraveler"])
    work_order = work_names[0].upper() if work_names else ""
    usage = wb["Usage List"]
    usage_order = ""
    for row in usage.iter_rows():
        for index, cell in enumerate(row):
            if _normalized_label(cell.value) == "job:":
                usage_order = next((_text(item.value).upper() for item in row[index + 1:] if _text(item.value)), "")
                break
        if usage_order:
            break
    folder_order = next((parent.name.upper() for parent in path.parents if PP_FOLDER_RE.fullmatch(parent.name)), "")
    filename_match = re.fullmatch(r"Work Order Traveler\(([^)]+)\)\.xlsx", path.name, re.IGNORECASE)
    filename_order = filename_match.group(1).strip().upper() if filename_match else ""
    candidates = [value for value in (folder_order, filename_order, usage_order, work_order) if PP_FOLDER_RE.fullmatch(value)]
    if not candidates:
        raise RuleError("traveler_identity", "无法从订单文件夹、文件名、Usage List 或 WorkOrderTraveler 取得订单号")
    order_id = candidates[0]
    if any(value != order_id for value in candidates[1:]):
        raise RuleError("traveler_identity", f"Traveler 订单号不一致：{candidates}")

    ws = wb["Pickinglist"]
    section = ""
    current_factory = ""
    name_col = qty_col = None
    fitting_totals: dict[tuple[str, str], TravelerItem] = {}
    fitting_zero: list[TravelerItem] = []
    documents: dict[str, list[TravelerItem]] = {}
    for row_number, row in enumerate(ws.iter_rows(values_only=True), 1):
        for index, value in enumerate(row):
            if _text(value) == "Name/工厂单名称":
                current_factory = next((_text(item) for item in row[index + 1:] if _text(item)), "")
                if not current_factory:
                    raise RuleError("traveler_identity", f"Pickinglist 第 {row_number} 行缺少工厂单名称")
                documents.setdefault(current_factory, [])
                section = ""
                name_col = qty_col = None
                break
        first = _text(row[0]) if row else ""
        if first and not isinstance(row[0], (int, float)) and first not in {"No.", "Picking List领料单", "Name/工厂单名称"}:
            if _find_header(row, "Name名字") is None and _find_header(row, "QTY数量") is None:
                section = first
                name_col = qty_col = None
                continue
        found_name = _find_header(row, "Name名字")
        found_qty = _find_header(row, "QTY数量")
        if found_name or found_qty:
            if not found_name or not found_qty:
                raise RuleError("traveler_schema", f"Pickinglist 第 {row_number} 行名称与数量表头不完整")
            name_col, qty_col = found_name, found_qty
            continue
        if not row or not isinstance(row[0], (int, float)):
            continue
        if not name_col or not qty_col:
            raise RuleError("traveler_schema", f"Pickinglist 第 {row_number} 行数据没有对应表头")
        name = _text(row[name_col - 1] if name_col <= len(row) else None)
        value = row[qty_col - 1] if qty_col <= len(row) else None
        if not name:
            if value not in (None, "", 0, 0.0):
                raise RuleError("traveler_schema", f"Pickinglist 第 {row_number} 行有数量但没有名称")
            continue
        if not current_factory:
            raise RuleError("traveler_identity", f"Pickinglist 第 {row_number} 行五金没有对应工厂单名称")
        if value in (None, "", 0, 0.0):
            fitting_zero.append(TravelerItem(row_number, section, name, 0.0, current_factory))
            continue
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise RuleError("traveler_quantity", f"{name} 的数量不是有效数字：{value}", row=row_number)
        if float(value) < 0:
            raise RuleError("traveler_quantity", f"{name} 的数量不能为负数：{value}", row=row_number)
        key = (current_factory, _normalize_name(name))
        if key in fitting_totals:
            fitting_totals[key].quantity += float(value)
        else:
            fitting_totals[key] = TravelerItem(row_number, section, name, float(value), current_factory)
    material_items, material_zero = _usage_list_items(usage, order_id)
    documents[order_id] = material_items
    for item in fitting_totals.values():
        documents.setdefault(item.document_remark, []).append(item)
    items = material_items + list(fitting_totals.values())
    zero_items = material_zero + fitting_zero
    pp_folder = folder_order or path.parent.name
    snapshot = {
        "order_id": order_id,
        "documents": {
            remark: [asdict(item) for item in values]
            for remark, values in sorted(documents.items())
        },
        "zero_items": [asdict(item) for item in zero_items],
    }
    return TravelerData(
        path=path.resolve(),
        pp_folder=pp_folder,
        order_id=order_id,
        order_name=order_id,
        items=items,
        zero_items=zero_items,
        documents=documents,
        modified_at=datetime.fromtimestamp(path.stat().st_mtime).isoformat(timespec="seconds"),
        fingerprint=_fingerprint(snapshot),
    )


class ProductCatalog:
    def __init__(self, path: Path):
        self.path = path
        self.products: list[Product] = []
        self.by_code: dict[str, list[Product]] = {}
        self._load()

    def _load(self) -> None:
        if not self.path.is_file():
            raise RuleError("product_catalog_missing", f"尚未导入库存商品资料：{self.path}")
        try:
            wb = load_workbook(self.path, data_only=True, read_only=True)
        except Exception as exc:
            raise RuleError("product_catalog_open", f"无法打开库存商品资料：{self.path.name}") from exc
        ws = wb[wb.sheetnames[0]]
        header_row = None
        header_map = {}
        for row_number, row in enumerate(ws.iter_rows(values_only=True), 1):
            values = {_text(value): index for index, value in enumerate(row)}
            if REQUIRED_PRODUCT_HEADERS.issubset(values):
                header_row = row_number
                header_map = values
                break
        if not header_row:
            raise RuleError("product_catalog_schema", f"商品资料缺少必要表头：{sorted(REQUIRED_PRODUCT_HEADERS)}")
        optional = {"备注": None, "计量单位": None}
        for label in optional:
            optional[label] = header_map.get(label)
        for row in ws.iter_rows(min_row=header_row + 1, values_only=True):
            code = _text(row[header_map["*商品编号"]] if header_map["*商品编号"] < len(row) else None)
            name = _text(row[header_map["商品名称"]] if header_map["商品名称"] < len(row) else None)
            if not code and not name:
                continue
            product = Product(
                category=_text(row[header_map["商品类别"]] if header_map["商品类别"] < len(row) else None),
                code=code,
                name=name,
                spec=_text(row[header_map["规格型号"]] if header_map["规格型号"] < len(row) else None),
                status=_text(row[header_map["状态"]] if header_map["状态"] < len(row) else None),
                remark=_text(row[optional["备注"]] if optional["备注"] is not None and optional["备注"] < len(row) else None),
                unit=_text(row[optional["计量单位"]] if optional["计量单位"] is not None and optional["计量单位"] < len(row) else None),
            )
            self.products.append(product)
            self.by_code.setdefault(code.upper(), []).append(product)

    def require_code(self, code: str) -> Product:
        matches = self.by_code.get(code.upper(), [])
        if len(matches) != 1:
            raise RuleError("product_conflict", f"商品编号 {code} 匹配到 {len(matches)} 条记录", product_code=code)
        product = matches[0]
        if not product.code or not product.name:
            raise RuleError("product_invalid", f"当前需要的商品 {code} 缺少编号或名称")
        if product.status and product.status != "启用":
            raise RuleError("product_disabled", f"商品已停用：{code} {product.name}")
        return product

    def find(self, *, category: str | None = None, name: str | None = None, contains: str | None = None,
             spec_thickness: float | None = None) -> list[Product]:
        results = self.products
        if category:
            results = [item for item in results if _normalize_name(item.category) == _normalize_name(category)]
        if name:
            results = [item for item in results if _normalize_name(item.name) == _normalize_name(name)]
        if contains:
            token = _normalize_name(contains)
            results = [item for item in results if token in _normalize_name(item.name) or token in _normalize_name(item.remark)]
        if spec_thickness is not None:
            aliases = {14.5: 15.0, 5.4: 5.2, 8.0: 9.0}
            requested = float(spec_thickness)
            expected_values = (8.0, 9.0) if requested in {8.0, 9.0} else (
                aliases.get(requested, requested),
            )
            results = [
                item for item in results
                if (numbers := re.findall(r"\d+(?:\.\d+)?", item.spec))
                and any(abs(float(numbers[0]) - expected) < 0.6 for expected in expected_values)
            ]
        return results


class InventoryMappings:
    def __init__(self, path: Path):
        self.path = path
        self.manual: dict[str, str] = {}
        self.ignored: dict[str, str] = {}
        if path.is_file():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                self.manual = {_normalize_name(k): str(v) for k, v in data.get("manual", {}).items()}
                self.ignored = {_normalize_name(k): str(v) for k, v in data.get("ignored", {}).items()}
            except (OSError, json.JSONDecodeError) as exc:
                raise RuleError("inventory_mapping", f"库存商品映射无法读取：{path}") from exc

    def ignored_reason(self, name: str) -> str | None:
        return self.ignored.get(_normalize_name(name))

    def manual_code(self, name: str) -> str | None:
        return self.manual.get(_normalize_name(name))

    def save_ignored(self, name: str, reason: str) -> None:
        normalized = _normalize_name(name)
        if not normalized:
            raise RuleError("inventory_mapping", "忽略材料名称不能为空")
        self.ignored[normalized] = reason.strip() or "用户在出库预览中选择忽略"
        self._save()

    def save_manual(self, name: str, product_code: str) -> None:
        normalized = _normalize_name(name)
        if not normalized:
            raise RuleError("inventory_mapping", "映射材料名称不能为空")
        self.manual[normalized] = product_code.strip().upper()
        self.ignored.pop(normalized, None)
        self._save()

    def remove_ignored(self, name: str) -> None:
        self.ignored.pop(_normalize_name(name), None)
        self._save()

    def _save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"version": 1, "manual": self.manual, "ignored": self.ignored}
        temporary = self.path.with_suffix(self.path.suffix + ".tmp")
        temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        temporary.replace(self.path)


FIXED_CODES = {
    "18MMPLYWOOD": "M0004",
    "14.5MMPLYWOOD": "M0003",
    "5.4MMPLYWOOD": "M0002",
    "HINGE": "M1001",
    "ADJUSTABLESHELFHOLDER": "M1013",
    "SHELHOLDER": "M1013",
    "HRAIL": "M1002",
    "LRAIL": "M1003",
    "M.C(L)": "M1089",
}


def _single(catalog: ProductCatalog, matches: list[Product], traveler_name: str, source: str) -> tuple[Product, str]:
    if len(matches) != 1:
        raise RuleError(
            "product_match",
            f"{traveler_name} 匹配到 {len(matches)} 个库存商品，需要人工指定",
            traveler_name=traveler_name,
            candidates=[asdict(item) for item in matches],
        )
    return catalog.require_code(matches[0].code), source


def match_item(catalog: ProductCatalog, mappings: InventoryMappings, item: TravelerItem) -> list[OutboundItem]:
    def outbound(product: Product, quantity: float, source: str) -> OutboundItem:
        return OutboundItem(
            item.name, product.code, product.name, quantity, item.section, source,
            item.document_remark,
        )

    ignored = mappings.ignored_reason(item.name)
    if ignored is not None:
        return []
    manual = mappings.manual_code(item.name)
    if manual:
        product = catalog.require_code(manual)
        return [outbound(product, item.quantity, "人工指定")]
    normalized = _normalize_name(item.name)
    if normalized == "PUSHOPEN":
        results = []
        for code in ("M1068", "M1069"):
            product = catalog.require_code(code)
            results.append(outbound(product, item.quantity, "Push Open 1:1拆分"))
        return results
    fixed = FIXED_CODES.get(normalized)
    if fixed:
        product = catalog.require_code(fixed)
        return [outbound(product, item.quantity, "已确认规则")]
    if match := TB_RE.fullmatch(item.name.strip()):
        token = f"TB{match.group(1)}用"
        product, source = _single(catalog, catalog.find(category="Hardware/Trash Can", contains=token), item.name, "TB型号规则")
        return [outbound(product, item.quantity, source)]
    if match := EDGE_RE.fullmatch(item.name.strip()):
        color = match.group(1).strip()
        matches = catalog.find(category="Edge band", name=f"{color} Edge Banding")
        source = "封边颜色精确名称"
        if not matches:
            color_token = _normalize_name(color)
            matches = [
                product for product in catalog.find(category="Edge band")
                if (normalized := _normalize_name(product.name)).startswith(color_token)
                and "ABSBANDING" in normalized
                and normalized.endswith("24MM")
            ]
            source = "封边颜色 + ABS banding + 24mm后缀"
        product, source = _single(catalog, matches, item.name, source)
        rounded = float(Decimal(str(item.quantity)).quantize(Decimal("1"), rounding=ROUND_HALF_UP))
        source = f"{source}（{item.quantity:g}m→{rounded:g}m，四舍五入取整）"
        return [outbound(product, rounded, source)]
    if match := PANEL_RE.fullmatch(item.name.strip()):
        thickness = float(match.group(1))
        color = match.group(2).strip()
        if color.lower() != "plywood":
            product, source = _single(
                catalog,
                catalog.find(category="Panel", name=color, spec_thickness=thickness),
                item.name,
                "Panel颜色和规格",
            )
            return [outbound(product, item.quantity, source)]
    exact_matches = catalog.find(name=item.name)
    if exact_matches:
        product, source = _single(catalog, exact_matches, item.name, "库存商品名称精确匹配")
        return [outbound(product, item.quantity, source)]
    raise RuleError(
        "product_match",
        f"找不到与 {item.name} 名称完全一致的库存商品，需要人工指定",
        traveler_name=item.name,
        candidates=[],
    )


def build_preview(path: Path, catalog_path: Path, mapping_path: Path) -> InventoryPreview:
    traveler = parse_traveler(path)
    catalog = ProductCatalog(catalog_path)
    mappings = InventoryMappings(mapping_path)
    outbound = []
    ignored = []
    missing = []
    for item in traveler.items:
        reason = mappings.ignored_reason(item.name)
        if reason is not None:
            ignored.append({**asdict(item), "reason": reason})
            continue
        try:
            outbound.extend(match_item(catalog, mappings, item))
        except RuleError as exc:
            missing.append({
                **asdict(item),
                "code": exc.code,
                "message": str(exc),
                **exc.context,
            })
    duplicate_keys = [
        key for key, count in Counter(
            (item.document_remark, item.product_code) for item in outbound
        ).items()
        if count > 1 and _normalize_name(key[1]) not in {"M1068", "M1069"}
    ]
    if duplicate_keys:
        conflicts = [
            asdict(item) for item in outbound
            if (item.document_remark, item.product_code) in duplicate_keys
        ]
        missing.append({"code": "duplicate_product_code", "message": "多个 Traveler 项目映射到同一商品编号", "items": conflicts})
    return InventoryPreview(traveler, outbound, ignored, missing)


def set_ignored_mapping(config: Config, name: str, ignored: bool, reason: str = "") -> dict:
    mappings = InventoryMappings(_mapping_path(config))
    if ignored:
        mappings.save_ignored(name, reason)
    else:
        mappings.remove_ignored(name)
    return {"ok": True, "traveler_name": name, "ignored": ignored}


def search_inventory_products(config: Config, query: str) -> dict:
    token = _normalize_name(query)
    if not token:
        raise RuleError("inventory_argument", "请输入商品编号、名称或规格")
    catalog = ProductCatalog(bootstrap_catalog(config))
    matches = [
        product for product in catalog.products
        if token in _normalize_name(" ".join((
            product.code, product.name, product.spec, product.category, product.remark
        )))
        and (not product.status or product.status == "启用")
    ]
    matches.sort(key=lambda product: (
        0 if token in {_normalize_name(product.code), _normalize_name(product.name)} else 1,
        product.code,
    ))
    return {"query": query, "products": [asdict(product) for product in matches[:50]]}


def save_manual_mapping(config: Config, name: str, product_code: str) -> dict:
    catalog = ProductCatalog(bootstrap_catalog(config))
    product = catalog.require_code(product_code)
    mappings = InventoryMappings(_mapping_path(config))
    mappings.save_manual(name, product.code)
    return {
        "ok": True,
        "traveler_name": name,
        "product": asdict(product),
    }


class InventorySyncStore:
    def __init__(self, path: Path, backup_root: Path):
        self.path = path
        self.backup_root = backup_root / "Inventory Sync Records"
        self.data = {"version": 2, "records": {}}
        if path.is_file():
            try:
                self.data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                raise RuleError("inventory_sync", f"库存同步记录无法读取：{path}") from exc

    @staticmethod
    def key(order_id: str, remark: str) -> str:
        return hashlib.sha256(
            f"{_normalize_name(order_id)}\n{_normalize_name(remark)}".encode()
        ).hexdigest()

    @staticmethod
    def raw_document_fingerprint(items: list[TravelerItem]) -> str:
        return _fingerprint({
            "items": sorted(
                (
                    _normalize_name(item.name),
                    float(item.quantity),
                )
                for item in items
            )
        })

    @staticmethod
    def mapped_document_fingerprint(items: list[OutboundItem]) -> str:
        return _fingerprint({
            "items": sorted(
                (item.product_code.upper(), float(item.quantity))
                for item in items
            )
        })

    def record_for_document(self, order_id: str, remark: str) -> dict | None:
        return self.data.get("records", {}).get(self.key(order_id, remark))

    def records_for_order(self, order_id: str) -> list[dict]:
        normalized = _normalize_name(order_id)
        return [
            record for record in self.data.get("records", {}).values()
            if _normalize_name(str(record.get("order_id", ""))) == normalized
        ]

    def status_for(self, traveler: TravelerData) -> tuple[str, str]:
        records = self.records_for_order(traveler.order_id)
        if not records:
            return "未出库", ""
        current_remarks = set(traveler.documents)
        if any(
            record.get("remark") not in current_remarks
            or not traveler.documents.get(str(record.get("remark", "")), [])
            for record in records
        ):
            return "需要人工处理", ""
        document_numbers = []
        missing = False
        changed = False
        for remark, items in traveler.documents.items():
            if not items:
                continue
            record = self.record_for_document(traveler.order_id, remark)
            if not record:
                missing = True
                continue
            document_numbers.append(str(record.get("document_number", "")))
            if record.get("raw_fingerprint") != self.raw_document_fingerprint(items):
                changed = True
        if changed:
            return "需要更新", "、".join(filter(None, document_numbers))
        if missing:
            return "未出库", "、".join(filter(None, document_numbers))
        return "已出库", "、".join(filter(None, document_numbers))

    def prepare_documents(self, preview: InventoryPreview) -> list[dict]:
        previous = {
            str(record.get("remark", "")): record
            for record in self.records_for_order(preview.traveler.order_id)
        }
        current = set(preview.traveler.documents)
        disappeared = sorted(
            remark for remark in previous
            if remark and (remark not in current or not preview.traveler.documents.get(remark))
        )
        if disappeared:
            raise RuleError(
                "inventory_manual_void",
                "以下已出库工厂单在当前 Traveler 中消失或五金为空，请人工删除或作废旧出库单后再处理："
                + "、".join(disappeared),
                remarks=disappeared,
            )
        payloads = []
        for document in preview.document_payloads():
            remark = document["remark"]
            items = [
                OutboundItem(**item) for item in document["items"]
            ]
            if not items:
                continue
            record = self.record_for_document(preview.traveler.order_id, remark)
            mapped_fingerprint = self.mapped_document_fingerprint(items)
            payloads.append({
                "remark": remark,
                "kind": document["kind"],
                "items": [
                    {"productCode": item.product_code, "quantity": item.quantity}
                    for item in items
                ],
                "changed": not record or record.get("mapped_fingerprint") != mapped_fingerprint,
                "knownDocumentNumber": str(record.get("document_number", "")) if record else "",
                "mappedFingerprint": mapped_fingerprint,
                "rawFingerprint": self.raw_document_fingerprint(
                    preview.traveler.documents.get(remark, [])
                ),
            })
        return payloads

    def save_success(self, preview: InventoryPreview, results: list[dict]) -> None:
        self._backup_current()
        prepared = {item["remark"]: item for item in self.prepare_documents(preview)}
        for result in results:
            if not result.get("saved") and not result.get("unchanged"):
                continue
            remark = str(result.get("remark", ""))
            plan = prepared.get(remark)
            if not plan:
                continue
            key = self.key(preview.traveler.order_id, remark)
            self.data.setdefault("records", {})[key] = {
                "traveler_path": str(preview.traveler.path),
                "order_id": preview.traveler.order_id,
                "remark": remark,
                "kind": plan["kind"],
                "raw_fingerprint": plan["rawFingerprint"],
                "mapped_fingerprint": plan["mappedFingerprint"],
                "document_number": str(result.get("documentNumber", "")),
                "document_url": str(result.get("url", "")),
                "status": "已出库",
                "items": plan["items"],
                "synced_at": datetime.now().isoformat(timespec="seconds"),
            }
        self.data["version"] = 2
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self.data, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")

    def _backup_current(self) -> None:
        if not self.path.is_file():
            return
        self.backup_root.mkdir(parents=True, exist_ok=True)
        destination = self.backup_root / f"inventory-sync {datetime.now():%Y-%m-%d %H%M%S.%f}.json"
        shutil.copy2(self.path, destination)
        backups = sorted(self.backup_root.glob("inventory-sync *.json"), key=lambda item: item.stat().st_mtime, reverse=True)
        for old in backups[50:]:
            old.unlink()


def _catalog_path(config: Config) -> Path:
    return config.state_dir / "inventory" / "current-products.xlsx"


def _mapping_path(config: Config) -> Path:
    return config.state_dir / "inventory" / "mappings.json"


def _sync_path(config: Config) -> Path:
    return Path.home() / "Documents" / "工作流程助手" / "data" / "inventory-outbound-records.json"


def bootstrap_catalog(config: Config) -> Path:
    destination = _catalog_path(config)
    if destination.is_file():
        return destination
    resource_dir = Path(__file__).resolve().parent.parent / "resources" / "inventory"
    sources = sorted(resource_dir.glob("*.xlsx"), key=lambda item: item.stat().st_mtime, reverse=True)
    if not sources:
        return destination
    ProductCatalog(sources[0])
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(sources[0], destination)
    return destination


def reconcile_folder_status(config: Config, folder: str) -> dict:
    folder = folder.strip().upper()
    if not re.fullmatch(r"(?:PP\d{4}|CS\d{3})", folder):
        raise RuleError("inventory_argument", f"文件夹编号格式无效：{folder}")
    paths = sorted((config.order_root / folder).glob("Work Order Traveler(*).xlsx"))
    travelers = [parse_traveler(path) for path in paths]
    response = run_jdy(config, "findOutbound", order_name=folder)
    rows = [str(row) for row in response.get("matches", [])]
    store = InventorySyncStore(_sync_path(config), config.backup_root)
    found = []
    not_found = []
    needs_review = []
    for traveler in travelers:
        token = _normalize_name(traveler.order_name)
        candidates = [row for row in rows if token and token in _normalize_name(row)]
        document_numbers = sorted(set(
            number
            for row in candidates
            for number in re.findall(r"QTCK\d+", row, flags=re.IGNORECASE)
        ))
        if len(document_numbers) == 1:
            number = document_numbers[0].upper()
            found.append({"order_name": traveler.order_name, "document_number": number})
        elif not document_numbers:
            not_found.append({
                "order_name": traveler.order_name,
                "reason": "库存系统中没有查询到对应出库记录",
            })
        else:
            needs_review.append({
                "order_name": traveler.order_name,
                "reason": "找到多个出库单号，需要人工选择",
                "candidates": document_numbers,
            })
    return {
        "ok": True,
        "folder": folder,
        "found": found,
        "not_found": not_found,
        "needs_review": needs_review,
    }


def list_travelers(config: Config, include_history: bool = False) -> dict:
    catalog = bootstrap_catalog(config)
    initial = datetime.strptime(config.initial_date, "%Y-%m-%d")
    store = InventorySyncStore(_sync_path(config), config.backup_root)
    entries = []
    errors = []
    for path in sorted(config.order_root.rglob("Work Order Traveler(*).xlsx")):
        if not TRAVELER_RE.fullmatch(path.name):
            continue
        try:
            traveler = parse_traveler(path)
            status, document = store.status_for(traveler)
            modified = datetime.fromisoformat(traveler.modified_at)
            if not include_history and modified < initial and status == "已出库":
                continue
            entries.append({
                "path": str(path),
                "pp_folder": traveler.pp_folder,
                "file_name": path.name,
                "order_name": traveler.order_name,
                "modified_at": traveler.modified_at,
                "fingerprint": traveler.fingerprint,
                "status": status,
                "document_number": document,
            })
        except RuleError as exc:
            errors.append({"path": str(path), "code": exc.code, "message": str(exc), **exc.context})
    catalog_info = {}
    if catalog.is_file():
        loaded = ProductCatalog(catalog)
        modified = datetime.fromtimestamp(catalog.stat().st_mtime)
        catalog_info = {
            "path": str(catalog),
            "count": len(loaded.products),
            "modified_at": modified.isoformat(timespec="seconds"),
            "stale": datetime.now() - modified > timedelta(days=30),
        }
    return {"travelers": entries, "errors": errors, "catalog": catalog_info}


def list_traveler_names(config: Config) -> dict:
    store = InventorySyncStore(_sync_path(config), config.backup_root)
    records_by_path = {
        str(Path(record.get("traveler_path", "")).resolve()): record
        for record in store.data.get("records", {}).values()
        if record.get("traveler_path")
    }
    entries = []
    for path in sorted(config.order_root.rglob("Work Order Traveler(*).xlsx")):
        if not TRAVELER_RE.fullmatch(path.name):
            continue
        resolved = str(path.resolve())
        record = records_by_path.get(resolved, {})
        entries.append({
            "path": resolved,
            "pp_folder": path.parent.name,
            "file_name": path.name,
            "order_name": "",
            "modified_at": datetime.fromtimestamp(path.stat().st_mtime).isoformat(timespec="seconds"),
            "fingerprint": "",
            "status": record.get("status", "未出库"),
            "document_number": record.get("document_number", ""),
        })
    return {
        "travelers": entries,
        "errors": [],
        "catalog": {},
        "lazy": True,
    }


def import_catalog(config: Config, source: Path) -> dict:
    catalog = ProductCatalog(source)
    destination = _catalog_path(config)
    destination.parent.mkdir(parents=True, exist_ok=True)
    draft = destination.with_suffix(".tmp.xlsx")
    shutil.copy2(source, draft)
    ProductCatalog(draft)
    os.replace(draft, destination)
    return {"path": str(destination), "source": str(source), "count": len(catalog.products)}


def update_catalog_online(config: Config) -> dict:
    """Export the current product catalog from JDY and install it atomically."""
    inventory_dir = _catalog_path(config).parent
    inventory_dir.mkdir(parents=True, exist_ok=True)
    download = inventory_dir / f".products-download-{os.getpid()}.xlsx"
    try:
        progress("正在从库存系统导出商品资料")
        run_jdy(config, "exportProducts", download_path=download)
        if not download.is_file():
            raise RuleError("product_catalog_download", "库存系统导出完成，但没有找到下载的商品资料文件")
        result = import_catalog(config, download)
        progress(f"商品资料已更新，共 {result['count']} 个商品")
        return {"ok": True, **result}
    finally:
        download.unlink(missing_ok=True)


def _local_setting(config: Config, name: str) -> str:
    settings = config.state_dir / "settings.json"
    if not settings.is_file():
        return ""
    try:
        return str(json.loads(settings.read_text(encoding="utf-8")).get(name, "")).strip()
    except (OSError, json.JSONDecodeError):
        return ""


def _keychain_password(account: str) -> str:
    if not account:
        raise RuleError("jdy_credentials", "请先在配置中心填写库存系统用户名")
    result = subprocess.run(
        ["/usr/bin/security", "find-generic-password", "-w", "-a", account,
         "-s", "com.pacificpride.workflow-assistant.jdy"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise RuleError("jdy_credentials", "库存系统密码尚未保存到 macOS 钥匙串")
    return result.stdout.strip()


def _jdy_error_detail(stderr: str) -> str:
    lines = [line.strip() for line in stderr.splitlines() if line.strip()]
    for index, text in enumerate(lines):
        prefix = "库存系统自动操作失败："
        if text.startswith(prefix):
            detail = text[len(prefix):].strip()
            if index + 1 < len(lines) and lines[index + 1].startswith("；当前页面"):
                detail += lines[index + 1]
            return detail
    for text in reversed(lines):
        try:
            event = json.loads(text)
            if isinstance(event, dict) and event.get("event") == "progress":
                continue
        except json.JSONDecodeError:
            pass
        return text
    return "库存系统浏览器操作失败，未返回具体原因"


def run_jdy(config: Config, action: str, traveler_path: Path | None = None, confirm_save: bool = False,
            download_path: Path | None = None, order_name: str = "") -> dict:
    username = _local_setting(config, "jdy_username")
    password = _keychain_password(username)
    root = Path(__file__).resolve().parent.parent
    node = root / "bin" / "node"
    if not node.is_file():
        node = Path("/Users/lantian/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node")
    helper = root / "tools" / "jdy_inventory.mjs"
    request = {
        "action": action,
        "username": username,
        "password": password,
        "profileDir": str(config.state_dir / "inventory" / "browser-profile-zh"),
    }
    if order_name:
        request["orderName"] = order_name
        today = datetime.now().date()
        request["queryDateFrom"] = (today - timedelta(days=550)).isoformat()
        request["queryDateTo"] = (today + timedelta(days=45)).isoformat()
    preview = None
    if action == "outbound":
        if not traveler_path:
            raise RuleError("inventory_argument", "出库必须提供 Traveler")
        preview = build_preview(traveler_path, bootstrap_catalog(config), _mapping_path(config))
        if not preview.ready:
            raise RuleError("inventory_precheck", "Traveler 存在未映射材料，禁止打开库存系统",
                            missing_items=preview.missing_items)
        store = InventorySyncStore(_sync_path(config), config.backup_root)
        documents = store.prepare_documents(preview)
        if not documents:
            raise RuleError("inventory_empty", "Traveler 没有需要出库的板材、封边或五金")
        request.update({
            "orderName": preview.traveler.order_id,
            "documents": documents,
            "confirmSave": confirm_save,
            "queryDateFrom": (datetime.now().date() - timedelta(days=550)).isoformat(),
            "queryDateTo": (datetime.now().date() + timedelta(days=45)).isoformat(),
        })
    elif action == "exportProducts":
        if not download_path:
            raise RuleError("inventory_argument", "更新商品资料缺少下载目标")
        request["downloadPath"] = str(download_path)
    env = os.environ.copy()
    env["NODE_PATH"] = str(root / "node_modules") if (root / "node_modules").is_dir() else (
        "/Users/lantian/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules"
    )
    requests = [request]
    if action == "outbound":
        requests = [
            {
                **request,
                "orderName": document["remark"],
                "remark": document["remark"],
                "kind": document["kind"],
                "items": document["items"],
                "changed": document["changed"],
                "knownDocumentNumber": document["knownDocumentNumber"],
            }
            for document in request["documents"]
        ]
    responses = []
    for browser_request in requests:
        result = subprocess.run(
            [str(node), str(helper)],
            input=json.dumps(browser_request, ensure_ascii=False),
            text=True, capture_output=True, env=env, check=False,
        )
        if result.stderr:
            sys.stderr.write(result.stderr)
        if result.returncode != 0:
            if action == "outbound" and preview is not None and confirm_save and responses:
                completed = [
                    item for item in responses
                    if item.get("saved") or item.get("unchanged")
                ]
                if completed:
                    InventorySyncStore(_sync_path(config), config.backup_root).save_success(
                        preview, completed
                    )
            raise RuleError("jdy_browser", _jdy_error_detail(result.stderr))
        try:
            responses.append(json.loads(result.stdout))
        except json.JSONDecodeError as exc:
            raise RuleError("jdy_browser", "库存系统返回结果无法解析") from exc
    try:
        response = responses[0] if action != "outbound" else {
            "ok": True,
            "saved": confirm_save and all(
                item.get("saved") or item.get("unchanged") for item in responses
            ),
            "results": responses,
            "simulated": not confirm_save,
        }
        if action == "outbound" and response.get("saved"):
            results = response["results"]
            if preview is None or any(
                not str(item.get("documentNumber", "")).strip()
                for item in results
            ):
                raise RuleError("jdy_save_result", "库存单已返回成功，但缺少分单结果或单据编号；结果需要人工核实")
            store = InventorySyncStore(_sync_path(config), config.backup_root)
            store.save_success(preview, results)
            response["syncRecorded"] = True
        return response
    except (TypeError, KeyError) as exc:
        raise RuleError("jdy_browser", "库存系统返回结果结构不完整") from exc


def inventory_main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="traveler-assistant inventory")
    parser.add_argument("action", choices=(
        "list", "list-names", "preview", "import-products", "preflight", "outbound",
        "find-outbound", "reconcile-folder", "ignore-item", "unignore-item",
        "search-products", "set-mapping", "update-products",
    ))
    parser.add_argument("--traveler", type=Path)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--include-history", action="store_true")
    parser.add_argument("--order-root", type=Path)
    parser.add_argument("--state-dir", type=Path)
    parser.add_argument("--confirm-save", action="store_true")
    parser.add_argument("--order-name", default="")
    parser.add_argument("--traveler-name", action="append", default=[])
    parser.add_argument("--reason", default="")
    parser.add_argument("--folder", default="")
    parser.add_argument("--query", default="")
    parser.add_argument("--product-code", default="")
    args = parser.parse_args(argv)
    config = Config()
    config.load_settings()
    if args.order_root:
        config.order_root = args.order_root
    if args.state_dir:
        config.state_dir = args.state_dir
    try:
        if args.action == "list":
            result = list_travelers(config, args.include_history)
        elif args.action == "list-names":
            result = list_traveler_names(config)
        elif args.action == "preview":
            if not args.traveler:
                raise RuleError("inventory_argument", "preview 必须提供 --traveler")
            result = build_preview(args.traveler, bootstrap_catalog(config), _mapping_path(config)).payload()
        elif args.action == "import-products":
            if not args.source:
                raise RuleError("inventory_argument", "import-products 必须提供 --source")
            result = import_catalog(config, args.source)
        elif args.action == "update-products":
            result = update_catalog_online(config)
        elif args.action == "preflight":
            result = run_jdy(config, "preflight")
        elif args.action == "find-outbound":
            if not args.order_name:
                raise RuleError("inventory_argument", "查询出库单必须提供 --order-name")
            result = run_jdy(config, "findOutbound", order_name=args.order_name)
        elif args.action == "reconcile-folder":
            if not args.folder:
                raise RuleError("inventory_argument", "更新文件夹状态必须提供 --folder")
            result = reconcile_folder_status(config, args.folder)
        elif args.action == "search-products":
            result = search_inventory_products(config, args.query)
        elif args.action == "set-mapping":
            if not args.traveler_name or not args.product_code:
                raise RuleError("inventory_argument", "保存映射必须提供材料名称和商品编号")
            result = save_manual_mapping(config, args.traveler_name[0], args.product_code)
        elif args.action in {"ignore-item", "unignore-item"}:
            if not args.traveler_name:
                raise RuleError("inventory_argument", "修改忽略状态必须提供 --traveler-name")
            results = [
                set_ignored_mapping(
                    config, name, args.action == "ignore-item", args.reason
                )
                for name in args.traveler_name
            ]
            result = {"ok": True, "items": results}
        else:
            result = run_jdy(config, "outbound", args.traveler, args.confirm_save)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except RuleError as exc:
        print(json.dumps({"fatal": {"code": exc.code, "message": str(exc), **exc.context}}, ensure_ascii=False, indent=2))
        return 2


if __name__ == "__main__":
    raise SystemExit(inventory_main())
