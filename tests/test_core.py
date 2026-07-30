import tempfile
import unittest
import json
from unittest.mock import patch
from pathlib import Path

from openpyxl import load_workbook

from traveler_assistant.core import (
    Config,
    BUSINESS_RULES,
    Candidate,
    PanelItem,
    ReportData,
    _include_full_sheet,
    _normalize_name,
    generate_traveler,
    build_reports,
    lookup_aimes_names,
    map_fittings,
    parse_board,
    parse_fittings,
    parse_fittings_groups,
    parse_materials,
    RuleError,
)


SAMPLE_LOCATIONS = (
    Path("/Volumes/server/Optimized Orders/pp0047/pp0047kitchen/Report"),
    Path.home() / "Library/Mobile Documents/com~apple~CloudDocs/PacificPride/Other/pp0047/pp0047kitchen/Report",
)
SAMPLE = next((path for path in SAMPLE_LOCATIONS if path.is_dir()), SAMPLE_LOCATIONS[0])


class CoreTests(unittest.TestCase):
    def test_structured_business_rules_are_loaded(self):
        self.assertEqual(BUSINESS_RULES["sheet_materials"]["plywood"]["standard_size_mm"], [2440, 1220])
        self.assertEqual(BUSINESS_RULES["sheet_materials"]["thickness_aliases"]["5"], 5.4)
        self.assertEqual(BUSINESS_RULES["fittings"]["direct_codes"]["WJ-CBT"], "Shelf Holder")

    def test_name_normalization(self):
        self.assertEqual(_normalize_name("pp0047-kitchen"), "PP0047KITCHEN")
        self.assertEqual(_normalize_name("PP0047 kitchen"), "PP0047KITCHEN")

    def test_sheet_size_rules(self):
        self.assertTrue(_include_full_sheet("2440*1220*18", (2440, 1220), 100))
        self.assertFalse(_include_full_sheet("2200*1100*18", (2440, 1220), 100))

    def test_settings_load_initial_date_and_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp)
            (state / "settings.json").write_text(json.dumps({
                "initial_date": "2026-07-22",
                "company_wifi": "Test WiFi",
                "source_root": "/tmp/orders",
                "leftover_threshold_mm": 80,
            }))
            config = Config(state_dir=state)
            config.load_settings()
            self.assertEqual(config.initial_date, "2026-07-22")
            self.assertEqual(config.company_wifi, "Test WiFi")
            self.assertEqual(config.source_root, Path("/tmp/orders"))
            self.assertEqual(config.leftover_threshold_mm, 80)

    def test_aimes_lookup_requires_machine_local_username(self):
        with self.assertRaises(RuleError) as raised:
            lookup_aimes_names(Config(aimes_username=""), ["F999"])
        self.assertEqual(raised.exception.code, "aimes_credentials")

    @unittest.skipUnless(SAMPLE.is_dir(), "PP0047 server or iCloud sample is not available")
    def test_parse_kitchen_samples(self):
        board = SAMPLE / "pp-板材清单-newPC124429962607020002.xlsx"
        fittings = SAMPLE / "FittingslistPC124429962607020002.xlsx"
        factory, order, panels, edge = parse_board(board, 100)
        ff, items = parse_fittings(fittings)
        mapped, ignored = map_fittings(items)
        self.assertEqual(factory, ff)
        self.assertEqual(order, "PP0047-KITCHEN")
        self.assertEqual(mapped["Hinge"], 36)
        self.assertEqual(mapped["Shelf Holder"], 36)
        self.assertEqual(mapped["H-Rail"], 12)
        self.assertEqual(mapped["L-Rail"], 7)
        self.assertTrue(edge)
        self.assertTrue(ignored)

    def test_dynamic_panel_and_edge_rows(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            config = Config(order_root=root / "orders")
            report = ReportData(
                "F999",
                "PP9999-TEST",
                "PP9999",
                root,
                root / "board.xlsx",
                root / "fittings.xlsx",
                [
                    PanelItem(18, "", "2440*1220", 2, "plywood"),
                    PanelItem(19.1, "Woodline 4", "2745*1220", 3, "panel"),
                    PanelItem(9, "Ivory Oak", "2745*1220", 1, "panel"),
                ],
                {"Ivory Oak": 12.34, "Woodline 4": 56.78},
                {"Hinge": 4, "Shelf Holder": 8, "H-Rail": 2, "L-Rail": 1},
                [],
            )
            output = root / "out.xlsx"
            generate_traveler(config, report, output)
            wb = load_workbook(output, data_only=True)
            self.assertEqual(wb["WorkOrderTraveler"]["B10"].value, "9mm--Ivory Oak")
            self.assertEqual(wb["Pickinglist"]["C12"].value, "Edge banding--Woodline 4")
            self.assertEqual(wb["Pickinglist"]["C16"].value, "Shelf Holder")

    @unittest.skipUnless(
        Path("/Volumes/server/Optimized Orders/pp0046").is_dir(),
        "PP0046 server sample is not available",
    )
    def test_pp0046_multi_factory_and_materials(self):
        root = Path("/Volumes/server/Optimized Orders/pp0046")
        report = root / "pp0046 1st_2nd_master autolabel/Report"
        groups = parse_fittings_groups(report / "FittingslistPC124429962607230001.xlsx")
        self.assertEqual([group[0] for group in groups], ["F2607220204", "F2607220203", "F2607220205"])
        mapped, _ = map_fittings([item for _, items in groups for item in items])
        self.assertEqual(mapped["Hinge"], 16)
        self.assertEqual(mapped["H-Rail"], 10)
        self.assertEqual(mapped["L-Rail"], 1)
        materials = parse_materials(root / "pp0046 materials.xlsx")
        quantities = {(item.kind, item.thickness, item.color): item.quantity for item in materials.panels}
        self.assertEqual(quantities[("plywood", 18, "")], 6)
        self.assertEqual(quantities[("plywood", 5.4, "")], 2)
        self.assertEqual(quantities[("panel", 19.1, "Antracita SM")], 1)
        self.assertEqual(quantities[("panel", 19.1, "Woodline 3")], 2)

    @unittest.skipUnless(
        Path("/Volumes/server/Optimized Orders/pp0046").is_dir(),
        "PP0046 server sample is not available",
    )
    def test_pp0046_builds_one_merged_report(self):
        root = Path("/Volumes/server/Optimized Orders/pp0046")
        report_dir = root / "pp0046 1st_2nd_master autolabel/Report"
        candidates = [
            Candidate("board", report_dir / "pp-板材清单-newPC124429962607230001.xlsx", "", mtime=1),
            Candidate("fittings", report_dir / "FittingslistPC124429962607230001.xlsx", "", mtime=1),
        ]
        names = {"F2607220204": "PP0046-MASTER", "F2607220203": "PP0046-2ND", "F2607220205": "PP0046-1ST"}
        with patch("traveler_assistant.core.lookup_aimes_names", return_value=names):
            reports, errors = build_reports(Config(source_root=root), candidates)
        self.assertEqual(errors, [])
        self.assertEqual(len(reports), 1)
        self.assertEqual(reports[0].order_name, "PP0046-MASTER/PP0046-2ND/PP0046-1ST")
        self.assertEqual(reports[0].traveler_file_name, "pp0046 1st_2nd_master autolabel")
        self.assertEqual(reports[0].fittings["Hinge"], 16)
        self.assertEqual(reports[0].materials_path, root / "pp0046 materials.xlsx")
        self.assertTrue(any("materials 与原报表汇总不一致" in warning for warning in reports[0].warnings))
        self.assertEqual(reports[0].edge_banding["Antracita SM"], 29.09)


if __name__ == "__main__":
    unittest.main()
