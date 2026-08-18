from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from agents import Agent, ModelSettings, Runner, set_tracing_disabled
from dotenv import load_dotenv
from openai import RateLimitError
from openai.types.shared import Reasoning
from pydantic import BaseModel


MODEL = "gpt-5.6-luna"


class AgentDecision(BaseModel):
    action: Literal[
        "list_orders",
        "preview_order",
        "check_inventory_stock",
        "generate_traveler",
        "update_traveler",
        "add_manual_hardware",
        "unsupported",
    ]
    order_id: str | None = None
    factory_name: str | None = None
    product_code: str | None = None
    quantity: int | None = None
    remarks: str | None = None
    explanation: str


@dataclass(frozen=True)
class AgentRouteResult:
    decision: AgentDecision
    input_tokens: int
    output_tokens: int


INSTRUCTIONS = """你是工作流程助手的轻量路由 Agent。你只把用户表达转换为一个结构化动作，不读取文件、不执行工具、不修改任何系统。

支持的动作：
- list_orders：查看或刷新订单列表，不需要订单号。
- preview_order：查找、查看、检查某个订单，需要 PP0063、PP0063-2 或 CS004 形式的订单号。
- check_inventory_stock：直接用中央数据库订单事实比对某个订单的板材和封边实时库存，不要求生成 Traveler，需要订单号。
- generate_traveler：生成或创建 Traveler，需要订单号。
- update_traveler：更新 Traveler，需要订单号。
- add_manual_hardware：在已生成 Traveler 的指定工厂单中添加人工五金，必须同时取得 order_id、完整 factory_name、product_code 和正整数 quantity；备注可选。`PP9999-KITCHEN` 和 `PP1234-2-LAUNDRY` 都是完整 factory_name：订单号后可以直接接房间名，也可以先带分单编号。
- unsupported：不属于以上动作，或者必要订单号缺失。

“在服务器上找一下 PP0063”属于 preview_order。“比对 CS004 的库存”属于 check_inventory_stock。“帮我在 PP1234-2-LAUNDRY 的人工五金里补两件 M0144”属于 add_manual_hardware，order_id 是 PP1234-2，quantity 是 2。不要猜测缺失的字段。explanation 只用一句简短中文说明。"""


def _load_api_key() -> None:
    load_dotenv(Path.home() / "Documents" / "工作流程助手" / ".env.local", override=False)
    if not os.environ.get("OPENAI_API_KEY"):
        raise RuntimeError("未配置 OPENAI_API_KEY。")


async def _run(text: str) -> AgentRouteResult:
    _load_api_key()
    set_tracing_disabled(True)
    agent = Agent(
        name="Workflow Router",
        instructions=INSTRUCTIONS,
        model=MODEL,
        model_settings=ModelSettings(
            reasoning=Reasoning(effort="low"),
            max_tokens=2048,
            verbosity="low",
            store=False,
        ),
        output_type=AgentDecision,
    )
    result = await Runner.run(agent, text, max_turns=1)
    usage = result.context_wrapper.usage
    return AgentRouteResult(
        decision=result.final_output,
        input_tokens=usage.input_tokens,
        output_tokens=usage.output_tokens,
    )


def route_with_agent(text: str) -> AgentRouteResult:
    try:
        return asyncio.run(_run(text))
    except RateLimitError as exc:
        if getattr(exc, "code", None) == "billing_not_active":
            raise RuntimeError("OpenAI API 项目尚未启用计费，Agent 暂不可用。") from None
        if getattr(exc, "code", None) == "credit_balance_exhausted":
            raise RuntimeError("OpenAI API 当前项目仍显示余额为 0，请检查 Billing 余额后再试。") from None
        raise
