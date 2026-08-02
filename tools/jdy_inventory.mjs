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
const waitForVisibleFrame = async (page, predicate, timeoutMs = 15000) => {
  const attempts = Math.max(1, Math.ceil(timeoutMs / 250));
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    for (const frame of page.frames().filter(predicate).reverse()) {
      const frameElement = await frame.frameElement().catch(() => null);
      if (frameElement && await frameElement.isVisible().catch(() => false)) return frame;
    }
    await page.waitForTimeout(250);
  }
  return null;
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
  for (let attempt = 0; attempt < 40; attempt += 1) {
    if (
      /\/login\/?/i.test(page.url()) ||
      await page.locator('input[type="password"]:visible').count() ||
      await page.getByText("进入使用", { exact: true }).count()
    ) break;
    await page.waitForTimeout(250);
  }
  let loginScope = page;
  if (/\/login\/?/i.test(page.url())) {
    for (let attempt = 0; attempt < 40; attempt += 1) {
      const ready = await Promise.all(page.frames().map(async frame =>
        await frame.locator("input").count() || await frame.getByText(/账号登录/).count()
      ));
      if (ready.some(Boolean)) break;
      await page.waitForTimeout(250);
    }
    for (const frame of page.frames()) {
      if (
        await frame.locator('input[type="password"]').count() ||
        await frame.getByText(/账号登录/).count()
      ) {
        loginScope = frame;
        break;
      }
    }
  }
  const visiblePassword = loginScope.locator('input[type="password"]:visible');
  if (!(await visiblePassword.count()) && /\/login\/?/i.test(page.url())) {
    const accountLogin = loginScope.getByText(/账号登录/).first();
    if (await accountLogin.count()) {
      await accountLogin.click({ force: true });
      await visiblePassword.first().waitFor({ state: "visible", timeout: 5000 }).catch(() => {});
      log("已切换到账号登录");
    }
  }
  if (await visiblePassword.count()) {
    log("正在登录库存系统");
    const password = visiblePassword.first();
    const username = loginScope.locator('input[name="login_username"]:visible, input[type="text"]:visible').first();
    if (await username.count() !== 1) {
      throw new Error(`登录页可见用户名输入框数量异常：${await username.count()}`);
    }
    await username.click();
    await username.press("Meta+A");
    await username.pressSequentially(request.username, { delay: 30 });
    await password.click();
    await password.press("Meta+A");
    await password.pressSequentially(request.password, { delay: 30 });
    const agreement = loginScope.locator('#reg_agreement, #agree-protocol').first();
    if (await agreement.count()) {
      if (!(await agreement.isChecked())) {
        await agreement.evaluate(element => {
          element.checked = true;
          element.dispatchEvent(new Event("input", { bubbles: true }));
          element.dispatchEvent(new Event("change", { bubbles: true }));
        });
      }
      log("已勾选登录协议");
    }
    const login = loginScope.locator('button:visible').filter({ hasText: /^登录$/ }).first()
      .or(loginScope.locator('input[type="button"][value="登录"]:visible').first());
    if (await login.count()) {
      await login.click();
      log("登录信息已提交");
    } else {
      await password.press("Enter");
      log("已通过回车提交登录信息");
    }
    const loginLimit = loginScope.getByText(/密码登录次数已达最大限制\s*20\s*次/).first();
    if (await loginLimit.count() && await loginLimit.isVisible()) {
      throw new Error("库存系统密码登录已达到20次上限；请使用验证码或扫码登录，或退出其他在线设备后重试");
    }
    const policyAgree = loginScope.locator("#agree-protocol");
    const policyAppeared = await policyAgree.waitFor({ state: "visible", timeout: 8000 })
      .then(() => true).catch(() => false);
    if (policyAppeared) {
      await policyAgree.click({ force: true, timeout: 5000 });
      log("已确认新版隐私政策弹窗");
      await page.waitForTimeout(1500);
      if (page.url().includes("/login")) {
        const loginAgain = loginScope.locator('button:visible').filter({ hasText: /^登录$/ }).first();
        if (await loginAgain.count()) await loginAgain.click();
        else await loginScope.locator('input[type="password"]:visible').first().press("Enter");
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
  const workbenchModal = page.locator(".kd-modal-container-show:visible").first();
  if (await workbenchModal.count()) {
    const dismiss = workbenchModal.locator(
      '.kd-modal-close:visible, [aria-label*="关闭"]:visible, button:visible',
    ).filter({ hasText: /关闭|确定|知道了|同意|暂不/ }).first();
    const closeIcon = workbenchModal.locator(
      '.kd-modal-close:visible, [aria-label*="关闭"]:visible, [class*="close"]:visible',
    ).first();
    if (await dismiss.count()) await dismiss.click({ force: true });
    else if (await closeIcon.count()) await closeIcon.click({ force: true });
    else {
      throw new Error(`工作台通知弹窗无法关闭：${(await workbenchModal.innerText()).replace(/\s+/g, " ").slice(0, 180)}`);
    }
    await workbenchModal.waitFor({ state: "hidden", timeout: 5000 }).catch(() => {});
    log("已关闭工作台通知弹窗");
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
    await record.click({ force: true });
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
    log(`正在按备注精确查询历史出库单：${request.orderName}`);
    if (!(await clickVisibleText(page, "仓库"))) throw new Error("找不到可见的仓库菜单");
    const menu = page.locator('#storage\\/otherOutbound_menu');
    await menu.waitFor({ state: "visible", timeout: 10000 });
    await menu.hover({ force: true });
    const record = menu.locator('.menuRouteLinkList--1MJ6N');
    await record.waitFor({ state: "visible", timeout: 10000 });
    await record.click({ force: true });
    await page.mouse.move(800, 80);
    let listFrame;
    for (let attempt = 0; attempt < 40 && !listFrame; attempt += 1) {
      listFrame = page.frames().find(frame => frame.url().includes("action=initOiList"));
      if (!listFrame) await page.waitForTimeout(250);
    }
    if (!listFrame) throw new Error("找不到其他出库单记录列表");
    const applyDate = async (input, value) => {
      await input.evaluate((element, nextValue) => {
        element.value = nextValue;
        element.dispatchEvent(new Event("input", { bubbles: true }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
        element.dispatchEvent(new Event("blur", { bubbles: true }));
      }, value);
    };
    await applyDate(listFrame.locator(".quick-datepicker-start"), request.queryDateFrom);
    await applyDate(listFrame.locator(".quick-datepicker-end"), request.queryDateTo);
    await listFrame.locator("#matchCon").fill(request.orderName);
    await listFrame.locator("#search").click();
    await page.waitForTimeout(1200);
    const normalizedRemark = request.orderName.replace(/\s+/g, "").toUpperCase();
    const exactRows = [];
    const visibleRows = listFrame.locator("tr:visible");
    for (let index = 0; index < await visibleRows.count(); index += 1) {
      const row = visibleRows.nth(index);
      const cells = (await row.locator("td").allTextContents())
        .map(text => text.replace(/\s+/g, "").toUpperCase());
      if (cells.includes(normalizedRemark)) exactRows.push(row);
    }
    if (exactRows.length > 1) {
      throw new Error(`备注“${request.orderName}”找到 ${exactRows.length} 张出库单，请人工检查，已停止`);
    }
    let existingDocumentNumber = "";
    let formFrame;
    let isUpdate = false;
    if (exactRows.length === 1) {
      const rowText = await exactRows[0].innerText();
      existingDocumentNumber = rowText.match(/QTCK\d+/i)?.[0]?.toUpperCase() || "";
      if (!existingDocumentNumber) throw new Error(`已找到备注“${request.orderName}”，但无法读取单据编号`);
      if (!request.changed) {
        log(`出库内容未变化，跳过更新：${existingDocumentNumber}`);
        process.stdout.write(JSON.stringify({
          ok: true, saved: true, unchanged: true, remark: request.orderName,
          documentNumber: existingDocumentNumber, url: page.url(),
        }));
      } else {
        log(`已找到唯一旧单 ${existingDocumentNumber}，准备替换全部明细`);
        const documentLink = exactRows[0].getByText(existingDocumentNumber, { exact: false }).first();
        if (await documentLink.count()) await documentLink.dblclick();
        else await exactRows[0].dblclick();
        await page.waitForTimeout(1000);
        formFrame = await waitForVisibleFrame(page, frame =>
          frame !== page.mainFrame() && frame.url().includes("invOi") &&
          !frame.url().includes("action=initOiList")
        );
        if (!formFrame) throw new Error(`无法打开旧出库单 ${existingDocumentNumber}`);
        const edit = formFrame.locator(
          '#edit:visible, #editBills:visible, button:visible, a:visible',
        ).filter({ hasText: /编辑|修改/ }).first();
        if (!(await edit.count()) || await edit.isDisabled().catch(() => false)) {
          throw new Error(`旧出库单 ${existingDocumentNumber} 不可编辑，请人工处理；不会新建重复单`);
        }
        await edit.click();
        isUpdate = true;
      }
    }

    if (exactRows.length === 0) {
      log("未找到同备注旧单，正在打开新增其他出库单");
      if (!(await clickVisibleText(page, "仓库"))) throw new Error("找不到可见的仓库菜单");
      log("已打开仓库菜单");
      await exact(page, "其他出库单").click();
      await page.mouse.move(800, 80);
      await page.waitForTimeout(800);
      log("已打开新增其他出库单页面并收起菜单");
      formFrame = await waitForVisibleFrame(page, frame =>
        frame !== page.mainFrame() && frame.url().includes("invOi") &&
        !frame.url().includes("action=initOiList")
      );
    }
    if (exactRows.length !== 1 || request.changed) {
    if (!formFrame) throw new Error("找不到其他出库单内嵌表单，页面结构可能已变化");
    await formFrame.waitForLoadState("domcontentloaded").catch(() => {});
    await page.waitForTimeout(1500);
    log("已进入其他出库单表单");

    const production = formFrame.getByText("生产领料", { exact: true });
    const businessInput = formFrame.getByPlaceholder(/业务类型/);
    if (await businessInput.count()) {
      await businessInput.click();
      await production.click();
    } else if (await production.count() && await production.first().isVisible()) {
      log("业务类型已经是生产领料");
    } else {
      const labels = formFrame.getByText(/业务类型/);
      let input;
      for (let labelIndex = 0; labelIndex < await labels.count() && !input; labelIndex += 1) {
        const candidates = labels.nth(labelIndex).locator("xpath=following::input");
        for (let inputIndex = 0; inputIndex < Math.min(await candidates.count(), 12); inputIndex += 1) {
          const candidate = candidates.nth(inputIndex);
          if (await candidate.isVisible() && !(await candidate.isDisabled())) {
            input = candidate;
            break;
          }
        }
      }
      if (!input) {
        const visibleInputs = await formFrame.locator("input:visible").evaluateAll(inputs =>
          inputs.slice(0, 30).map(element => ({
            id: element.id || "",
            name: element.getAttribute("name") || "",
            placeholder: element.getAttribute("placeholder") || "",
          })),
        );
        throw new Error(`无法定位可见的业务类型输入框：${JSON.stringify(visibleInputs)}`);
      }
      await input.click();
      await production.click();
    }
    log("业务类型已设置为生产领料");

    const remark = formFrame.getByPlaceholder(/备注/);
    if (await remark.count()) await remark.fill(request.orderName);
    else await formFrame.locator("textarea").first().fill(request.orderName);
    log(`备注已填写：${request.orderName}`);
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
    if (isUpdate) {
      const rows = formFrame.locator("tbody:visible tr:visible");
      while (await rows.count() > request.items.length) {
        const last = rows.nth((await rows.count()) - 1);
        await last.click();
        const remove = formFrame.locator(
          '.ui-icon-minus:visible, .icon-delete:visible, .delete-row:visible, [title*="删除行"]:visible',
        ).first();
        if (!(await remove.count())) {
          throw new Error(`旧出库单 ${existingDocumentNumber} 有多余明细，但找不到删除行按钮，已停止保存`);
        }
        await remove.click({ force: true });
        await page.waitForTimeout(200);
      }
      if (await rows.count() !== request.items.length) {
        throw new Error(`旧出库单 ${existingDocumentNumber} 明细行数未能完整替换，已停止保存`);
      }
      log(`旧出库单 ${existingDocumentNumber} 的全部明细已替换`);
    }

    if (!request.confirmSave) {
      log("模拟填写完成，已停在保存之前");
      process.stdout.write(JSON.stringify({
        ok: true, saved: false, remark: request.orderName,
        documentNumber: existingDocumentNumber, url: page.url(),
      }));
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
      if (!documentMatch && !existingDocumentNumber) throw new Error("保存前无法读取单据编号，已停止保存");
      let documentNumber = existingDocumentNumber || documentMatch[1];
      const suffixMatch = documentNumber.match(/^(.*?)(\d+)$/);
      if (!suffixMatch) throw new Error(`单据编号无法递增：${documentNumber}`);
      const prefix = suffixMatch[1];
      const suffixWidth = suffixMatch[2].length;
      const initialSuffix = Number(suffixMatch[2]);
      let saved = false;
      for (let attempt = 0; attempt <= 10; attempt += 1) {
        const responsePromise = page.waitForResponse(
          response => response.url().includes("invOi.do?action=") &&
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
        if (!isUpdate && Number(payload.status) === 400 && message.includes("单据编号重复")) {
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
      log(`${isUpdate ? "出库单更新" : "出库单新增"}成功：${documentNumber}`);
      process.stdout.write(JSON.stringify({
        ok: true, saved: true, unchanged: false, updated: isUpdate,
        remark: request.orderName, documentNumber, url: page.url(),
      }));
    }
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
