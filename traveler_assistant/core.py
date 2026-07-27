from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import time
import math
import urllib.error
import urllib.request
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Iterable

from openpyxl import load_workbook
from openpyxl.cell.cell import MergedCell
from openpyxl.utils import get_column_letter, range_boundaries


BOARD_RE = re.compile(r"^pp-板材清单-newPC\d+\.xlsx$", re.IGNORECASE)
FITTINGS_RE = re.compile(r"^FittingslistPC\d+\.xlsx$", re.IGNORECASE)
PP_RE = re.compile(r"(?i)(PP\d{4})")
FACTORY_RE = re.compile(r"^F\d+$", re.IGNORECASE)
MATERIALS_RE = re.compile(r"^(PP\d{4})\s*materials\.xlsx$", re.IGNORECASE)


class RuleError(RuntimeError):
    def __init__(self, code: str, message: str, **context):
        super().__init__(message)
        self.code = code
        self.context = context


def _load_business_rules() -> dict:
    bundled = Path(__file__).resolve().parent.parent / "config/business-rules.json"
    local = Path.home() / "Library/Application Support/工作流程助手/business-rules.json"
    path = local if local.is_file() else bundled
    try:
        rules = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"业务规则配置无法读取：{path}") from exc
    required = {"schema_version", "sheet_materials", "materials_workbook", "fittings"}
    if rules.get("schema_version") != 1 or not required.issubset(rules):
        raise RuntimeError(f"业务规则配置结构不受支持：{path}")
    return rules


BUSINESS_RULES = _load_business_rules()


def progress(message: str, **details) -> None:
    print(json.dumps({"event": "progress", "message": message, **details}, ensure_ascii=False), file=sys.stderr, flush=True)


@dataclass
class Config:
    source_root: Path = Path("/Volumes/server/Optimized Orders")
    order_root: Path = Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/PacificPride/Order"
    template: Path = Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/PacificPride/模版/Work Order Traveler().xlsx"
    backup_root: Path = Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/PacificPride/Work Order Traveler Backups"
    state_dir: Path = Path.home() / "Library/Application Support/工作流程助手"
    company_wifi: str = "SpectrumSetup-7C81"
    leftover_threshold_mm: float = 100.0
    initial_date: str = "2026-07-22"
    # AIMES credentials are machine-local settings. Never ship a real account
    # name or password in source control or in the application bundle.
    aimes_username: str = ""
    aimes_url: str = "https://aimes.3vjia.com/"
    aimes_keychain_service: str = "com.pacificpride.traveler-assistant.aimes"
    aimes_retry_delays: tuple[float, float] = (30.0, 60.0)
    node_path: Path = Path("/Users/lantian/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node")
    playwright_node_modules: Path = Path("/Users/lantian/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules")

    def __post_init__(self) -> None:
        project_root = Path(__file__).resolve().parent.parent
        bundled_node = project_root / "bin/node"
        bundled_modules = project_root / "node_modules"
        if bundled_node.is_file():
            self.node_path = bundled_node
        if bundled_modules.is_dir():
            self.playwright_node_modules = bundled_modules

    @property
    def database(self) -> Path:
        return self.state_dir / "state.sqlite3"

    @property
    def settings_file(self) -> Path:
        return self.state_dir / "settings.json"

    def load_settings(self) -> None:
        if not self.settings_file.is_file():
            return
        try:
            values = json.loads(self.settings_file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise RuleError("settings_invalid", f"设置文件无法读取：{self.settings_file}") from exc
        path_fields = {"source_root", "order_root", "template", "backup_root"}
        allowed = path_fields | {"company_wifi", "leftover_threshold_mm", "initial_date", "aimes_username"}
        for key, value in values.items():
            if key not in allowed:
                continue
            if key in path_fields:
                setattr(self, key, Path(value).expanduser())
            elif key == "leftover_threshold_mm":
                setattr(self, key, float(value))
            else:
                setattr(self, key, str(value))
        try:
            datetime.strptime(self.initial_date, "%Y-%m-%d")
        except ValueError as exc:
            raise RuleError("settings_invalid", f"初始扫描日期格式错误：{self.initial_date}") from exc


@dataclass
class PanelItem:
    thickness: float
    color: str
    spec: str
    quantity: float
    kind: str

    @property
    def label(self) -> str:
        t = _fmt_number(self.thickness)
        return f"{t}mm--plywood" if self.kind == "plywood" else f"{t}mm--{self.color}".rstrip("-")


@dataclass
class FittingItem:
    name: str
    code: str
    size: str
    unit: str
    quantity: float


@dataclass
class ReportData:
    factory_order: str
    order_name: str
    pp_order: str
    report_dir: Path
    board_path: Path
    fittings_path: Path
    panels: list[PanelItem]
    edge_banding: dict[str, float]
    fittings: dict[str, float]
    ignored_fittings: list[FittingItem]
    warnings: list[str] = field(default_factory=list)
    factory_orders: list[str] = field(default_factory=list)
    traveler_file_name: str = ""
    materials_path: Path | None = None

    def managed_snapshot(self) -> dict:
        return {
            "factory_order": self.factory_order,
            "factory_orders": self.factory_orders or [self.factory_order],
            "order_name": self.order_name,
            "panels": [asdict(x) for x in self.panels],
            "edge_banding": self.edge_banding,
            "fittings": self.fittings,
        }


@dataclass
class Candidate:
    kind: str
    path: Path
    factory_order: str
    order_name: str = ""
    mtime: float = 0


@dataclass
class MaterialsData:
    pp_order: str
    path: Path
    panels: list[PanelItem]
    edge_banding: dict[str, float]


def _ceil_half_sheet(value) -> float:
    number = _number(value)
    return float(math.ceil(number)) if not number.is_integer() else number


class StateStore:
    def __init__(self, path: Path):
        path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(path)
        self.conn.row_factory = sqlite3.Row
        self.conn.executescript(
            """
            create table if not exists meta(key text primary key, value text not null);
            create table if not exists snapshots(order_name text primary key, payload text not null, updated_at text not null);
            create table if not exists notices(signature text primary key, payload text not null, seen_at text not null);
            create table if not exists runs(id integer primary key, started_at text not null, mode text not null, status text not null, payload text not null);
            """
        )
        self.conn.commit()

    def get_meta(self, key: str) -> str | None:
        row = self.conn.execute("select value from meta where key=?", (key,)).fetchone()
        return row[0] if row else None

    def set_meta(self, key: str, value: str) -> None:
        self.conn.execute("insert into meta(key,value) values(?,?) on conflict(key) do update set value=excluded.value", (key, value))
        self.conn.commit()

    def snapshot(self, order_name: str) -> dict | None:
        row = self.conn.execute("select payload from snapshots where order_name=?", (order_name,)).fetchone()
        return json.loads(row[0]) if row else None

    def save_snapshot(self, order_name: str, payload: dict) -> None:
        self.conn.execute(
            "insert into snapshots values(?,?,?) on conflict(order_name) do update set payload=excluded.payload,updated_at=excluded.updated_at",
            (order_name, json.dumps(payload, ensure_ascii=False, sort_keys=True), datetime.now().isoformat()),
        )
        self.conn.commit()

    def notice_changed(self, key: str, payload: dict) -> bool:
        encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True)
        row = self.conn.execute("select payload from notices where signature=?", (key,)).fetchone()
        changed = not row or row[0] != encoded
        if changed:
            self.conn.execute(
                "insert into notices values(?,?,?) on conflict(signature) do update set payload=excluded.payload,seen_at=excluded.seen_at",
                (key, encoded, datetime.now().isoformat()),
            )
            self.conn.commit()
        return changed

    def log_run(self, mode: str, status: str, payload: dict) -> None:
        self.conn.execute(
            "insert into runs(started_at,mode,status,payload) values(?,?,?,?)",
            (datetime.now().isoformat(), mode, status, json.dumps(payload, ensure_ascii=False)),
        )
        self.conn.commit()


def _value(ws, coordinate: str):
    return ws[coordinate].value


def _text(value) -> str:
    return "" if value is None else str(value).strip()


def _number(value) -> float:
    if value in (None, ""):
        return 0.0
    try:
        return float(value)
    except (TypeError, ValueError) as exc:
        raise RuleError("invalid_number", f"无法识别数值：{value}") from exc


def _fmt_number(value: float) -> str:
    return str(int(value)) if float(value).is_integer() else str(value).rstrip("0").rstrip(".")


def _normalize_name(value: str) -> str:
    return re.sub(r"[\s_-]+", "", value).upper()


def _parse_spec(value: str) -> tuple[float, float]:
    nums = re.findall(r"\d+(?:\.\d+)?", value.replace("×", "*").lower())
    if len(nums) < 2:
        raise RuleError("invalid_spec", f"无法识别板材规格：{value}")
    dims = sorted((float(nums[0]), float(nums[1])), reverse=True)
    return dims[0], dims[1]


def _parse_material(value: str) -> tuple[float, str]:
    parts = [p.strip() for p in value.split("/")]
    match = re.search(r"\d+(?:\.\d+)?", parts[0] if parts else value)
    if not match:
        raise RuleError("invalid_thickness", f"无法识别板材厚度：{value}")
    thickness = float(match.group())
    aliases = {float(source): float(target) for source, target in BUSINESS_RULES["sheet_materials"]["thickness_aliases"].items()}
    for source, target in aliases.items():
        if abs(thickness - source) < 0.01:
            thickness = target
            break
    color = parts[1] if len(parts) > 1 else ""
    return thickness, color


def _classify_panel(thickness: float) -> tuple[str, tuple[float, float]]:
    material_rules = BUSINESS_RULES["sheet_materials"]
    for kind in ("plywood", "panel"):
        rule = material_rules[kind]
        if any(abs(thickness - float(value)) < 0.01 for value in rule["thicknesses_mm"]):
            return kind, tuple(float(value) for value in rule["standard_size_mm"])
    raise RuleError("unexpected_thickness", f"发现未确认的板材厚度：{thickness}mm", thickness=thickness)


def _include_full_sheet(spec: str, standard: tuple[float, float], threshold: float) -> bool:
    dims = _parse_spec(spec)
    diffs = (standard[0] - dims[0], standard[1] - dims[1])
    if any(x < 0 for x in diffs):
        raise RuleError("oversize_panel", f"板材尺寸 {spec} 大于标准 {standard[0]}*{standard[1]}")
    if diffs == (0, 0):
        return True
    if all(x >= 0 for x in diffs) and any(0 < x <= threshold for x in diffs):
        raise RuleError("near_standard_panel", f"板材尺寸 {spec} 接近但不等于标准尺寸，需要人工核实")
    return False


def parse_board(path: Path, threshold: float) -> tuple[str, str, list[PanelItem], dict[str, float]]:
    wb = load_workbook(path, data_only=True, read_only=True)
    if wb.sheetnames != ["Page1"]:
        raise RuleError("board_schema", f"板材清单工作表结构变化：{wb.sheetnames}", path=str(path))
    ws = wb["Page1"]
    factory = _text(_value(ws, "B2"))
    order_name = _text(_value(ws, "G2"))
    if not FACTORY_RE.fullmatch(factory) or not PP_RE.search(order_name):
        raise RuleError("board_identity", f"板材清单工厂单号或订单名称异常：{factory} / {order_name}")
    if _text(_value(ws, "A5")) != "大板统计":
        raise RuleError("board_schema", "板材清单缺少“大板统计”标题")

    aggregate: dict[tuple[float, str, str, str], float] = defaultdict(float)
    for row in range(7, ws.max_row + 1):
        if _text(ws.cell(row, 1).value) == "小板统计":
            break
        material, spec, qty = _text(ws.cell(row, 2).value), _text(ws.cell(row, 5).value), ws.cell(row, 6).value
        if not material or not spec or qty in (None, ""):
            continue
        thickness, color = _parse_material(material)
        kind, standard = _classify_panel(thickness)
        if not _include_full_sheet(spec, standard, threshold):
            continue
        normalized_spec = f"{_fmt_number(standard[0])}*{_fmt_number(standard[1])}"
        aggregate[(thickness, color if kind == "panel" else "", normalized_spec, kind)] += _number(qty)

    panels = [PanelItem(k[0], k[1], k[2], v, k[3]) for k, v in aggregate.items()]
    display_order = [float(value) for value in BUSINESS_RULES["sheet_materials"]["display_order_mm"]]
    panels.sort(key=lambda x: (next((index for index, value in enumerate(display_order) if abs(x.thickness - value) < 0.01), 99), x.color))

    edge: dict[str, float] = defaultdict(float)
    header = None
    for row in range(1, ws.max_row + 1):
        if _text(ws.cell(row, 7).value) == "封边条/米":
            header = row
            break
    if header is None:
        raise RuleError("board_schema", "板材清单缺少“封边条/米”字段")
    for row in range(header + 1, ws.max_row + 1):
        color = _text(ws.cell(row, 2).value)
        meters = ws.cell(row, 7).value
        if color and meters not in (None, "") and _number(meters) != 0:
            edge[color] += _number(meters)
    edge_decimals = int(BUSINESS_RULES["sheet_materials"]["edge_decimals"])
    edge = {k: round(v, edge_decimals) for k, v in edge.items() if round(v, edge_decimals) != 0}
    has_panel = any(x.kind == "panel" and x.quantity > 0 for x in panels)
    if has_panel and not edge:
        raise RuleError("missing_edge", "大板统计中存在 Panel，但封边统计为 0")
    if not has_panel and edge:
        raise RuleError("unexpected_edge", "大板统计中没有 Panel，但出现了封边数量")
    return factory.upper(), order_name, panels, edge


def parse_fittings_groups(path: Path) -> list[tuple[str, list[FittingItem]]]:
    wb = load_workbook(path, data_only=True, read_only=True)
    if wb.sheetnames != ["Page1"]:
        raise RuleError("fittings_schema", f"五金清单工作表结构变化：{wb.sheetnames}", path=str(path))
    ws = wb["Page1"]
    starts = [row for row in range(1, ws.max_row + 1) if _text(ws.cell(row, 1).value) == "Order No."]
    if not starts:
        raise RuleError("fittings_schema", "五金清单缺少 Order No. 区块")
    groups = []
    for index, start in enumerate(starts):
        factory = _text(ws.cell(start, 3).value).upper()
        if not FACTORY_RE.fullmatch(factory):
            raise RuleError("fittings_identity", f"五金清单工厂单号异常：{factory}")
        header = start + 5
        expected = {3: "Name", 5: "Code", 6: "Size", 11: "Quantity"}
        if any(_text(ws.cell(header, col).value) != label for col, label in expected.items()):
            raise RuleError("fittings_schema", f"五金清单第 {start} 行开始的区块字段发生变化")
        items = []
        end = starts[index + 1] if index + 1 < len(starts) else ws.max_row + 1
        for row in range(header + 1, end):
            name = _text(ws.cell(row, 3).value)
            if not name or name == "Total":
                continue
            items.append(FittingItem(name, _text(ws.cell(row, 5).value), _text(ws.cell(row, 6).value), _text(ws.cell(row, 9).value), _number(ws.cell(row, 11).value)))
        groups.append((factory, items))
    return groups


def parse_fittings(path: Path) -> tuple[str, list[FittingItem]]:
    groups = parse_fittings_groups(path)
    if len(groups) != 1:
        raise RuleError("multiple_factory_orders", f"五金清单包含 {len(groups)} 个工厂单号", factory_orders=[x[0] for x in groups])
    return groups[0]


def parse_materials(path: Path) -> MaterialsData:
    wb = load_workbook(path, data_only=True, read_only=True)
    if len(wb.sheetnames) != 1:
        raise RuleError("materials_schema", f"materials 工作表结构变化：{wb.sheetnames}")
    ws = wb[wb.sheetnames[0]]
    pp = _text(ws["B1"].value).upper()
    if not re.fullmatch(r"PP\d{4}", pp):
        raise RuleError("materials_identity", f"materials 文件 PP 号码异常：{pp}")
    expected = {
        "C2": "3/4 Plywood", "D2": "5/8 Plywood", "E2": "1/4 Plywood",
        "F2": "3/4 Finish Panel", "G2": "1/4 Finish Panel", "H2": "Edge Banding (m)", "I2": "Color",
    }
    for cell, label in expected.items():
        if " ".join(_text(ws[cell].value).split()).lower() != label.lower():
            raise RuleError("materials_schema", f"materials 字段 {cell} 已变化，预期 {label}")
    total_row = next((r for r in range(3, ws.max_row + 1) if _text(ws.cell(r, 1).value) == "Total Qty:"), None)
    color_row = next((r for r in range(3, ws.max_row + 1) if _text(ws.cell(r, 1).value) == "Color Table"), None)
    if not total_row or not color_row:
        raise RuleError("materials_schema", "materials 文件缺少 Total Qty 或 Color Table")
    material_rules = BUSINESS_RULES["sheet_materials"]
    plywood_size = "*".join(_fmt_number(float(value)) for value in material_rules["plywood"]["standard_size_mm"])
    plywood = [
        PanelItem(float(thickness), "", plywood_size, _ceil_half_sheet(ws.cell(total_row, int(column)).value), "plywood")
        for column, thickness in BUSINESS_RULES["materials_workbook"]["plywood_columns"].items()
    ]
    header = color_row + 1
    row_34, row_14, row_edge = color_row + 2, color_row + 3, color_row + 4
    if _text(ws.cell(row_34, 1).value) != "Sheets (3/4):" or _text(ws.cell(row_14, 1).value) != "Sheets (1/4):":
        raise RuleError("materials_schema", "materials Color Table 行标题发生变化")
    panels = plywood[:]
    edge = {}
    for col in range(3, ws.max_column + 1):
        color = _text(ws.cell(header, col).value)
        if not color:
            continue
        qty_34 = _number(ws.cell(row_34, col).value)
        qty_14 = _number(ws.cell(row_14, col).value)
        meters = _number(ws.cell(row_edge, col).value)
        panel_size = "*".join(_fmt_number(float(value)) for value in material_rules["panel"]["standard_size_mm"])
        panel_rows = BUSINESS_RULES["materials_workbook"]["panel_rows"]
        if qty_34:
            panels.append(PanelItem(float(panel_rows["3/4"]), color, panel_size, _ceil_half_sheet(qty_34), "panel"))
        if qty_14:
            panels.append(PanelItem(float(panel_rows["1/4"]), color, panel_size, _ceil_half_sheet(qty_14), "panel"))
        if meters:
            edge[color] = round(meters, int(material_rules["edge_decimals"]))
    return MaterialsData(pp, path, panels, edge)


def lookup_aimes_names(config: Config, factory_orders: list[str]) -> dict[str, str]:
    if not config.aimes_username.strip():
        raise RuleError("aimes_credentials", "尚未设置 AIMES 用户名，请先在设置中填写并保存")
    helper = Path(__file__).resolve().parent.parent / "tools/aimes_lookup.mjs"
    try:
        password = subprocess.check_output([
            "/usr/bin/security", "find-generic-password", "-w", "-a", config.aimes_username,
            "-s", config.aimes_keychain_service,
        ], text=True, stderr=subprocess.DEVNULL).strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise RuleError("aimes_credentials", "无法从 macOS 钥匙串读取 AIMES 密码") from exc
    payload = json.dumps({"username": config.aimes_username, "password": password, "factoryOrders": factory_orders})
    env = os.environ.copy()
    env["NODE_PATH"] = str(config.playwright_node_modules)
    last_error = ""
    for attempt in range(3):
        progress(f"正在登录 AIMES 查询工厂单名称（第 {attempt + 1}/3 次）", factory_orders=factory_orders)
        try:
            completed = subprocess.run(
                [str(config.node_path), str(helper)], input=payload, text=True, capture_output=True,
                timeout=120, env=env, check=True,
            )
            result = json.loads(completed.stdout)
            if all(result.get(factory) for factory in factory_orders):
                progress("AIMES 工厂单名称查询完成", names={factory: result[factory] for factory in factory_orders})
                return {factory: _text(result[factory]) for factory in factory_orders}
            last_error = "查询结果缺少工厂单名称"
        except subprocess.CalledProcessError as exc:
            lines = [line.strip() for line in (exc.stderr or "").splitlines() if line.strip()]
            useful = [
                line for line in lines
                if "Node.js v" not in line and not line.startswith("at ") and set(line) != {"="}
            ]
            detail = _text(next(
                (line for line in useful if "AIMES 自动查询失败" in line),
                " | ".join(useful[-8:]),
            ))
            last_error = detail or "AIMES 自动登录浏览器异常退出"
            if "账号或密码错误" in last_error:
                raise RuleError("aimes_credentials", "AIMES 拒绝登录：账号或密码错误，请在设置中更新 AIMES 密码")
        except subprocess.TimeoutExpired:
            last_error = "AIMES 自动登录或查询等待超时"
        except (subprocess.SubprocessError, OSError, json.JSONDecodeError) as exc:
            last_error = str(exc)
        if attempt < 2:
            progress(f"AIMES 查询失败，等待 {int(config.aimes_retry_delays[attempt])} 秒后重试")
            time.sleep(config.aimes_retry_delays[attempt])
    raise RuleError("aimes_unavailable", f"AIMES 连续查询三次失败，任务已停止：{last_error}", factory_orders=factory_orders)


def preflight(config: Config) -> None:
    progress("正在检查服务器目录是否可读", path=str(config.source_root))
    if not config.source_root.is_dir():
        raise RuleError("server_unavailable", f"服务器目录不可访问：{config.source_root}")
    try:
        next(config.source_root.iterdir(), None)
    except OSError as exc:
        raise RuleError("server_unavailable", f"服务器目录无法读取：{config.source_root}") from exc
    progress("服务器目录可读取")
    progress("正在检查 AIMES 网站是否可访问", url=config.aimes_url)
    try:
        request = urllib.request.Request(config.aimes_url, headers={"User-Agent": "Workflow Assistant/1.0"})
        with urllib.request.urlopen(request, timeout=15) as response:
            if response.status < 200 or response.status >= 400:
                raise RuleError("aimes_preflight", f"AIMES 网站返回异常状态：HTTP {response.status}")
    except RuleError:
        raise
    except (urllib.error.URLError, OSError) as exc:
        raise RuleError("aimes_preflight", "AIMES 网站当前无法打开，本次任务未开始") from exc
    progress("AIMES 网站可以访问")


def map_fittings(items: list[FittingItem]) -> tuple[dict[str, float], list[FittingItem]]:
    fitting_rules = BUSINESS_RULES["fittings"]
    direct_codes = {code.upper(): name for code, name in fitting_rules["direct_codes"].items()}
    paired_codes = {code.upper(): name for code, name in fitting_rules["paired_codes"].items()}
    result: dict[str, float] = {name: 0 for name in [*direct_codes.values(), *paired_codes.values()]}
    ignored: list[FittingItem] = []
    rail: dict[str, dict[str, float]] = {name: defaultdict(float) for name in paired_codes.values()}
    for item in items:
        code = item.code.strip().upper()
        if code in direct_codes:
            result[direct_codes[code]] += item.quantity
        elif code in paired_codes:
            key = paired_codes[code]
            side = "right" if "right" in item.name.lower() else "left" if "left" in item.name.lower() else "unknown"
            rail[key][side] += item.quantity
        else:
            ignored.append(item)
    for key, sides in rail.items():
        if not sides:
            continue
        if set(sides) != {"left", "right"} or abs(sides["left"] - sides["right"]) > 0.001:
            raise RuleError("rail_mismatch", f"{key} 左右数量不一致：{dict(sides)}")
        result[key] = sides["left"]
    return {k: v for k, v in result.items()}, ignored


def discover(config: Config, started_at: float, include_history: bool = False, query: str | None = None) -> list[Candidate]:
    if not config.source_root.is_dir():
        raise RuleError("server_unavailable", f"服务器目录不可访问：{config.source_root}")
    candidates: list[Candidate] = []
    roots = [config.source_root]
    if query and (pp_query := PP_RE.search(query)):
        code = pp_query.group(1).upper()
        if code not in str(config.source_root).upper():
            roots = [p for p in config.source_root.iterdir() if p.is_dir() and p.name.upper().startswith(code)]
    report_dirs: list[Path] = []
    for root in roots:
        for current, dirs, _ in os.walk(root):
            current_path = Path(current)
            depth = len(current_path.relative_to(root).parts)
            if current_path.name.lower() == "report":
                report_dirs.append(current_path)
                dirs[:] = []
                continue
            if depth >= 2:
                dirs[:] = [d for d in dirs if d.lower() == "report"]
    for report_dir in report_dirs:
        if not PP_RE.search(str(report_dir.parent)):
            continue
        for path in report_dir.iterdir():
            if not path.is_file() or path.name.startswith("~$"):
                continue
            kind = "board" if "板材清单" in path.name and path.suffix.lower() == ".xlsx" else "fittings" if "fittingslist" in path.name.lower() and path.suffix.lower() == ".xlsx" else ""
            if not kind:
                continue
            if query:
                pp_query = PP_RE.search(query)
                if pp_query and pp_query.group(1).upper() not in str(path).upper():
                    continue
            pattern_ok = BOARD_RE.fullmatch(path.name) if kind == "board" else FITTINGS_RE.fullmatch(path.name)
            if not pattern_ok and path.stat().st_mtime >= started_at:
                raise RuleError("filename_changed", f"目标报表命名格式发生变化：{path}")
            if not pattern_ok:
                continue
            candidates.append(Candidate(kind, path, "", mtime=path.stat().st_mtime))
    return candidates


def _pp_root(path: Path, pp: str) -> Path | None:
    for parent in (path, *path.parents):
        if parent.name.upper() == pp:
            return parent
    return None


def _material_totals(panels: list[PanelItem], edge: dict[str, float]) -> dict:
    panel_totals = defaultdict(float)
    for item in panels:
        color = _normalize_name(item.color) if item.kind == "panel" else ""
        panel_totals[(item.kind, item.thickness, color)] += item.quantity
    return {
        "panels": {f"{kind}:{_fmt_number(thickness)}:{color}": round(qty, 2) for (kind, thickness, color), qty in sorted(panel_totals.items())},
        "edge": {_normalize_name(color): round(qty, 2) for color, qty in sorted(edge.items())},
    }


def build_reports(config: Config, paths: Iterable[Candidate]) -> tuple[list[ReportData], list[dict]]:
    errors: list[dict] = []
    by_folder: dict[Path, dict[str, list[Candidate]]] = defaultdict(lambda: defaultdict(list))
    for candidate in paths:
        by_folder[candidate.path.parent][candidate.kind].append(candidate)

    reports: list[ReportData] = []
    for folder, kinds in by_folder.items():
        if not kinds.get("board") or not kinds.get("fittings"):
            errors.append({"code": "unpaired", "message": "同一 Report 目录中缺少板材清单或五金清单", "path": str(folder)})
            continue
        board = max(kinds["board"], key=lambda item: item.mtime)
        fitting = max(kinds["fittings"], key=lambda item: item.mtime)
        try:
            board_factory, board_name, panels, edge = parse_board(board.path, config.leftover_threshold_mm)
            fitting_groups = parse_fittings_groups(fitting.path)
            factory_orders = [factory for factory, _ in fitting_groups]
            if board_factory not in factory_orders:
                raise RuleError("factory_mismatch", f"板材工厂单 {board_factory} 不在五金清单中", factory_orders=factory_orders)
            pp_match = PP_RE.search(board_name)
            if not pp_match:
                raise RuleError("invalid_order_name", f"订单名称无法识别 PP####：{board_name}")
            pp = pp_match.group(1).upper()
            all_items = [item for _, group_items in fitting_groups for item in group_items]
            mapped, ignored = map_fittings(all_items)
            multi = len(factory_orders) > 1
            if multi:
                names = lookup_aimes_names(config, factory_orders)
                order_name = "/".join(names[factory] for factory in factory_orders)
                traveler_file_name = folder.parent.name
            else:
                order_name = board_name
                traveler_file_name = order_name
            warnings = []
            if multi:
                warnings.append(f"五金清单包含 {len(factory_orders)} 个工厂单，已合并数量并按 AIMES 名称生成一个 Traveler")
            reports.append(ReportData(
                board_factory, order_name, pp, folder, board.path, fitting.path, panels, edge,
                mapped, ignored, warnings, factory_orders, traveler_file_name,
            ))
        except RuleError as exc:
            errors.append({"code": exc.code, "message": str(exc), "path": str(folder), **exc.context})

    deduplicated: list[ReportData] = []
    by_factory: dict[tuple[str, ...], list[ReportData]] = defaultdict(list)
    for report in reports:
        by_factory[tuple(report.factory_orders or [report.factory_order])].append(report)
    for factories, matches in by_factory.items():
        if len(matches) == 1:
            deduplicated.append(matches[0])
            continue
        newest_board = max(matches, key=lambda report: report.board_path.stat().st_mtime)
        newest_fittings = max(matches, key=lambda report: report.fittings_path.stat().st_mtime)
        if newest_board.report_dir != newest_fittings.report_dir:
            errors.append({
                "code": "cross_folder_latest",
                "message": f"工厂单 {'/'.join(factories)} 的最新板材与五金报表不在同一目录",
                "board": str(newest_board.board_path), "fittings": str(newest_fittings.fittings_path),
            })
            continue
        newest_board.warnings.append(f"发现 {len(matches)} 组重复工厂单，已采用板材清单修改时间最新的同目录报表组")
        deduplicated.append(newest_board)
    reports = deduplicated

    reports_by_pp: dict[str, list[ReportData]] = defaultdict(list)
    for report in reports:
        reports_by_pp[report.pp_order].append(report)
    for pp, pp_reports in reports_by_pp.items():
        root = _pp_root(pp_reports[0].report_dir, pp)
        if not root:
            continue
        materials_files = [p for p in root.iterdir() if p.is_file() and not p.name.startswith("~$") and MATERIALS_RE.fullmatch(p.name)]
        if not materials_files:
            continue
        try:
            materials = parse_materials(max(materials_files, key=lambda p: p.stat().st_mtime))
            board_panels = [item for report in pp_reports for item in report.panels]
            board_edge = defaultdict(float)
            for report in pp_reports:
                for color, qty in report.edge_banding.items():
                    board_edge[color] += qty
            expected = _material_totals(materials.panels, materials.edge_banding)
            actual = _material_totals(board_panels, dict(board_edge))
            if expected != actual:
                comparison = json.dumps({"materials": expected, "原报表": actual}, ensure_ascii=False, sort_keys=True)
                for report in pp_reports:
                    report.materials_path = materials.path
                    report.warnings.append(
                        f"{pp} materials 与原报表汇总不一致；本次已按原报表完成，请检查 materials。差异：{comparison}"
                    )
                continue
            for report in pp_reports:
                report.materials_path = materials.path
                if len(report.factory_orders) > 1:
                    report.panels = materials.panels
                    report.edge_banding = materials.edge_banding
                    report.warnings.append("已用 PP materials 上方总数及 Color Table 覆盖板材与封边数量，并核对一致")
        except RuleError as exc:
            errors.append({"code": exc.code, "message": str(exc), "path": str(root), **exc.context})
    return reports, errors


def find_existing(config: Config, report: ReportData) -> Path | None:
    folder = config.order_root / report.pp_order
    exact = folder / f"Work Order Traveler({report.traveler_file_name or report.order_name}).xlsx"
    if exact.exists():
        return exact
    if not folder.is_dir():
        return None
    target = _normalize_name(report.order_name)
    for path in folder.glob("Work Order Traveler(*).xlsx"):
        try:
            wb = load_workbook(path, data_only=False, read_only=True)
            current = _text(wb["WorkOrderTraveler"]["B5"].value)
            if _normalize_name(current) == target:
                return path
        except Exception:
            continue
    return None


def _copy_style(source, target) -> None:
    if source.has_style:
        target._style = copy.copy(source._style)
    target.number_format = source.number_format
    target.font = copy.copy(source.font)
    target.fill = copy.copy(source.fill)
    target.border = copy.copy(source.border)
    target.alignment = copy.copy(source.alignment)
    target.protection = copy.copy(source.protection)


def _write_merged(ws, coordinate: str, value) -> None:
    cell = ws[coordinate]
    if isinstance(cell, MergedCell):
        for merged in ws.merged_cells.ranges:
            if coordinate in merged:
                ws.cell(merged.min_row, merged.min_col).value = value
                return
    cell.value = value


def _insert_styled_rows(ws, idx: int, amount: int, source_row: int) -> None:
    """Insert rows while preserving the template's merged-cell row pattern."""
    if amount <= 0:
        return
    old_merges = [str(x) for x in ws.merged_cells.ranges]
    source_merges = []
    for merged in old_merges:
        min_col, min_row, max_col, max_row = range_boundaries(merged)
        if min_row == max_row == source_row:
            source_merges.append((min_col, max_col))
        ws.unmerge_cells(merged)
    ws.insert_rows(idx, amount)
    for row in range(idx, idx + amount):
        ws.row_dimensions[row].height = ws.row_dimensions[source_row].height
        for col in range(1, ws.max_column + 1):
            _copy_style(ws.cell(source_row, col), ws.cell(row, col))
        for min_col, max_col in source_merges:
            ws.merge_cells(start_row=row, start_column=min_col, end_row=row, end_column=max_col)
    for merged in old_merges:
        min_col, min_row, max_col, max_row = range_boundaries(merged)
        if min_row >= idx:
            min_row += amount
            max_row += amount
        elif max_row >= idx:
            max_row += amount
        elif max_row == idx - 1 and min_row < max_row and min_col == max_col:
            max_row += amount
        ws.merge_cells(
            start_row=min_row,
            start_column=min_col,
            end_row=max_row,
            end_column=max_col,
        )


def _find_row(ws, value: str, column: int = 3) -> int:
    for row in range(1, ws.max_row + 1):
        if _text(ws.cell(row, column).value) == value:
            return row
    raise RuleError("template_schema", f"模板中找不到字段：{value}")


def generate_traveler(
    config: Config,
    report: ReportData,
    destination: Path,
    base_path: Path | None = None,
    allow_replace: bool = False,
) -> None:
    if destination.exists() and not allow_replace:
        raise RuleError("destination_exists", f"目标文件已存在，拒绝覆盖：{destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="traveler-") as temp:
        draft = Path(temp) / destination.name
        shutil.copy2(base_path or config.template, draft)
        wb = load_workbook(draft)
        main = wb["WorkOrderTraveler"]
        pick = wb["Pickinglist"]
        main["D4"] = f"{datetime.now().year}.{datetime.now().month}.{datetime.now().day}"
        main["B5"] = report.order_name

        plywood = {x.thickness: x for x in report.panels if x.kind == "plywood"}
        standard_rows = [
            (float(thickness), row)
            for thickness, row in zip(BUSINESS_RULES["sheet_materials"]["plywood"]["thicknesses_mm"], (6, 7, 8))
        ]
        plywood_spec = "*".join(
            _fmt_number(float(value))
            for value in BUSINESS_RULES["sheet_materials"]["plywood"]["standard_size_mm"]
        )
        for thickness, row in standard_rows:
            item = plywood.get(thickness)
            label = f"{_fmt_number(thickness)}mm--plywood"
            main.cell(row, 2).value = label
            main.cell(row, 3).value = plywood_spec
            main.cell(row, 4).value = item.quantity if item else 0
            pick.cell(row, 3).value = label
            pick.cell(row, 5).value = plywood_spec
            pick.cell(row, 7).value = item.quantity if item else 0

        panel_items = [x for x in report.panels if x.kind == "panel"]
        if not panel_items:
            panel_rule = BUSINESS_RULES["sheet_materials"]["panel"]
            panel_items = [PanelItem(
                float(panel_rule["thicknesses_mm"][0]),
                "",
                "*".join(_fmt_number(float(value)) for value in panel_rule["standard_size_mm"]),
                0,
                "panel",
            )]
        extra_panels = len(panel_items) - 1
        _insert_styled_rows(main, 10, extra_panels, 9)
        _insert_styled_rows(pick, 10, extra_panels, 9)
        for offset, item in enumerate(panel_items):
            row = 9 + offset
            main.cell(row, 2).value = item.label
            main.cell(row, 3).value = item.spec.replace("×", "*")
            main.cell(row, 4).value = item.quantity
            pick.cell(row, 1).value = 4 + offset
            pick.cell(row, 3).value = item.label
            pick.cell(row, 5).value = item.spec.replace("×", "*")
            pick.cell(row, 7).value = item.quantity

        colors = sorted({x.color for x in report.panels if x.kind == "panel" and x.color})
        main_edge_row = 10 + extra_panels
        main.cell(main_edge_row, 3).value = colors[0] if len(colors) == 1 else ""
        main.cell(main_edge_row + 1, 3).value = colors[0] if len(colors) == 1 else ""
        pick_edge_row = 10 + extra_panels
        edge_items = sorted(report.edge_banding.items())
        _insert_styled_rows(pick, pick_edge_row + 1, max(0, len(edge_items) - 1), pick_edge_row)
        if report.edge_banding:
            for offset, (color, meters) in enumerate(edge_items):
                row = pick_edge_row + offset
                pick.cell(row, 1).value = 4 + len(panel_items) + offset
                pick.cell(row, 3).value = f"Edge banding--{color}"
                pick.cell(row, 5).value = "M/米"
                pick.cell(row, 7).value = round(meters, int(BUSINESS_RULES["sheet_materials"]["edge_decimals"]))
        else:
            pick.cell(pick_edge_row, 3).value = "Edge banding"
            pick.cell(pick_edge_row, 5).value = "M/米"
            pick.cell(pick_edge_row, 7).value = None

        fitting_rows = {
            "Hinge": _find_row(pick, "Hinge"),
            "Shelf Holder": _find_row(pick, "Adjustable shelf holder"),
            "H-Rail": _find_row(pick, "H-Rail"),
            "L-Rail": _find_row(pick, "L-Rail"),
        }
        units = BUSINESS_RULES["fittings"]["units"]
        for name, row in fitting_rows.items():
            pick.cell(row, 3).value = name
            pick.cell(row, 5).value = units[name]
            pick.cell(row, 7).value = report.fittings.get(name) or None

        wb.save(draft)
        check = load_workbook(draft, data_only=False, read_only=True)
        if _text(check["WorkOrderTraveler"]["B5"].value) != report.order_name:
            raise RuleError("write_verification", "生成后复查工厂单名称失败")
        os.replace(draft, destination)


def update_existing(config: Config, report: ReportData, existing: Path, rebuild: bool) -> Path:
    if not rebuild and (len([x for x in report.panels if x.kind == "panel"]) > 1 or len(report.edge_banding) > 1):
        raise RuleError(
            "complex_in_place_update",
            "现有文件包含需要动态增行的数据，请选择“按模板重新生成”，以免破坏人工内容",
        )
    backup_dir = config.backup_root / report.pp_order
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y-%m-%d %H%M%S")
    backup = backup_dir / f"{existing.stem} backup {stamp}{existing.suffix}"
    shutil.copy2(existing, backup)
    generate_traveler(
        config,
        report,
        existing,
        base_path=config.template if rebuild else existing,
        allow_replace=True,
    )
    return backup


def diff_snapshot(old: dict, new: dict) -> list[dict]:
    changes = []
    keys = sorted(set(old) | set(new))
    for key in keys:
        if old.get(key) != new.get(key):
            changes.append({"field": key, "old": old.get(key), "new": new.get(key)})
    return changes


def run(config: Config, mode: str, query: str | None = None, include_history: bool = False, write: bool = False) -> dict:
    preflight(config)
    state = StateStore(config.database)
    configured_start = datetime.strptime(config.initial_date, "%Y-%m-%d").isoformat()
    if state.get_meta("started_at") != configured_start:
        state.set_meta("started_at", configured_start)
    if not state.get_meta("template_hash"):
        state.set_meta("template_hash", hashlib.sha256(config.template.read_bytes()).hexdigest())
    current_hash = hashlib.sha256(config.template.read_bytes()).hexdigest()
    if state.get_meta("template_hash") != current_hash:
        raise RuleError("template_changed", "Traveler 模板发生变化，需要人工确认")

    started = datetime.fromisoformat(state.get_meta("started_at")).timestamp()
    progress(f"开始扫描 server，初始日期为 {config.initial_date}")
    candidates = discover(config, started, include_history, query)
    if not include_history:
        candidates = [x for x in candidates if x.mtime >= started]
    folders = sorted({
        f"{(PP_RE.search(str(candidate.path)) or ['未知PP'])[0].upper()} / {candidate.path.parent.parent.name}"
        for candidate in candidates
    })
    if folders:
        progress(f"发现 {len(folders)} 个候选源文件夹：{'、'.join(folders)}", folders=folders)
    else:
        progress("未发现符合时间和查询条件的新报表")
    progress(f"准备读取并校验 {len(candidates)} 个目标 Excel 报表")
    reports, errors = build_reports(config, candidates)
    progress(f"报表解析完成：{len(reports)} 个可处理订单，{len(errors)} 项异常")
    if query:
        q = _normalize_name(query)
        reports = [r for r in reports if q in ({_normalize_name(x) for x in (r.factory_orders or [r.factory_order])} | {_normalize_name(r.order_name), _normalize_name(r.pp_order), _normalize_name(r.traveler_file_name)})]
    if mode in ("update", "rebuild") and len(reports) != 1:
        raise RuleError("update_selection", f"更新操作必须精确匹配一个工厂单，当前匹配 {len(reports)} 个")
    result = {"mode": mode, "reports": [], "errors": errors}
    for report in reports:
        progress(f"正在处理 {report.traveler_file_name or report.order_name}", factory_orders=report.factory_orders)
        existing = find_existing(config, report)
        new_snapshot = report.managed_snapshot()
        old_snapshot = state.snapshot(_normalize_name(report.order_name))
        ignored_payload = [asdict(x) for x in report.ignored_fittings]
        ignored_changed = state.notice_changed(f"ignored:{_normalize_name(report.order_name)}", ignored_payload)
        warning_payload = {"warnings": report.warnings}
        warnings_changed = state.notice_changed(f"warnings:{_normalize_name(report.order_name)}", warning_payload)
        item = {
            "factory_order": report.factory_order,
            "factory_orders": report.factory_orders or [report.factory_order],
            "order_name": report.order_name,
            "board": str(report.board_path),
            "fittings": str(report.fittings_path),
            "materials": str(report.materials_path) if report.materials_path else None,
            "existing": str(existing) if existing else None,
            "warnings": report.warnings if warnings_changed else [],
            "ignored_fittings": ignored_payload if ignored_changed else [],
            "changes": diff_snapshot(old_snapshot, new_snapshot) if old_snapshot else [],
        }
        if write and not existing:
            destination = config.order_root / report.pp_order / f"Work Order Traveler({report.traveler_file_name or report.order_name}).xlsx"
            progress(f"正在生成 Traveler：{destination.name}")
            generate_traveler(config, report, destination)
            state.save_snapshot(_normalize_name(report.order_name), new_snapshot)
            item["created"] = str(destination)
            progress(f"Traveler 已生成：{destination.name}")
        elif mode in ("update", "rebuild"):
            if not existing:
                raise RuleError("missing_existing", f"找不到需要更新的 Traveler：{report.order_name}")
            backup = update_existing(config, report, existing, rebuild=mode == "rebuild")
            state.save_snapshot(_normalize_name(report.order_name), new_snapshot)
            item["updated"] = str(existing)
            item["backup"] = str(backup)
            progress(f"Traveler 已更新，旧版本已备份：{existing.name}")
        elif existing and old_snapshot and old_snapshot != new_snapshot:
            item["action_required"] = True
        elif existing and old_snapshot is None:
            # First sighting establishes the comparison baseline without changing the workbook.
            state.save_snapshot(_normalize_name(report.order_name), new_snapshot)
            item["baseline_created"] = True
        result["reports"].append(item)
    state.log_run(mode, "error" if errors else "ok", result)
    progress("任务完成", reports=len(result["reports"]), errors=len(errors))
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="traveler-assistant")
    parser.add_argument("mode", choices=("preview", "scan", "update", "rebuild"))
    parser.add_argument("--query")
    parser.add_argument("--include-history", action="store_true")
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--order-root", type=Path)
    parser.add_argument("--template", type=Path)
    parser.add_argument("--state-dir", type=Path)
    args = parser.parse_args(argv)
    config = Config()
    config.load_settings()
    for key in ("source_root", "order_root", "template", "state_dir"):
        if getattr(args, key):
            setattr(config, key, getattr(args, key))
    try:
        result = run(config, args.mode, args.query, args.include_history, write=args.mode == "scan")
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 2 if result["errors"] else 0
    except RuleError as exc:
        print(json.dumps({"fatal": {"code": exc.code, "message": str(exc), **exc.context}}, ensure_ascii=False, indent=2))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
