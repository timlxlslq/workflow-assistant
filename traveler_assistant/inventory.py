from __future__ import annotations

import argparse
import hashlib
import json
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
PP_FOLDER_RE = re.compile(r"^PP\d{4}$", re.IGNORECASE)
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


@dataclass
class TravelerData:
    path: Path
    pp_folder: str
    order_name: str
    items: list[TravelerItem]
    zero_items: list[TravelerItem]
    modified_at: str
    fingerprint: str

    def content_snapshot(self) -> dict:
        return {
            "order_name": self.order_name,
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
        return {
            "traveler": {
                "path": str(self.traveler.path),
                "pp_folder": self.traveler.pp_folder,
                "order_name": self.traveler.order_name,
                "modified_at": self.traveler.modified_at,
                "fingerprint": self.traveler.fingerprint,
            },
            "outbound_items": [asdict(item) for item in self.outbound_items],
            "zero_items": [asdict(item) for item in self.traveler.zero_items],
            "ignored_items": self.ignored_items,
            "missing_items": self.missing_items,
            "warnings": self.warnings,
            "ready": self.ready,
        }


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


def parse_traveler(path: Path) -> TravelerData:
    if not path.is_file() or path.suffix.lower() != ".xlsx":
        raise RuleError("traveler_missing", f"Traveler 文件不存在或格式不是 xlsx：{path}")
    try:
        wb = load_workbook(path, data_only=True, read_only=True)
    except Exception as exc:
        raise RuleError("traveler_open", f"无法打开 Traveler：{path.name}") from exc
    required = {"WorkOrderTraveler", "Pickinglist"}
    if not required.issubset(wb.sheetnames):
        raise RuleError("traveler_schema", f"Traveler 缺少必要工作表：{sorted(required - set(wb.sheetnames))}")
    names = {
        sheet: _order_name_candidates(wb[sheet])
        for sheet in ("WorkOrderTraveler", "Pickinglist")
    }
    for sheet, values in names.items():
        if len(set(values)) > 1:
            raise RuleError("traveler_identity", f"{sheet} 中出现多个不同工厂单名称：{values}")
    main_name = names["WorkOrderTraveler"][0] if names["WorkOrderTraveler"] else ""
    pick_name = names["Pickinglist"][0] if names["Pickinglist"] else ""
    if main_name and pick_name and main_name != pick_name:
        raise RuleError("traveler_identity", f"两个工作表的工厂单名称不一致：{main_name} / {pick_name}")
    order_name = main_name or pick_name
    if not order_name:
        raise RuleError("traveler_identity", "Traveler 两个工作表都没有工厂单名称")
    if order_name.strip() in {"0", "-"}:
        raise RuleError("traveler_identity", f"Traveler 的工厂单名称无效：{order_name}")

    ws = wb["Pickinglist"]
    section = ""
    name_col = qty_col = None
    items: list[TravelerItem] = []
    zero_items: list[TravelerItem] = []
    for row_number, row in enumerate(ws.iter_rows(values_only=True), 1):
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
        if value in (None, "", 0, 0.0):
            zero_items.append(TravelerItem(row_number, section, name, 0.0))
            continue
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise RuleError("traveler_quantity", f"{name} 的数量不是有效数字：{value}", row=row_number)
        if float(value) < 0:
            raise RuleError("traveler_quantity", f"{name} 的数量不能为负数：{value}", row=row_number)
        items.append(TravelerItem(row_number, section, name, float(value)))
    duplicates = [name for name, count in Counter(_normalize_name(item.name) for item in items).items() if count > 1]
    if duplicates:
        detail = [
            asdict(item) for item in items
            if _normalize_name(item.name) in duplicates
        ]
        raise RuleError("traveler_duplicate_item", "Traveler 中存在重复领料名称，需要人工判断", items=detail)
    pp_folder = next((parent.name.upper() for parent in path.parents if PP_FOLDER_RE.fullmatch(parent.name)), path.parent.name)
    snapshot = {
        "order_name": order_name,
        "items": [asdict(item) for item in items],
        "zero_items": [asdict(item) for item in zero_items],
    }
    return TravelerData(
        path=path.resolve(),
        pp_folder=pp_folder,
        order_name=order_name,
        items=items,
        zero_items=zero_items,
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
    ignored = mappings.ignored_reason(item.name)
    if ignored is not None:
        return []
    manual = mappings.manual_code(item.name)
    if manual:
        product = catalog.require_code(manual)
        return [OutboundItem(item.name, product.code, product.name, item.quantity, item.section, "人工指定")]
    normalized = _normalize_name(item.name)
    if normalized == "PUSHOPEN":
        results = []
        for code in ("M1068", "M1069"):
            product = catalog.require_code(code)
            results.append(OutboundItem(item.name, product.code, product.name, item.quantity, item.section, "Push Open 1:1拆分"))
        return results
    fixed = FIXED_CODES.get(normalized)
    if fixed:
        product = catalog.require_code(fixed)
        return [OutboundItem(item.name, product.code, product.name, item.quantity, item.section, "已确认规则")]
    if match := TB_RE.fullmatch(item.name.strip()):
        token = f"TB{match.group(1)}用"
        product, source = _single(catalog, catalog.find(category="Hardware/Trash Can", contains=token), item.name, "TB型号规则")
        return [OutboundItem(item.name, product.code, product.name, item.quantity, item.section, source)]
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
        return [OutboundItem(item.name, product.code, product.name, rounded, item.section, source)]
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
            return [OutboundItem(item.name, product.code, product.name, item.quantity, item.section, source)]
    exact_matches = catalog.find(name=item.name)
    if exact_matches:
        product, source = _single(catalog, exact_matches, item.name, "库存商品名称精确匹配")
        return [OutboundItem(item.name, product.code, product.name, item.quantity, item.section, source)]
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
    duplicates = [
        code for code, count in Counter(item.product_code for item in outbound).items()
        if count > 1 and _normalize_name(code) not in {"M1068", "M1069"}
    ]
    if duplicates:
        conflicts = [asdict(item) for item in outbound if item.product_code in duplicates]
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
        self.data = {"version": 1, "records": {}}
        if path.is_file():
            try:
                self.data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                raise RuleError("inventory_sync", f"库存同步记录无法读取：{path}") from exc

    @staticmethod
    def key(order_name: str, path: str) -> str:
        return hashlib.sha256(f"{_normalize_name(order_name)}\n{Path(path).resolve()}".encode()).hexdigest()

    def record_for(self, traveler: TravelerData) -> dict | None:
        return self.data.get("records", {}).get(self.key(traveler.order_name, str(traveler.path)))

    def status_for(self, traveler: TravelerData) -> tuple[str, str]:
        record = self.record_for(traveler)
        if not record:
            return "未出库", ""
        if record.get("status") in {"结果未知", "失败", "原单据不可编辑"}:
            return record["status"], record.get("document_number", "")
        if record.get("fingerprint") != traveler.fingerprint:
            return "需要更新", record.get("document_number", "")
        return "已出库", record.get("document_number", "")

    def save_success(self, preview: InventoryPreview, document_number: str, document_url: str = "") -> None:
        self._backup_current()
        key = self.key(preview.traveler.order_name, str(preview.traveler.path))
        self.data.setdefault("records", {})[key] = {
            "traveler_path": str(preview.traveler.path),
            "order_name": preview.traveler.order_name,
            "fingerprint": preview.traveler.fingerprint,
            "document_number": document_number,
            "document_url": document_url,
            "status": "已出库",
            "items": [asdict(item) for item in preview.outbound_items],
            "ignored_items": preview.ignored_items,
            "synced_at": datetime.now().isoformat(timespec="seconds"),
        }
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(self.data, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")

    def save_discovered(self, traveler: TravelerData, document_number: str) -> None:
        self._backup_current()
        key = self.key(traveler.order_name, str(traveler.path))
        self.data.setdefault("records", {})[key] = {
            "traveler_path": str(traveler.path),
            "order_name": traveler.order_name,
            "fingerprint": traveler.fingerprint,
            "document_number": document_number,
            "document_url": "",
            "status": "已出库",
            "items": [],
            "ignored_items": [],
            "source": "库存系统记录查询",
            "synced_at": datetime.now().isoformat(timespec="seconds"),
        }
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
    return config.state_dir / "inventory-sync.json"


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
    if not re.fullmatch(r"PP\d{4}", folder):
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
            store.save_discovered(traveler, number)
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
        request.update({
            "orderName": preview.traveler.order_name,
            "items": [
                {"productCode": item.product_code, "quantity": item.quantity}
                for item in preview.outbound_items
            ],
            "confirmSave": confirm_save,
        })
    elif action == "exportProducts":
        if not download_path:
            raise RuleError("inventory_argument", "更新商品资料缺少下载目标")
        request["downloadPath"] = str(download_path)
    env = os.environ.copy()
    env["NODE_PATH"] = str(root / "node_modules") if (root / "node_modules").is_dir() else (
        "/Users/lantian/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules"
    )
    result = subprocess.run(
        [str(node), str(helper)],
        input=json.dumps(request, ensure_ascii=False),
        text=True, capture_output=True, env=env, check=False,
    )
    if result.stderr:
        sys.stderr.write(result.stderr)
    if result.returncode != 0:
        raise RuleError("jdy_browser", _jdy_error_detail(result.stderr))
    try:
        response = json.loads(result.stdout)
        if action == "outbound" and response.get("saved"):
            document_number = str(response.get("documentNumber", "")).strip()
            if not document_number or preview is None:
                raise RuleError("jdy_save_result", "库存单已返回保存成功，但缺少单据编号；结果需要人工核实")
            store = InventorySyncStore(_sync_path(config), config.backup_root)
            store.save_success(preview, document_number, str(response.get("url", "")))
            response["syncRecorded"] = True
        return response
    except json.JSONDecodeError as exc:
        raise RuleError("jdy_browser", "库存系统返回结果无法解析") from exc


def inventory_main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="traveler-assistant inventory")
    parser.add_argument("action", choices=(
        "list", "list-names", "preview", "import-products", "preflight", "outbound",
        "find-outbound", "reconcile-folder", "ignore-item", "unignore-item",
        "search-products", "set-mapping",
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
