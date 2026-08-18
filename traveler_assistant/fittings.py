"""Shared Fittingslist selection rules.

Fittingslist files can be copied into several room folders while retaining the
same factory-order blocks.  This module is deliberately independent of
Traveler generation so database synchronization and on-demand Traveler
rendering use the same source-selection contract.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Callable, Iterable

from .core import FittingItem, RuleError, parse_fittings_groups


EPSILON = 1e-9


def fitting_signature(items: Iterable[FittingItem]) -> tuple:
    return tuple(sorted(
        (
            str(item.name or "").strip(),
            str(item.code or "").strip().upper(),
            str(item.size or "").strip(),
            str(item.unit or "").strip(),
            round(float(item.quantity), 6),
        )
        for item in items
    ))


@dataclass(frozen=True)
class SelectedFittings:
    path: Path
    modified_at: float
    items: tuple[FittingItem, ...]
    signature: tuple


def select_latest_fittings(
    paths: Iterable[Path],
    *,
    allow_missing_factory: bool = False,
    fallback_factory: str = "",
    is_empty_report: Callable[[Path], bool] | None = None,
) -> tuple[dict[str, SelectedFittings], list[str], bool, list[Path]]:
    """Select one Fittingslist block per factory order.

    Returns ``(selected, warnings, found_files, skipped_empty_files)``.  A
    factory order is selected from the newest file.  Equal-time files with
    different content stop the selection so the caller cannot silently choose
    an arbitrary source.
    """
    occurrences: dict[str, list[SelectedFittings]] = {}
    found_files = False
    skipped_empty: list[Path] = []
    for path in sorted({Path(path) for path in paths}, key=lambda item: str(item).casefold()):
        found_files = True
        try:
            groups = parse_fittings_groups(
                path,
                allow_missing_factory=allow_missing_factory,
                fallback_factory=fallback_factory,
            )
        except RuleError:
            if is_empty_report is not None and is_empty_report(path):
                skipped_empty.append(path)
                continue
            raise
        modified_at = path.stat().st_mtime
        for factory, items in groups:
            if not any(float(item.quantity) > 0 for item in items):
                continue
            candidate = SelectedFittings(
                path=path,
                modified_at=modified_at,
                items=tuple(items),
                signature=fitting_signature(items),
            )
            occurrences.setdefault(factory.upper(), []).append(candidate)

    selected: dict[str, SelectedFittings] = {}
    warnings: list[str] = []
    for factory, matches in sorted(occurrences.items()):
        newest_time = max(item.modified_at for item in matches)
        newest = [item for item in matches if abs(item.modified_at - newest_time) < EPSILON]
        newest_signatures = {item.signature for item in newest}
        if len(newest_signatures) > 1:
            raise RuleError(
                "fittings_timestamp_tie",
                f"{factory} 的多个最新 Fittingslist 修改时间相同但五金内容不同，请人工检查",
                files=[str(item.path) for item in newest],
            )
        chosen = newest[0]
        selected[factory] = chosen
        all_signatures = {item.signature for item in matches}
        if len(all_signatures) > 1:
            older = [str(item.path) for item in matches if item.path != chosen.path]
            warnings.append(
                f"{factory} 在不同 Fittingslist 中内容不一致；已采用修改时间最新的 {chosen.path.name}"
                f"（{datetime.fromtimestamp(chosen.modified_at).isoformat(timespec='seconds')}），"
                f"较旧文件：{'、'.join(older)}"
            )
        elif len(matches) > 1:
            warnings.append(f"{factory} 在 {len(matches)} 份 Fittingslist 中重复且内容一致，已自动去重")
    return selected, warnings, found_files, skipped_empty
