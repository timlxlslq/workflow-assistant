import { chromium } from "playwright";
import fs from "node:fs";

const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const request = JSON.parse(Buffer.concat(chunks).toString("utf8"));
const log = message => process.stderr.write(`${JSON.stringify({ event: "progress", message })}\n`);
const exact = (page, text) => page.getByText(text, { exact: true });
const clickVisibleText = async (page, text) => {
  const matches = page.getByText(text, { exact: true });
  for (let index = (await matches.count()) - 1; index >= 0; index -= 1) {
    const item = matches.nth(index);
    if (await item.isVisible()) {
      await item.click();
      return true;
    }
  }
  return false;
};

let context;
let page;
try {
  fs.mkdirSync(request.profileDir, { recursive: true });
  log("正在打开库存系统浏览器");
  context = await chromium.launchPersistentContext(request.profileDir, {
    executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    headless: true,
    acceptDownloads: true,
    locale: "zh-CN",
    extraHTTPHeaders: { "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.5" },
    args: ["--no-first-run", "--no-default-browser-check"],
  });
  page = context.pages()[0] || await context.newPage();
  await page.goto("https://service.jdy.com/workbench/web/index.html", {
    waitUntil: "domcontentloaded",
    timeout: 30000,
  });
  await page.waitForTimeout(2000);
  log("库存系统登录页连接成功");
  if (page.url().includes("/global/")) {
    const acceptCookies = page.getByRole("button", { name: "Accept All", exact: true }).first();
    if (await acceptCookies.count()) await acceptCookies.click();
    const regionClose = page.getByText("Close", { exact: true });
    if (await regionClose.count() && await regionClose.last().isVisible()) await regionClose.last().click();
    const signIn = page.locator('a:visible, button:visible').filter({ hasText: /^Sign in$/ }).first();
    const pageCount = context.pages().length;
    await signIn.click();
    await page.waitForTimeout(2000);
    if (context.pages().length > pageCount) page = context.pages().at(-1);
    await page.waitForLoadState("domcontentloaded").catch(() => {});
    log("已从英文全球站返回库存系统登录入口");
  }
  const visiblePassword = page.locator('input[type="password"]:visible');
  if (await visiblePassword.count()) {
    log("正在登录库存系统");
    const password = visiblePassword.first();
    const username = page.locator('input[name="login_username"]:visible, input[type="text"]:visible').first();
    if (await username.count() !== 1) {
      throw new Error(`登录页可见用户名输入框数量异常：${await username.count()}`);
    }
    await username.click();
    await username.press("Meta+A");
    await username.pressSequentially(request.username, { delay: 30 });
    await password.click();
    await password.press("Meta+A");
    await password.pressSequentially(request.password, { delay: 30 });
    const agreement = page.locator('input[type="checkbox"]:visible').first();
    if (await agreement.count() && !(await agreement.isChecked())) {
      await agreement.check({ force: true });
      log("已勾选登录协议");
    }
    const login = page.locator('button:visible').filter({ hasText: /^登录$/ }).first()
      .or(page.locator('input[type="button"][value="登录"]:visible').first());
    if (await login.count()) {
      await login.click();
      log("登录信息已提交");
    } else {
      await password.press("Enter");
      log("已通过回车提交登录信息");
    }
    const loginLimit = page.getByText(/密码登录次数已达最大限制\s*20\s*次/).first();
    if (await loginLimit.count() && await loginLimit.isVisible()) {
      throw new Error("库存系统密码登录已达到20次上限；请使用验证码或扫码登录，或退出其他在线设备后重试");
    }
    const policyAgree = page.locator("#agree-protocol");
    const policyAppeared = await policyAgree.waitFor({ state: "visible", timeout: 8000 })
      .then(() => true).catch(() => false);
    if (policyAppeared) {
      await policyAgree.click({ force: true, timeout: 5000 });
      log("已确认新版隐私政策弹窗");
      await page.waitForTimeout(1500);
      if (page.url().includes("/login")) {
        const loginAgain = page.locator('button:visible').filter({ hasText: /^登录$/ }).first();
        if (await loginAgain.count()) await loginAgain.click();
        else await page.locator('input[type="password"]:visible').first().press("Enter");
        log("隐私政策确认后已重新提交登录");
      } else {
        log("隐私政策确认后登录成功");
      }
    }
  } else {
    if (page.url().includes("service.jdy.com")) log("正在复用已有登录状态");
    else throw new Error(`未找到登录表单，也不在已登录工作台：${page.url()}`);
  }

  const englishControl = page.locator('button:visible, a:visible, div:visible, span:visible')
    .filter({ hasText: /^English$/ }).last();
  if (await englishControl.count()) {
    await englishControl.click({ force: true });
    const chinese = page.getByText("简体中文", { exact: true }).last();
    await chinese.waitFor({ state: "visible", timeout: 5000 });
    await chinese.click();
    await page.waitForTimeout(1500);
    log("工作台语言已切回简体中文");
  }
  const enter = page.getByText("进入使用", { exact: true });
  await enter.first().waitFor({ state: "visible", timeout: 30000 });
  const enterCount = await enter.count();
  if (enterCount !== 1) throw new Error(`检测到 ${enterCount} 个“进入使用”按钮，需要人工判断`);
  const newProductPage = context.waitForEvent("page", { timeout: 15000 }).catch(() => null);
  await enter.click();
  const openedPage = await newProductPage;
  if (openedPage) page = openedPage;
  await page.waitForLoadState("domcontentloaded").catch(() => {});
  if (page.url().includes("service.jdy.com/workbench")) {
    await page.waitForURL(url => !url.href.includes("service.jdy.com/workbench"), { timeout: 30000 });
  }
  log("已进入库存系统工作台");

  if (request.action === "preflight") {
    log("库存系统连接与登录状态正常");
    process.stdout.write(JSON.stringify({ ok: true, url: page.url() }));
  } else if (request.action === "exportProducts") {
    log("正在打开商品列表");
    await exact(page, "商品").first().click();
    await exact(page, "商品").last().click();
    await page.mouse.move(800, 100);
    const downloadPromise = page.waitForEvent("download", { timeout: 30000 });
    await page.getByText("导出", { exact: true }).click();
    const download = await downloadPromise;
    await download.saveAs(request.downloadPath);
    process.stdout.write(JSON.stringify({ ok: true, downloadPath: request.downloadPath }));
  } else if (request.action === "findOutbound") {
    if (!(await clickVisibleText(page, "仓库"))) throw new Error("找不到可见的仓库菜单");
    const menu = page.locator('#storage\\/otherOutbound_menu');
    await menu.waitFor({ state: "visible", timeout: 10000 });
    await menu.hover({ force: true });
    const record = menu.locator('.menuRouteLinkList--1MJ6N');
    await record.waitFor({ state: "visible", timeout: 10000 });
    await record.click();
    await page.mouse.move(800, 80);
    let listFrame;
    for (let attempt = 0; attempt < 40 && !listFrame; attempt += 1) {
      listFrame = page.frames().find(frame => frame.url().includes("action=initOiList"));
      if (!listFrame) await page.waitForTimeout(250);
    }
    if (!listFrame) throw new Error("找不到其他出库单记录列表");
    const startDate = listFrame.locator(".quick-datepicker-start");
    const endDate = listFrame.locator(".quick-datepicker-end");
    if (await startDate.count() !== 1 || await endDate.count() !== 1) {
      throw new Error("无法唯一定位其他出库单查询日期范围");
    }
    const applyDate = async (input, value) => {
      await input.evaluate((element, nextValue) => {
        element.value = nextValue;
        element.dispatchEvent(new Event("input", { bubbles: true }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
        element.dispatchEvent(new Event("blur", { bubbles: true }));
      }, value);
    };
    await applyDate(startDate, request.queryDateFrom);
    await applyDate(endDate, request.queryDateTo);
    log(`出库记录查询范围：${request.queryDateFrom} 至 ${request.queryDateTo}`);
    const search = listFrame.locator("#matchCon");
    await search.fill(request.orderName);
    const searchResponse = page.waitForResponse(
      response => response.url().includes("invOi.do") &&
        response.request().method() === "POST",
      { timeout: 15000 },
    ).catch(() => null);
    await listFrame.locator("#search").click();
    await searchResponse;
    await page.waitForTimeout(1200);
    const allRows = await listFrame.locator("tr").allTextContents();
    const matches = await listFrame.locator("tr")
      .filter({ hasText: new RegExp(request.orderName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i") })
      .allTextContents();
    process.stdout.write(JSON.stringify({
      ok: true,
      orderName: request.orderName,
      matches,
      rowCount: allRows.length,
    }));
  } else {
    log("正在打开其他出库单");
    if (!(await clickVisibleText(page, "仓库"))) throw new Error("找不到可见的仓库菜单");
    log("已打开仓库菜单");
    await exact(page, "其他出库单").click();
    await page.mouse.move(800, 80);
    await page.waitForTimeout(800);
    log("已打开新增其他出库单页面并收起菜单");
    const formFrame = await page.waitForEvent("framenavigated", {
      predicate: frame => frame !== page.mainFrame() && frame.url().includes("invOi"),
      timeout: 15000,
    }).catch(() => page.frames().find(frame => frame !== page.mainFrame() && frame.url().includes("invOi")));
    if (!formFrame) throw new Error("找不到其他出库单内嵌表单，页面结构可能已变化");
    log("已进入其他出库单表单");

    const production = formFrame.getByText("生产领料", { exact: true });
    const businessInput = formFrame.getByPlaceholder(/业务类型/);
    if (await businessInput.count()) {
      await businessInput.click();
      await production.click();
    } else {
      const label = formFrame.getByText(/业务类型/).first();
      const input = label.locator("xpath=following::input[1]");
      await input.click();
      await production.click();
    }
    log("业务类型已设置为生产领料");

    const remark = formFrame.getByPlaceholder(/备注/);
    if (await remark.count()) await remark.fill(request.orderName);
    else await formFrame.locator("textarea").first().fill(request.orderName);
    log(`备注已填写工厂单名称：${request.orderName}`);
    const headers = formFrame.locator("thead:visible th");
    const headerTexts = (await headers.allTextContents()).map(text => text.replace(/\s+/g, ""));
    const productHeader = headerTexts.findIndex(text => text.startsWith("*商品"));
    const quantityHeader = headerTexts.findIndex(text => text.startsWith("*数量"));
    if (productHeader < 0 || quantityHeader < 0) {
      throw new Error(`无法识别商品或数量列：${headerTexts.join(" | ")}`);
    }
    const productColumnId = await headers.nth(productHeader).getAttribute("id");
    const quantityColumnId = await headers.nth(quantityHeader).getAttribute("id");
    if (!productColumnId || !quantityColumnId) throw new Error("商品或数量表头缺少关联ID");
    log(`已识别表格列：${productColumnId} / ${quantityColumnId}`);

    for (let index = 0; index < request.items.length; index += 1) {
      const item = request.items[index];
      log(`正在填写 ${index + 1}/${request.items.length}：${item.productCode}`);
      const rows = formFrame.locator("tbody:visible tr:visible");
      while (await rows.count() <= index) {
        const plus = formFrame.locator(
          '.ui-icon-plus:visible, .icon-add:visible, .add-row:visible, [title*="新增"]:visible, [title*="添加"]:visible',
        ).first();
        if (await plus.count()) await plus.click({ force: true });
        else throw new Error("出库单行数不足，且找不到增加行按钮");
      }
      const row = rows.nth(index);
      const productCell = row.locator(`td[aria-describedby="${productColumnId}"]`);
      const quantityCell = row.locator(`td[aria-describedby="${quantityColumnId}"]`);
      if (await productCell.count() !== 1 || await quantityCell.count() !== 1) {
        throw new Error(`第 ${index + 1} 行无法唯一定位商品或数量单元格`);
      }
      await productCell.click();
      const goodsEditor = formFrame.locator('input[name="goods"]:visible');
      await goodsEditor.waitFor({ state: "visible", timeout: 5000 });
      await goodsEditor.fill(item.productCode);
      await goodsEditor.press("Enter");
      await page.waitForTimeout(1200);
      const escapedCode = item.productCode.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      if (!(await row.innerText()).includes(item.productCode)) {
        let goodsFrame;
        for (let attempt = 0; attempt < 40 && !goodsFrame; attempt += 1) {
          goodsFrame = page.frames().find(frame => frame.url().includes("goods-batch.jsp"));
          if (!goodsFrame) await page.waitForTimeout(250);
        }
        if (!goodsFrame) throw new Error(`商品 ${item.productCode} 输入后未精确匹配`);
        let productRow;
        for (let pageNumber = 1; pageNumber <= 20; pageNumber += 1) {
          const candidates = goodsFrame.locator("tbody:visible tr:visible")
            .filter({ hasText: new RegExp(`(?:^|\\s)${escapedCode}(?:\\s|$)`) });
          if (await candidates.count()) {
            productRow = candidates.first();
            break;
          }
          const next = goodsFrame.locator(
            '.ui-icon-seek-next:visible, [title*="下一页"]:visible, [aria-label*="下一页"]:visible',
          ).first();
          if (!(await next.count())) break;
          await next.click({ force: true });
          await page.waitForTimeout(500);
        }
        if (!productRow) throw new Error(`商品选择窗口中找不到 ${item.productCode}`);
        await productRow.click();
        const chooseAndClose = formFrame.getByText("选中并关闭", { exact: true });
        if (await chooseAndClose.count()) await chooseAndClose.click();
        else await productRow.dblclick();
        await formFrame.locator("#ldg_lockmask").waitFor({ state: "hidden", timeout: 10000 });
      }
      const selectedRowText = (await row.innerText()).replace(/\s+/g, " ").trim();
      if (!selectedRowText.includes(item.productCode)) {
        throw new Error(`商品选择结果不一致：要求 ${item.productCode}，实际行内容 ${selectedRowText}`);
      }
      await quantityCell.click();
      const quantityEditor = formFrame.locator('input[name="qty"]:visible');
      await quantityEditor.waitFor({ state: "visible", timeout: 5000 });
      await quantityEditor.evaluate((input, value) => {
        input.value = value;
      }, String(item.quantity));
      await quantityEditor.press("Enter");
      await page.waitForTimeout(300);
      const rowText = (await row.innerText()).replace(/\s+/g, " ").trim();
      if (!rowText) throw new Error(`商品 ${item.productCode} 填写后表格行仍为空`);
      const displayedQuantity = (await quantityCell.innerText()).replace(/,/g, "").trim();
      const parsedQuantity = Number(displayedQuantity);
      if (!Number.isFinite(parsedQuantity) || Math.abs(parsedQuantity - Number(item.quantity)) > 0.0001) {
        throw new Error(
          `商品 ${item.productCode} 数量回读不一致：Traveler=${item.quantity}，库存表格=${displayedQuantity || "空"}`,
        );
      }
      log(`已填写商品 ${item.productCode}，数量 ${item.quantity}`);
    }

    if (!request.confirmSave) {
      log("模拟填写完成，已停在保存之前");
      process.stdout.write(JSON.stringify({ ok: true, saved: false, url: page.url() }));
      await new Promise(resolve => setTimeout(resolve, request.keepOpenMs || 3000));
    } else {
      log("已获得确认，正在保存出库单");
      const activeEditors = formFrame.locator('input[name="goods"]:visible, input[name="qty"]:visible');
      await formFrame.getByText("单据日期", { exact: false }).first().click();
      if (await activeEditors.count()) {
        await activeEditors.first().waitFor({ state: "hidden", timeout: 5000 }).catch(() => {});
      }
      log("已提交当前表格编辑状态");
      const formText = await formFrame.locator("body").innerText();
      const documentMatch = formText.match(/单据编号[：:]\s*([A-Za-z0-9_-]+)/);
      if (!documentMatch) throw new Error("保存前无法读取单据编号，已停止保存");
      let documentNumber = documentMatch[1];
      const suffixMatch = documentNumber.match(/^(.*?)(\d+)$/);
      if (!suffixMatch) throw new Error(`单据编号无法递增：${documentNumber}`);
      const prefix = suffixMatch[1];
      const suffixWidth = suffixMatch[2].length;
      const initialSuffix = Number(suffixMatch[2]);
      let saved = false;
      for (let attempt = 0; attempt <= 10; attempt += 1) {
        const responsePromise = page.waitForResponse(
          response => response.url().includes("invOi.do?action=addOo") &&
            response.request().method() === "POST",
          { timeout: 20000 },
        ).then(response => ({ kind: "response", response }))
          .catch(error => ({ kind: "timeout", error }));
        const dialogPromise = page.waitForEvent("dialog", { timeout: 20000 })
          .then(dialog => ({ kind: "dialog", dialog }))
          .catch(error => ({ kind: "timeout", error }));
        await formFrame.locator("#save:visible").click();
        let outcome = await Promise.race([responsePromise, dialogPromise]);
        if (outcome.kind === "dialog") {
          const warning = outcome.dialog.message();
          if (!request.forceWarnings) {
            await outcome.dialog.dismiss();
            throw new Error(`保存需要人工确认：${warning}`);
          }
          await outcome.dialog.accept();
          log(`已按人工授权确认库存系统警告：${warning}`);
          outcome = await responsePromise;
        }
        if (outcome.kind !== "response") {
          throw new Error("点击保存后库存系统未返回结果，请人工核实");
        }
        const response = outcome.response;
        const payload = await response.json().catch(() => ({}));
        const message = String(payload.msg || payload.message || "");
        if (Number(payload.status) === 400 && message.includes("单据编号重复")) {
          if (attempt >= 10) throw new Error("单据编号连续重试10次仍然重复");
          await page.waitForTimeout(2000);
          await formFrame.locator("#ldg_lockmask").waitFor({ state: "hidden", timeout: 10000 }).catch(() => {});
          documentNumber = prefix + String(initialSuffix + attempt + 1).padStart(suffixWidth, "0");
          await formFrame.locator("#editBills").click();
          const numberEditor = formFrame.locator("#numberAuto input:visible");
          await numberEditor.waitFor({ state: "visible", timeout: 5000 });
          await numberEditor.fill(documentNumber);
          await numberEditor.press("Enter");
          await formFrame.getByText("单据日期", { exact: false }).first().click();
          await numberEditor.waitFor({ state: "hidden", timeout: 5000 }).catch(() => {});
          const committedNumber = (await formFrame.locator("#number").innerText()).trim();
          if (committedNumber !== documentNumber) {
            throw new Error(`单据编号修改未生效：要求 ${documentNumber}，页面显示 ${committedNumber || "空"}`);
          }
          await page.waitForTimeout(1500);
          const saveDisabled = await formFrame.locator("#save").isDisabled().catch(() => false);
          if (saveDisabled) throw new Error("修改重复单据编号后，库存系统的保存按钮仍处于禁用状态");
          log(`单据编号重复，已改为 ${documentNumber}、回读确认并准备重试`);
          continue;
        }
        if (![0, 200].includes(Number(payload.status)) && payload.success !== true) {
          throw new Error(`库存系统拒绝保存：${message || JSON.stringify(payload)}`);
        }
        saved = true;
        break;
      }
      if (!saved) throw new Error("库存系统未返回明确保存成功");
      log(`出库单保存成功：${documentNumber}`);
      process.stdout.write(JSON.stringify({ ok: true, saved: true, documentNumber, url: page.url() }));
    }
  }
} catch (error) {
  let pageInfo = "";
  try {
    const body = (await page.locator("body").innerText()).replace(/\s+/g, " ").slice(0, 300);
    pageInfo = `；当前页面：${page.url()}；页面提示：${body}`;
  } catch {}
  process.stderr.write(`库存系统自动操作失败：${error?.message || String(error)}${pageInfo}\n`);
  process.exitCode = 1;
} finally {
  if (context) await context.close();
}
