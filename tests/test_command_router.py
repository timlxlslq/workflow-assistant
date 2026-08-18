import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from traveler_assistant.agent_runner import AgentDecision, AgentRouteResult
from traveler_assistant.assistant_cli import _agent_command, _factory_name_belongs_to_order
from traveler_assistant.command_router import LocalCommand, normalize_command_text, parse_local_command
from traveler_assistant.core import Config, RuleError
from traveler_assistant.runtime_store import RuntimeStore
from traveler_assistant.tool_gateway import _order_folder, execute_local_command


class LocalCommandRouterTests(unittest.TestCase):
    def test_common_phrasings_are_zero_token_commands(self):
        expected = LocalCommand("preview_order", {"order_id": "PP1234"})
        self.assertEqual(parse_local_command("查找PP1234"), expected)
        self.assertEqual(parse_local_command("在服务器上找一下 PP1234"), expected)

    def test_spoken_mixed_digits_are_normalized_before_routing(self):
        expected = LocalCommand("preview_order", {"order_id": "PP0068"})
        self.assertEqual(parse_local_command("查找 PP 0零6八"), expected)
        self.assertEqual(parse_local_command("查找 P P 零 零 六 八"), expected)
        self.assertEqual(normalize_command_text("查找 PP 0零35杠二"), "查找pp0035-2")

    def test_stock_comparison_has_priority_over_order_preview(self):
        expected = LocalCommand("check_inventory_stock", {"order_id": "CS004"})
        self.assertEqual(parse_local_command("比对CS004的库存"), expected)
        self.assertEqual(parse_local_command("查询 CS004 库存"), expected)
        self.assertEqual(parse_local_command("Check inventory for CS004"), expected)

    def test_write_commands_require_approval(self):
        self.assertEqual(
            parse_local_command("生成 PP1234 的 Traveler"),
            LocalCommand("generate_traveler", {"order_id": "PP1234"}, True),
        )
        self.assertEqual(
            parse_local_command("更新Traveler PP1234"),
            LocalCommand("update_traveler", {"order_id": "PP1234"}, True),
        )
        self.assertEqual(
            parse_local_command("给 PP1234-2-LAUNDRY 添加人工五金 M0144 数量 2 备注现场增加"),
            LocalCommand(
                "add_manual_hardware",
                {
                    "order_id": "PP1234-2",
                    "factory_name": "PP1234-2-LAUNDRY",
                    "product_code": "M0144",
                    "quantity": "2",
                    "remarks": "现场增加",
                },
                True,
            ),
        )

    def test_manual_hardware_gateway_stops_at_preview_without_approval(self):
        command = LocalCommand(
            "add_manual_hardware",
            {
                "order_id": "PP1234-2",
                "factory_name": "PP1234-2-LAUNDRY",
                "product_code": "M0144",
                "quantity": "2",
            },
            True,
        )
        with patch(
            "traveler_assistant.tool_gateway.preview_manual_hardware",
            return_value={"product_code": "M0144", "quantity": 2},
        ), patch("traveler_assistant.tool_gateway.add_manual_hardware") as write:
            result = execute_local_command(Config(), command)
        self.assertEqual(result["status"], "approval_required")
        write.assert_not_called()

    def test_stock_comparison_uses_database_order_facts(self):
        with patch(
            "traveler_assistant.inventory.check_database_stock",
            return_value={"source_type": "database", "rows": [{"productCode": "M0020"}], "hasShortage": False},
        ) as check:
            result = execute_local_command(
                Config(),
                LocalCommand("check_inventory_stock", {"order_id": "CS004"}),
            )
        check.assert_called_once_with(unittest.mock.ANY, "CS004")
        self.assertEqual(result["result_type"], "stock_comparison")
        self.assertEqual(result["order_id"], "CS004")

    def test_cut_to_size_commands_use_the_cut_to_size_source(self):
        with tempfile.TemporaryDirectory() as temp:
            server = Path(temp)
            optimized = server / "Optimized Orders"
            cut_to_size = server / "CUT TO SIZE"
            pp_folder = optimized / "pp0068"
            cs_folder = cut_to_size / "cs004"
            pp_folder.mkdir(parents=True)
            cs_folder.mkdir(parents=True)
            config = Config(source_root=optimized)
            self.assertEqual(_order_folder(config, "PP0068"), pp_folder)
            self.assertEqual(_order_folder(config, "CS004"), cs_folder)

    def test_missing_order_reports_the_directory_actually_searched(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "Optimized Orders"
            root.mkdir()
            with self.assertRaises(RuleError) as raised:
                _order_folder(Config(source_root=root), "PP0063-2")
            self.assertEqual(raised.exception.context["searched_root"], str(root))
            self.assertEqual(raised.exception.context["match_count"], 0)
            self.assertIn(str(root), str(raised.exception))

    def test_unrecognized_text_requests_agent(self):
        self.assertIsNone(parse_local_command("帮我看看今天应该先处理什么"))

    def test_agent_factory_suffix_is_rebuilt_only_when_present_in_user_text(self):
        route = AgentRouteResult(
            AgentDecision(
                action="add_manual_hardware",
                order_id="PP9999",
                factory_name="KITCHEN",
                product_code="M2000",
                quantity=2,
                explanation="添加人工五金",
            ),
            10,
            5,
        )
        with tempfile.TemporaryDirectory() as temp:
            store = RuntimeStore(Path(temp) / "workflow.sqlite3")
            with patch("traveler_assistant.agent_runner.route_with_agent", return_value=route):
                command, _ = _agent_command(
                    store,
                    "帮我在 PP9999-KITCHEN 的人工五金里补两件 M2000",
                )
            self.assertEqual(command.arguments["factory_name"], "PP9999-KITCHEN")

            with patch("traveler_assistant.agent_runner.route_with_agent", return_value=route):
                rejected, _ = _agent_command(store, "给 PP9999 添加两件 M2000")
            self.assertIsNone(rejected)

    def test_split_order_factory_name_is_not_mixed_into_base_order(self):
        self.assertTrue(_factory_name_belongs_to_order("PP0035", "PP0035-OFFICE"))
        self.assertTrue(_factory_name_belongs_to_order("PP0035-2", "PP0035-2-MASTER"))
        self.assertTrue(_factory_name_belongs_to_order("PP0035-2", "PP0035-2 OPENSHELF"))
        self.assertFalse(_factory_name_belongs_to_order("PP0035", "PP0035-2-MASTER"))

    def test_gateway_rejects_unknown_tools(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(RuleError) as raised:
                execute_local_command(
                    Config(source_root=Path(temp)),
                    LocalCommand("delete_everything"),
                )
        self.assertEqual(raised.exception.code, "unknown_tool")


if __name__ == "__main__":
    unittest.main()
