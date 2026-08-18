from __future__ import annotations

import re
from dataclasses import dataclass, field


ORDER_ID_RE = re.compile(r"(PP\d{4}(?:-\d+)?|CS\d{3})", re.IGNORECASE)
SPOKEN_ORDER_ID_RE = re.compile(
    r"(?P<prefix>p\s*p|c\s*s)\s*(?P<number>[0-9零〇○一二两三四五六七八九幺\s]+)"
    r"(?:(?:-|\s*[杠横]\s*)"
    r"(?P<suffix>[0-9零〇○一二两三四五六七八九幺\s]+))?",
    re.IGNORECASE,
)
SPOKEN_DIGITS = str.maketrans(
    {"零": "0", "〇": "0", "○": "0", "一": "1", "幺": "1", "二": "2", "两": "2",
     "三": "3", "四": "4", "五": "5", "六": "6", "七": "7", "八": "8", "九": "9"}
)
MANUAL_HARDWARE_RE = re.compile(
    r"^\u7ed9(?P<factory>pp\d{4}.*?)\u6dfb\u52a0(?:\u4eba\u5de5)?\u4e94\u91d1"
    r"(?P<product_code>[a-z]\d+)(?:\u6570\u91cf)?(?P<quantity>\d+)"
    r"(?:\u4e2a|\u4ef6|\u5957)?(?:\u5907\u6ce8(?P<remarks>.+))?$",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class LocalCommand:
    action: str
    arguments: dict[str, str] = field(default_factory=dict)
    requires_approval: bool = False


def normalize_spoken_order_ids(text: str) -> str:
    """Canonicalize digit-by-digit speech transcripts such as ``PP 0零6八``."""
    def replace(match: re.Match[str]) -> str:
        prefix = re.sub(r"\s+", "", match.group("prefix")).upper()
        number = re.sub(r"\s+", "", match.group("number")).translate(SPOKEN_DIGITS)
        suffix = match.group("suffix")
        if suffix is not None:
            suffix = re.sub(r"\s+", "", suffix).translate(SPOKEN_DIGITS)
            return f"{prefix}{number}-{suffix}"
        return f"{prefix}{number}"

    return SPOKEN_ORDER_ID_RE.sub(replace, text)


def normalize_command_text(text: str) -> str:
    text = normalize_spoken_order_ids(text)
    return re.sub(r"[\s，。！？,!.?]+", "", text).lower()


def parse_local_command(text: str) -> LocalCommand | None:
    normalized = normalize_command_text(text)
    if not normalized:
        return None

    if normalized in {"刷新订单", "刷新订单列表", "查看订单", "订单列表"}:
        return LocalCommand("list_orders")

    manual_hardware = MANUAL_HARDWARE_RE.fullmatch(normalized)
    if manual_hardware:
        factory_name = manual_hardware.group("factory").upper()
        order = ORDER_ID_RE.match(factory_name)
        if order is None:
            return None
        arguments = {
            "order_id": order.group(1).upper(),
            "factory_name": factory_name,
            "product_code": manual_hardware.group("product_code").upper(),
            "quantity": manual_hardware.group("quantity"),
        }
        if remarks := manual_hardware.group("remarks"):
            arguments["remarks"] = remarks
        return LocalCommand("add_manual_hardware", arguments, True)

    match = ORDER_ID_RE.search(normalized)
    if not match:
        return None
    order_id = match.group(1).upper()
    arguments = {"order_id": order_id}

    if any(word in normalized for word in ("库存", "stock", "inventory")):
        return LocalCommand("check_inventory_stock", arguments)
    if ("生成" in normalized or "创建" in normalized) and (
        "traveler" in normalized or "生产单" in normalized
    ):
        return LocalCommand("generate_traveler", arguments, True)
    if "更新" in normalized and ("traveler" in normalized or "生产单" in normalized):
        return LocalCommand("update_traveler", arguments, True)
    if any(word in normalized for word in ("预览", "查看", "查找", "找一下", "查询", "检查")):
        return LocalCommand("preview_order", arguments)
    return None
