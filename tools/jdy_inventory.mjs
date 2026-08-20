import { chromium } from "playwright";
import fs from "node:fs";
import path from "node:path";

const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const request = JSON.parse(Buffer.concat(chunks).toString("utf8"));
const processStartedAt = performance.now();
const UI_STEP_TIMEOUT = 15000;
const PAGE_NAVIGATION_TIMEOUT = 30000;
const DOWNLOAD_TIMEOUT = 60000;
const elapsedSeconds = startedAt => ((performance.now() - startedAt) / 1000).toFixed(2);
const safePageURL = () => {
  try {
    if (!page) return "";
    const current = new URL(page.url());
    return `${current.origin}${current.pathname}`;
  } catch {
    return "";
  }
};
const log = message => process.stderr.write(`${JSON.stringify({
  event: "progress",
  message: `[+${elapsedSeconds(processStartedAt)}s] ${message}`,
  page_url: safePageURL(),
})}\n`);
const timed = async (label, operation) => {
  const startedAt = performance.now();
  log(`${label}：开始`);
  try {
    const result = await operation();
    log(`${label}：完成，耗时 ${elapsedSeconds(startedAt)} 秒`);
    return result;
  } catch (error) {
    log(`${label}：失败，耗时 ${elapsedSeconds(startedAt)} 秒`);
    throw error;
  }
};
const timedWait = async (page, milliseconds, label) =>
  timed(`${label}（计划等待 ${(milliseconds / 1000).toFixed(2)} 秒）`, () =>
    page.waitForTimeout(milliseconds));
const exact = (page, text) => page.getByText(text, { exact: true });
const firstVisible = async locator => {
  for (let index = 0; index < await locator.count(); index += 1) {
    const candidate = locator.nth(index);
    if (await candidate.isVisible().catch(() => false)) return candidate;
  }
  return null;
};
const clickVisibleText = async (page, text) => {
  const matches = page.getByText(text, { exact: true });
  for (let index = (await matches.count()) - 1; index >= 0; index -= 1) {
    const item = matches.nth(index);
    if (await item.isVisible().catch(() => false)) {
      const clicked = await item.click().then(() => true).catch(() => false);
      if (clicked) return true;
    }
  }
  return false;
};
const clickVisibleTextAcrossFrames = async (page, text) => {
  for (const frame of page.frames().reverse()) {
    if (await clickVisibleText(frame, text)) return true;
  }
  return false;
};
const visibleTextLocatorsAcrossFrames = async (page, text) => {
  const matches = [];
  for (const frame of page.frames().reverse()) {
    const locator = frame.getByText(text, { exact: true });
    for (let index = 0; index < await locator.count(); index += 1) {
      const candidate = locator.nth(index);
      if (await candidate.isVisible().catch(() => false)) matches.push(candidate);
    }
  }
  return matches;
};
const visibleLeftNavigationLocators = async (page, text) => {
  const locator = page.mainFrame().getByText(text, { exact: true });
  const matches = [];
  for (let index = 0; index < await locator.count(); index += 1) {
    const candidate = locator.nth(index);
    if (await candidate.isVisible().catch(() => false)) matches.push(candidate);
  }
  return matches;
};
const waitForVisibleLeftNavigationItem = async (page, text, timeoutMs = UI_STEP_TIMEOUT) => {
  const attempts = Math.max(1, Math.ceil(timeoutMs / 250));
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const matches = await visibleLeftNavigationLocators(page, text);
    if (matches.length) return matches;
    await page.waitForTimeout(250);
  }
  throw new Error(`左侧菜单中等待可见“${text}”超过 ${timeoutMs / 1000} 秒`);
};
const inventoryMenuForAction = action => action === "exportProducts" ? "商品" : "仓库";
const waitForInventoryActionShell = async currentPage => {
  if (request.action === "preflight") return;
  const menuText = inventoryMenuForAction(request.action);
  await waitForVisibleLeftNavigationItem(currentPage, menuText, PAGE_NAVIGATION_TIMEOUT);
};
const waitForVisibleTextAcrossFrames = async (page, text, timeoutMs = UI_STEP_TIMEOUT) => {
  const attempts = Math.max(1, Math.ceil(timeoutMs / 250));
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const matches = await visibleTextLocatorsAcrossFrames(page, text);
    if (matches.length) return matches;
    await page.waitForTimeout(250);
  }
  throw new Error(`等待可见“${text}”控件超过 ${timeoutMs / 1000} 秒`);
};
const visiblePatternLocatorsAcrossFrames = async (page, pattern) => {
  const matches = [];
  for (const frame of page.frames().reverse()) {
    const locator = frame.getByText(pattern);
    for (let index = 0; index < await locator.count(); index += 1) {
      const candidate = locator.nth(index);
      if (await candidate.isVisible().catch(() => false)) matches.push(candidate);
    }
  }
  return matches;
};
const waitForVisiblePatternToDisappear = async (page, pattern, timeoutMs = UI_STEP_TIMEOUT) => {
  const attempts = Math.max(1, Math.ceil(timeoutMs / 250));
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    if (!(await visiblePatternLocatorsAcrossFrames(page, pattern)).length) return;
    await page.waitForTimeout(250);
  }
  throw new Error(`等待网页提示消失超过 ${timeoutMs / 1000} 秒`);
};
const moveAndClick = async (label, locator) => {
  await timed(`移动鼠标到${label}`, () => locator.hover());
  await timed(`点击${label}`, () => locator.click());
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
const hasVisibleLocator = async (frame, selector) => {
  try {
    return await frame.locator(selector).count() > 0;
  } catch {
    return false;
  }
};
const decodedURL = rawURL => {
  try {
    return decodeURIComponent(rawURL || "");
  } catch {
    return rawURL || "";
  }
};
const isOtherOutboundListURL = rawURL => {
  const url = decodedURL(rawURL);
  return /(?:[?&#]|&)action=initOiList(?:[&#]|$)/i.test(url);
};
const hasOtherOutboundListControls = async frame => {
  const requiredSelectors = [
    ".quick-datepicker-start:visible",
    ".quick-datepicker-end:visible",
    "#matchCon:visible",
    "#search:visible",
  ];
  for (const selector of requiredSelectors) {
    if (!(await hasVisibleLocator(frame, selector))) return false;
  }
  return true;
};
const isOtherOutboundListFrame = async frame => {
  // The route can appear before initOiList has rendered its query controls.
  // A URL alone is therefore not evidence that the page is query-ready.
  // Some tenant workbenches keep the shell URL while rendering the list
  // inside a route/frame, so visible controls are the readiness contract.
  return hasOtherOutboundListControls(frame);
};
const isOtherOutboundFormFrame = async frame => {
  if (frame === page?.mainFrame()) return false;
  if (!frame.url().includes("invOi") || isOtherOutboundListURL(frame.url())) return false;
  const hasSave = await frame.locator("#save:visible").count() > 0;
  const hasTable = await frame.locator("thead:visible th").count() > 0;
  return hasSave && hasTable;
};
const normalizeGridText = value => String(value || "")
  .replace(/\u00a0/g, " ")
  .replace(/\s+/g, " ")
  .trim();
const outboundMaterialRows = async frame => {
  const rows = frame.locator("tbody:visible tr:visible");
  const snapshots = [];
  let codeColumnSeen = false;
  for (let index = 0; index < await rows.count(); index += 1) {
    const row = rows.nth(index);
    const codeCell = row.locator('td[aria-describedby="grid_invNumber"]').first();
    if (!(await codeCell.count())) continue;
    codeColumnSeen = true;
    const productCode = normalizeGridText(await codeCell.textContent());
    if (!productCode || productCode === "合计：") continue;
    snapshots.push({ row, productCode, text: normalizeGridText(await row.innerText()) });
  }
  if (!codeColumnSeen) {
    throw new Error("保存前未找到库存商品编码列，已停止保存");
  }
  return snapshots;
};
const assertOutboundFormMatchesRequest = async (frame, items, quantityColumnId) => {
  const snapshots = await outboundMaterialRows(frame);
  const expectedCodes = items.map(item => item.productCode);
  if (snapshots.length !== items.length) {
    throw new Error(`保存前发现 ${snapshots.length} 行非空材料，预期 ${items.length} 行；已停止保存`);
  }
  for (const item of items) {
    const matches = snapshots.filter(snapshot => snapshot.productCode === item.productCode);
    if (matches.length !== 1) {
      throw new Error(`保存前商品 ${item.productCode} 明细不唯一，已停止保存`);
    }
    const quantityCell = matches[0].row.locator(`td[aria-describedby="${quantityColumnId}"]`);
    const displayedQuantity = (await quantityCell.innerText()).replace(/,/g, "").trim();
    const parsedQuantity = Number(displayedQuantity);
    if (!Number.isFinite(parsedQuantity) || Math.abs(parsedQuantity - Number(item.quantity)) > 0.0001) {
      throw new Error(`保存前商品 ${item.productCode} 数量不一致：预期 ${item.quantity}，实际 ${displayedQuantity || "空"}`);
    }
  }
  const unexpected = snapshots.filter(snapshot =>
    !expectedCodes.includes(snapshot.productCode)
  );
  if (unexpected.length) {
    throw new Error(`保存前发现 ${unexpected.length} 行非本次出库材料，已停止保存`);
  }
};
const currentOtherOutboundListFrame = async page => {
  for (const frame of page.frames().reverse()) {
    if (await isOtherOutboundListFrame(frame)) return frame;
  }
  return null;
};
const currentOtherOutboundFormFrame = async page => {
  for (const frame of page.frames().reverse()) {
    if (await isOtherOutboundFormFrame(frame)) return frame;
  }
  return null;
};
const waitForOtherOutboundListFrame = async (page, timeoutMs = PAGE_NAVIGATION_TIMEOUT) => {
  const attempts = Math.max(1, Math.ceil(timeoutMs / 250));
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    for (const frame of page.frames().reverse()) {
      if (await hasOtherOutboundListControls(frame)) return frame;
    }
    await page.waitForTimeout(250);
  }
  return null;
};
const waitForOtherOutboundFormFrame = async (page, timeoutMs = PAGE_NAVIGATION_TIMEOUT) => {
  const attempts = Math.max(1, Math.ceil(timeoutMs / 250));
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    for (const frame of page.frames().reverse()) {
      if (await isOtherOutboundFormFrame(frame)) return frame;
    }
    await page.waitForTimeout(250);
  }
  return null;
};
const clickOtherOutboundHistory = async page => {
  const candidates = await visibleTextLocatorsAcrossFrames(page, "历史单据");
  for (const candidate of candidates.reverse()) {
    if (!(await candidate.isVisible().catch(() => false))) continue;
    const newPagePromise = context.waitForEvent("page", { timeout: 3000 }).catch(() => null);
    await moveAndClick("其他出库单中的历史单据", candidate);
    const openedPage = await newPagePromise;
    if (openedPage) {
      page = openedPage;
      await page.waitForLoadState("domcontentloaded").catch(() => {});
    }
    const listFrame = await waitForOtherOutboundListFrame(page);
    if (listFrame) {
      log("已通过“历史单据”打开其他出库单记录列表");
      return { page, listFrame };
    }
  }
  return null;
};
const clickOtherOutboundHistoryWithRetry = async currentPage => {
  const first = await clickOtherOutboundHistory(currentPage);
  if (first) return first;
  log("历史单据页面未完成加载，准备重新打开后重试");
  await currentPage.reload({ waitUntil: "domcontentloaded", timeout: 12000 }).catch(() => {});
  await currentPage.waitForTimeout(500);
  return clickOtherOutboundHistory(currentPage);
};
const openOtherOutboundMenuItem = async (page, label = "其他出库单") => {
  const warehouseItems = await waitForVisibleLeftNavigationItem(page, "仓库", PAGE_NAVIGATION_TIMEOUT);
  const warehouse = warehouseItems.at(-1);
  // Some workbench versions open the second-level menu on hover, while
  // others also require a click. Start with hover, then retry the visible
  // menu item before clicking the parent again (a second click can close a
  // toggle menu in some accounts).
  const clickVisibleMenuText = async () => {
    const candidates = await visibleTextLocatorsAcrossFrames(page, label);
    for (const candidate of candidates.reverse()) {
      if (!(await candidate.isVisible().catch(() => false))) continue;
      await candidate.hover({ force: true }).catch(() => {});
      const clicked = await candidate.click({ force: true }).then(() => true).catch(() => false);
      if (clicked) return true;
    }
    return false;
  };
  const clickVisibleMenuLink = async () => {
    for (const frame of page.frames().reverse()) {
      const menu = frame.locator('#storage\\/otherOutbound_menu:visible').last();
      if (!(await menu.count())) continue;
      await menu.hover({ force: true }).catch(() => {});
      const directLink = menu.locator(
        'a:visible, button:visible, [role="menuitem"]:visible, li:visible',
      ).filter({ hasText: new RegExp("^\\s*" + label + "\\s*$") }).last();
      if (await directLink.count()) {
        await directLink.click({ force: true });
        return true;
      }
      const route = menu.locator('.menuRouteLinkList--1MJ6N:visible').last();
      if (await route.count()) {
        await route.click({ force: true });
        return true;
      }
    }
    return false;
  };

  await warehouse.hover({ force: true }).catch(() => {});
  for (let attempt = 0; attempt < 80; attempt += 1) {
    if (await clickVisibleMenuText()) return;
    if (await clickVisibleMenuLink()) return;
    if (attempt === 3 || attempt === 12 || attempt === 24) {
      await warehouse.click({ force: true }).catch(() => {});
    }
    await page.waitForTimeout(250);
  }
  throw new Error(`仓库菜单已打开，但找不到“${label}”入口`);
};
const openOtherOutboundList = async currentPage => {
  const existing = await currentOtherOutboundListFrame(currentPage);
  if (existing) {
    log("已复用当前页面中的其他出库单记录列表");
    const ready = await waitForOtherOutboundListFrame(page);
    if (ready) return ready;
    log("当前其他出库单列表控件未就绪，准备通过左侧菜单重新打开");
  }
  const historyFromCurrentPage = await clickOtherOutboundHistoryWithRetry(currentPage);
  if (historyFromCurrentPage) {
    page = historyFromCurrentPage.page;
    return historyFromCurrentPage.listFrame;
  }
  await openOtherOutboundMenuItem(currentPage);
  page = currentPage;
  await page.mouse.move(800, 80);
  const listFrame = await waitForOtherOutboundListFrame(page);
  if (listFrame) return listFrame;
  // In the current tenant, clicking “其他出库单” opens the blank entry form
  // (initOi), while the searchable history is opened by its “历史单据” button.
  // Do not treat the entry form as a failed list load; follow the page's own
  // navigation to the actual initOiList view.
  log("“其他出库单”已打开新增表单，准备点击“历史单据”进入记录列表");
  const historyFromForm = await clickOtherOutboundHistoryWithRetry(page);
  if (historyFromForm) {
    page = historyFromForm.page;
    return historyFromForm.listFrame;
  }
  if (!listFrame) throw new Error("找不到其他出库单记录列表");
  return listFrame;
};

let context;
let page;
let remoteBrowser;
let temporaryProfile = "";
let cdpEndpointAvailable = false;
let keepBrowserOpenOnExit = request.keepBrowserOpen === true;
let securityChallengeDetected = false;
let loginResponseObservedAt = null;
let loginSubmittedAt = null;
let securityChallengeResolve;
const securityChallenge = new Promise(resolve => {
  securityChallengeResolve = resolve;
});
const isInventoryDomainURL = rawURL => {
  try {
    const parsed = new URL(rawURL);
    const hostname = parsed.hostname.toLowerCase().replace(/\.$/, "");
    return (parsed.protocol === "http:" || parsed.protocol === "https:") &&
      (hostname === "jdy.com" || hostname.endsWith(".jdy.com"));
  } catch {
    return false;
  }
};
const isInventoryLoginOrGlobalURL = rawURL => {
  try {
    const parsed = new URL(rawURL);
    const path = parsed.pathname.toLowerCase();
    return /\/(?:login|logout)(?:\/|$)/i.test(path) ||
      path.replace(/\/$/, "") === "/global" ||
      parsed.searchParams.get("logout")?.toLowerCase() === "true";
  } catch {
    return true;
  }
};
const isInventoryWorkbenchURL = url =>
  isInventoryDomainURL(url) && !isInventoryLoginOrGlobalURL(url);
const isInventoryPage = candidate => {
  const url = candidate.url();
  return isInventoryWorkbenchURL(url);
};
const isServiceWorkbenchURL = rawURL => {
  try {
    const parsed = new URL(rawURL);
    return new Set(["service.jdy.com", "www.jdy.com"]).has(parsed.hostname.toLowerCase()) &&
      parsed.pathname.toLowerCase().startsWith("/workbench");
  } catch {
    return false;
  }
};
const ensureInventoryBusinessWorkbench = async currentPage => {
  page = currentPage;
  if (!isServiceWorkbenchURL(page.url())) return page;
  log("当前停留在库存服务工作台，准备点击“进入使用”进入业务系统");
  const modal = page.locator(".kd-modal-container-show:visible").first();
  if (await modal.count()) {
    const close = await firstVisible(modal.locator(
      '.kd-modal-close:visible, [aria-label*="关闭"]:visible, [class*="close"]:visible, button:visible',
    ));
    if (close) await close.click({ force: true });
    else await page.keyboard.press("Escape");
    await modal.waitFor({ state: "hidden", timeout: 5000 }).catch(() => {});
  }
  const enter = page.getByText("进入使用", { exact: true });
  await enter.first().waitFor({ state: "visible", timeout: UI_STEP_TIMEOUT });
  if (await enter.count() !== 1) {
    throw new Error(`库存服务工作台检测到 ${await enter.count()} 个“进入使用”按钮，无法安全选择`);
  }
  const beforeURL = page.url();
  const openedPagePromise = context.waitForEvent("page", { timeout: PAGE_NAVIGATION_TIMEOUT }).catch(() => null);
  const navigatedPromise = page.waitForURL(url => !isServiceWorkbenchURL(url.href), {
    timeout: PAGE_NAVIGATION_TIMEOUT,
  }).then(() => null).catch(() => null);
  await timed("点击服务工作台“进入使用”", () => enter.click({ force: true }));
  const openedPage = await Promise.race([openedPagePromise, navigatedPromise]);
  if (openedPage) page = openedPage;
  if (page.url() === beforeURL) {
    await page.waitForTimeout(1000);
  }
  await page.waitForLoadState("domcontentloaded").catch(() => {});
  if (isServiceWorkbenchURL(page.url())) {
    throw new Error("点击“进入使用”后仍停留在库存服务工作台，未进入业务系统");
  }
  await waitForInventoryActionShell(page);
  log("已从服务工作台进入库存业务系统");
  return page;
};
const attachToExistingInventoryChrome = async endpoint => {
  try {
    const browser = await chromium.connectOverCDP(endpoint);
    cdpEndpointAvailable = true;
    const candidates = browser.contexts().flatMap(browserContext => browserContext.pages());
    const inventoryPages = candidates.filter(candidate => isInventoryPage(candidate));
    let existingPage = null;
    if (new Set(["outbound", "findOutbound"]).has(request.action)) {
      // Prefer the tab that already contains the outbound list. CDP can expose
      // several authenticated workbench tabs, and choosing the first one can
      // attach to a generic shell while the user is looking at another tab.
      for (const candidate of inventoryPages) {
        if (await currentOtherOutboundListFrame(candidate) ||
            await currentOtherOutboundFormFrame(candidate)) {
          existingPage = candidate;
          break;
        }
      }
    }
    // The service portal is an entry page, not the business workbench. Prefer
    // an already-entered tenant page for every action; if it is the only page,
    // ensureInventoryBusinessWorkbench() will click “进入使用” below.
    existingPage ||= inventoryPages.find(candidate => !isServiceWorkbenchURL(candidate.url())) ||
      inventoryPages[0] || null;
    if (!existingPage) {
      // Playwright's Browser has close(), not Puppeteer's disconnect(). For a
      // browser connected over CDP, close() disposes the Playwright connection
      // and leaves the user's Chrome process running.
      await browser.close();
      return false;
    }
    remoteBrowser = browser;
    context = existingPage.context();
    page = existingPage;
    log(`发现已打开的库存系统浏览器，直接复用当前 Chrome 页面（共 ${inventoryPages.length} 个库存标签页）`);
    return true;
  } catch {
    return false;
  }
};

const closeInventoryChrome = async endpoint => {
  try {
    const browser = await chromium.connectOverCDP(endpoint);
    const session = await browser.newBrowserCDPSession();
    await session.send("Browser.close");
    return true;
  } catch {
    return false;
  }
};

// Browser.close() on a Playwright CDP connection only disconnects Playwright.
// Normal App termination uses the browser-level CDP command to close the
// dedicated Chrome itself.
if (request.action === "closeChrome") {
  const endpoint = request.cdpEndpoint || "http://127.0.0.1:9222";
  const closed = await closeInventoryChrome(endpoint);
  process.stdout.write(JSON.stringify({ ok: true, closed }));
  process.exit(0);
}

try {
  fs.mkdirSync(request.profileDir, { recursive: true });
  const headless = request.headless !== false;
  const cdpEndpoint = request.cdpEndpoint || "http://127.0.0.1:9222";
  const attached = await timed("连接已有库存系统 Chrome", () =>
    attachToExistingInventoryChrome(cdpEndpoint));
  if (!attached) log(headless ? "正在后台连接库存系统" : "正在打开库存系统浏览器（排障模式）");
  const launchOptions = {
    executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    headless,
    acceptDownloads: true,
    locale: "zh-CN",
    extraHTTPHeaders: { "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.5" },
    args: ["--no-first-run", "--no-default-browser-check"],
  };
  if (!attached) {
    if (!cdpEndpointAvailable) {
      launchOptions.args.push(`--remote-debugging-port=${new URL(cdpEndpoint).port || "9222"}`);
    }
    try {
      context = await timed("启动库存系统浏览器", () =>
        chromium.launchPersistentContext(request.profileDir, launchOptions));
    } catch (error) {
      const message = String(error?.message || error);
      if (
        (message.includes("address already in use") || message.includes("Unable to connect to the browser")) &&
        launchOptions.args.some(argument => argument.startsWith("--remote-debugging-port="))
      ) {
        log("已有 Chrome 未打开库存系统页面，改用独立受控浏览器");
        launchOptions.args = launchOptions.args.filter(argument => !argument.startsWith("--remote-debugging-port="));
        context = await chromium.launchPersistentContext(request.profileDir, launchOptions);
      } else if (message.includes("ProcessSingleton") || message.includes("profile is already in use")) {
        temporaryProfile = await fs.promises.mkdtemp(path.join(request.profileDir, "retry-session-"));
        log("上次浏览器仍在运行，已切换独立会话继续查询");
        context = await timed("启动独立库存系统浏览器会话", () =>
          chromium.launchPersistentContext(temporaryProfile, launchOptions));
      } else {
        throw error;
      }
    }
    page = context.pages()[0] || await context.newPage();
  }
  page.on("response", async response => {
    if (!response.url().includes("/commonservice/ajaxChecking.do")) return;
    loginResponseObservedAt = performance.now();
    const body = await response.text().catch(() => "");
    try {
      const payload = JSON.parse(body);
      if (payload && payload.challenge && payload.gt) {
        securityChallengeDetected = true;
        securityChallengeResolve(true);
      }
    } catch {
      // A non-JSON response is handled by the normal login timeout below.
    }
  });
  if (!attached) {
  await timed("打开库存系统入口页面", () => page.goto("https://www.jdy.com/login/", {
    waitUntil: "domcontentloaded",
    timeout: 30000,
  }));
  await timedWait(page, 2000, "等待入口页面初始化");
  log("库存系统登录页连接成功");
  if (page.url().includes("/global/")) {
    const acceptCookies = page.getByRole("button", { name: "Accept All", exact: true }).first();
    if (await acceptCookies.count()) await acceptCookies.click();
    const regionClose = page.getByText("Close", { exact: true });
    if (await regionClose.count() && await regionClose.last().isVisible()) await regionClose.last().click();
    const signIn = page.locator('a:visible, button:visible').filter({ hasText: /^Sign in$/ }).first();
    const pageCount = context.pages().length;
    if (await signIn.count()) {
      await timed("点击全球站 Sign in", () => signIn.click());
    } else {
      log("全球站未显示登录按钮，正在直接打开库存系统登录入口");
      await timed("直接打开库存系统登录入口", () => page.goto("https://www.jdy.com/login/", {
        waitUntil: "domcontentloaded",
        timeout: 30000,
      }));
    }
    await timedWait(page, 2000, "等待登录入口跳转");
    if (context.pages().length > pageCount) page = context.pages().at(-1);
    await page.waitForLoadState("domcontentloaded").catch(() => {});
    log("已从英文全球站返回库存系统登录入口");
  }
  const loginEntryWaitStartedAt = performance.now();
  for (let attempt = 0; attempt < 40; attempt += 1) {
    if (
      /\/login\/?/i.test(page.url()) ||
      await page.locator('input[type="password"]:visible').count() ||
      await page.getByText("进入使用", { exact: true }).count()
    ) break;
    await page.waitForTimeout(250);
  }
  log(`等待登录入口元素：实际耗时 ${elapsedSeconds(loginEntryWaitStartedAt)} 秒`);
  let loginScope = page;
  if (/\/login\/?/i.test(page.url())) {
    const loginFrameWaitStartedAt = performance.now();
    for (let attempt = 0; attempt < 40; attempt += 1) {
      const ready = await Promise.all(page.frames().map(async frame =>
        await frame.locator("input").count() || await frame.getByText(/账号登录/).count()
      ));
      if (ready.some(Boolean)) break;
      await page.waitForTimeout(250);
    }
    log(`等待账号登录表单或内嵌框架：实际耗时 ${elapsedSeconds(loginFrameWaitStartedAt)} 秒`);
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
      await timed("切换到账号登录", () => accountLogin.click({ force: true }));
      await timed("等待账号密码输入框显示", () =>
        visiblePassword.first().waitFor({ state: "visible", timeout: 5000 }).catch(() => {}));
      log("已切换到账号登录");
    }
  }
  if (await visiblePassword.count()) {
    if (!request.password) {
      throw new Error("未发现已登录的库存系统页面，且当前操作没有可用登录凭据；请先在库存专用 Chrome 中完成登录");
    }
    log("正在登录库存系统");
    const password = visiblePassword.first();
    const username = loginScope.locator('input[name="login_username"]:visible, input[type="text"]:visible').first();
    if (await username.count() !== 1) {
      throw new Error(`登录页可见用户名输入框数量异常：${await username.count()}`);
    }
    await timed("填写账号和密码", async () => {
      await username.click();
      await username.press("Meta+A");
      await username.pressSequentially(request.username, { delay: 30 });
      await password.click();
      await password.press("Meta+A");
      await password.pressSequentially(request.password, { delay: 30 });
    });
    // JDY's login form only re-runs its client-side validation after focus
    // moves back through both fields. Preserve the verified user workflow:
    // password -> username -> password.
    await timed("点击用户名输入框触发登录校验", () => username.click());
    await timed("再次点击密码输入框完成登录校验", () => password.click());
    const agreements = loginScope.locator('#reg_agreement, #agree-protocol');
    if (await agreements.count()) {
      for (let index = 0; index < await agreements.count(); index += 1) {
        const agreement = agreements.nth(index);
        if (!(await agreement.isDisabled().catch(() => true))) {
          if (!(await agreement.isChecked().catch(() => false))) {
            await agreement.evaluate(element => element.click());
          }
        }
      }
      log("已勾选登录协议");
    }
    const login = loginScope.locator('button:visible').filter({ hasText: /^登录$/ }).first()
      .or(loginScope.locator('input[type="button"][value="登录"]:visible').first());
    loginSubmittedAt = performance.now();
    if (await login.count()) {
      await timed("点击登录提交账号密码", () => login.click());
      log("登录信息已提交");
    } else {
      await timed("按回车提交账号密码", () => password.press("Enter"));
      log("已通过回车提交登录信息");
    }
    const securityWaitStartedAt = performance.now();
    const challenged = await Promise.race([
      securityChallenge,
      page.waitForTimeout(1500).then(() => false),
    ]);
    log(`等待登录安全验证响应：实际耗时 ${elapsedSeconds(securityWaitStartedAt)} 秒`);
    if (loginResponseObservedAt !== null) {
      log(`登录提交到网页响应：实际耗时 ${((loginResponseObservedAt - loginSubmittedAt) / 1000).toFixed(2)} 秒`);
    } else {
      log("登录提交后暂未捕获网页响应，继续等待页面结果");
    }
    if (challenged || securityChallengeDetected) {
      if (headless) {
        log("库存系统要求完成安全验证，后台浏览器无法继续");
        throw new Error("库存系统要求完成验证码或安全验证；请先使用可见浏览器完成登录验证，再重试");
      }
      log("请在可见浏览器中完成库存系统验证码或安全验证");
    }
    const loginLimit = loginScope.getByText(/密码登录次数已达最大限制\s*20\s*次/).first();
    if (await loginLimit.count() && await loginLimit.isVisible()) {
      throw new Error("库存系统密码登录已达到20次上限；请使用验证码或扫码登录，或退出其他在线设备后重试");
    }
    const policyAgree = loginScope.locator("#agree-protocol");
    const policyWaitStartedAt = performance.now();
    const policyAppeared = await policyAgree.waitFor({ state: "visible", timeout: 8000 })
      .then(() => true).catch(() => false);
    log(`等待隐私政策弹窗：实际耗时 ${elapsedSeconds(policyWaitStartedAt)} 秒`);
    if (policyAppeared) {
      await policyAgree.click({ force: true, timeout: 5000 });
      log("已确认新版隐私政策弹窗");
      await timedWait(page, 1500, "等待隐私政策确认生效");
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
    if (/\/global\//i.test(page.url())) {
      throw new Error("库存系统登录入口未打开，当前停留在全球站退出页；请重试或使用可见浏览器登录");
    }
    if (isInventoryPage(page)) log("正在复用已有登录状态");
    else throw new Error(`未找到登录表单，也不在已登录工作台：${page.url()}`);
  }

  const englishControl = page.locator('button:visible, a:visible, div:visible, span:visible')
    .filter({ hasText: /^English$/ }).last();
  if (await englishControl.count()) {
    await englishControl.click({ force: true });
    const chinese = page.getByText("简体中文", { exact: true }).last();
    await chinese.waitFor({ state: "visible", timeout: 5000 });
    await chinese.click();
    await timedWait(page, 1500, "等待工作台语言切换生效");
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
  const enterTimeout = UI_STEP_TIMEOUT;
  const enterWaitStartedAt = performance.now();
  const enterReady = await enter.first().waitFor({ state: "visible", timeout: enterTimeout })
    .then(() => true).catch(() => false);
  log(`等待“进入使用”按钮：实际耗时 ${elapsedSeconds(enterWaitStartedAt)} 秒（超时上限 ${enterTimeout / 1000} 秒）`);
  if (loginSubmittedAt !== null) {
    log(`登录提交到“进入使用”可见：实际耗时 ${((performance.now() - loginSubmittedAt) / 1000).toFixed(2)} 秒`);
  }
  if (!enterReady) {
    if (/\/login\/?/i.test(page.url())) {
      if (securityChallengeDetected) {
        throw new Error("库存系统安全验证未完成；请在可见浏览器中完成验证码或扫码登录后重试");
      }
      throw new Error("库存系统登录未成功，请检查账号密码、验证码或登录限制后重试");
    }
    throw new Error("库存系统未显示“进入使用”，页面可能尚未加载完成");
  }
  // Some workbench notices are injected after the initial page-ready check.
  // Recheck immediately before entering so their mask cannot intercept the click.
  const lateModalWaitStartedAt = performance.now();
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const lateModal = page.locator(".kd-modal-container-show:visible").first();
    if (await lateModal.count()) {
      const close = await firstVisible(lateModal.locator(
        '.kd-modal-close, [aria-label*="关闭"], [class*="close"], button',
      ));
      if (close) await close.click({ force: true });
      else await page.keyboard.press("Escape");
      const hidden = await lateModal.waitFor({ state: "hidden", timeout: 5000 })
        .then(() => true).catch(() => false);
      if (!hidden) throw new Error("库存系统通知弹窗遮挡了“进入使用”，且无法自动关闭");
      log("已关闭延迟出现的工作台通知");
      break;
    }
    await page.waitForTimeout(250);
  }
  log(`等待延迟工作台通知：实际耗时 ${elapsedSeconds(lateModalWaitStartedAt)} 秒`);
  const enterCount = await enter.count();
  if (enterCount !== 1) throw new Error(`检测到 ${enterCount} 个“进入使用”按钮，需要人工判断`);
  const pageBeforeEnter = page.url();
  const newProductPage = context.waitForEvent("page", { timeout: 3000 }).catch(() => null);
  await timed("点击“进入使用”", () => enter.click());
  const openedPage = await Promise.race([
    newProductPage,
    page.waitForURL(url => url.href !== pageBeforeEnter, { timeout: 3000 })
      .then(() => null)
      .catch(() => null),
  ]);
  if (openedPage) page = openedPage;
  await timed("等待工作台页面 DOM 加载", () => page.waitForLoadState("domcontentloaded").catch(() => {}));
  if (isInventoryWorkbenchURL(page.url())) {
    await timed("等待工作台跳转到业务页面", () =>
      page.waitForURL(url => !url.href.includes("service.jdy.com/workbench"), {
        timeout: PAGE_NAVIGATION_TIMEOUT,
      }));
  }
  }
  if (attached) page = await ensureInventoryBusinessWorkbench(page);
  await waitForInventoryActionShell(page);
  log(attached ? "已复用库存系统工作台页面" : "已进入库存系统工作台");

  if (request.action === "preflight") {
    log("库存系统连接与登录状态正常");
    process.stdout.write(JSON.stringify({ ok: true, url: page.url() }));
  } else if (request.action === "exportProducts") {
    log("正在打开商品列表");
    const initialGoods = await waitForVisibleLeftNavigationItem(page, "商品");
    log(`已确认商品菜单可见，共 ${initialGoods.length} 个候选控件`);
    await moveAndClick("商品菜单", initialGoods[0]);

    let goodsItems = [];
    let exportItems = [];
    const menuStateStartedAt = performance.now();
    for (let attempt = 0; attempt < 60; attempt += 1) {
      goodsItems = await visibleTextLocatorsAcrossFrames(page, "商品");
      exportItems = await visibleTextLocatorsAcrossFrames(page, "导出");
      if (exportItems.length || goodsItems.length >= 2) break;
      await page.waitForTimeout(250);
    }
    log(`检查商品菜单下一步：实际耗时 ${elapsedSeconds(menuStateStartedAt)} 秒`);
    if (!exportItems.length && goodsItems.length < 2) {
      throw new Error("点击商品菜单后未出现商品列表入口或导出按钮，已停止操作");
    }
    if (!exportItems.length) {
      await moveAndClick("商品列表入口", goodsItems[goodsItems.length - 1]);
      exportItems = await waitForVisibleTextAcrossFrames(page, "导出");
    } else {
      log("商品菜单点击后已直接出现导出按钮，跳过重复点击");
    }
    log("已确认商品列表中的导出按钮出现");
    let download;
    for (let exportAttempt = 1; exportAttempt <= 2; exportAttempt += 1) {
      exportItems = await waitForVisibleTextAcrossFrames(page, "导出");
      if (!(await exportItems[0].isEnabled().catch(() => false))) {
        throw new Error("商品列表中的导出按钮已出现，但当前不可用，已停止操作");
      }
      log(`已确认商品列表中的导出按钮可见且可用（第 ${exportAttempt} 次）`);
      const downloadPromise = page.waitForEvent("download", { timeout: DOWNLOAD_TIMEOUT })
        .then(nextDownload => ({ download: nextDownload }))
        .catch(error => ({ error }));
      let stopNoDataPolling = false;
      const noDataPromise = (async () => {
        for (let attempt = 0; attempt < DOWNLOAD_TIMEOUT / 250; attempt += 1) {
          if (stopNoDataPolling) return { stopped: true };
          const notices = await visiblePatternLocatorsAcrossFrames(page, /没有数据可以导出/);
          if (notices.length) return { noData: true };
          await page.waitForTimeout(250);
        }
        return { timedOut: true };
      })();
      await moveAndClick(`导出按钮（第 ${exportAttempt} 次）`, exportItems[0]);
      const downloadResult = await timed("等待商品资料下载或网页提示", () =>
        Promise.race([downloadPromise, noDataPromise]));
      stopNoDataPolling = true;
      if (downloadResult.download) {
        download = downloadResult.download;
        break;
      }
      if (downloadResult.noData && exportAttempt === 1) {
        log("检测到“没有数据可以导出”，准备关闭提示并重试一次");
        const acknowledgeItems = await waitForVisibleTextAcrossFrames(page, "我知道了");
        await moveAndClick("“没有数据可以导出”提示中的“我知道了”", acknowledgeItems[0]);
        await timed("等待“没有数据可以导出”提示消失", () =>
          waitForVisiblePatternToDisappear(page, /没有数据可以导出/));
        log("提示已消失，重新检查导出按钮");
        continue;
      }
      if (downloadResult.noData) {
        throw new Error("库存系统提示：重试后仍然没有数据可以导出");
      }
      throw new Error("点击导出后 60 秒内没有检测到文件下载事件；请检查导出按钮是否打开了弹窗、新页面或被网站拦截");
    }
    if (!download) throw new Error("商品资料导出未返回下载文件");
    await download.saveAs(request.downloadPath);
    log("商品资料下载文件已保存");
    process.stdout.write(JSON.stringify({ ok: true, downloadPath: request.downloadPath }));
  } else if (request.action === "findOutbound") {
    const listFrame = await openOtherOutboundList(page);
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
  } else if (request.action === "stockBalance") {
    const warehouseItems = await waitForVisibleLeftNavigationItem(page, "仓库");
    await warehouseItems[0].click({ force: true });
    await page.waitForTimeout(400);
    // The current workbench groups inventory reports under a second-level
    // "仓库报表" entry. Older accounts expose the balance report directly,
    // so keep the direct lookup first and expand the group only when needed.
    let openedBalance = await clickVisibleTextAcrossFrames(page, "商品库存余额表");
    if (!openedBalance) {
      const reportGroup = await firstVisible(page.getByText("仓库报表", { exact: true }));
      if (reportGroup) {
        await reportGroup.click({ force: true });
        await page.waitForTimeout(500);
        openedBalance = await clickVisibleTextAcrossFrames(page, "商品库存余额表");
      }
    }
    if (!openedBalance) {
      throw new Error("仓库菜单中找不到商品库存余额表");
    }
    await page.mouse.move(800, 80);
    await page.waitForTimeout(1000);
    const balanceFrame = await waitForVisibleFrame(page, frame =>
      frame.url().includes("goods-balance.jsp")
    );
    if (!balanceFrame) throw new Error("找不到商品库存余额表内嵌页面");
    log("已进入商品库存余额表");

    const productLabel = balanceFrame.getByText(/^商品[：:]?$/, { exact: false }).first();
    const productInput = productLabel.locator("xpath=following::input[1]");
    await productInput.waitFor({ state: "visible", timeout: 15000 });
    if (await productInput.count() !== 1) throw new Error("无法唯一定位商品查询输入框");
    const queryButtonMatches = balanceFrame.getByText("查询", { exact: true });
    const queryButton = await firstVisible(queryButtonMatches);
    if (!queryButton) throw new Error("找不到可见的库存查询按钮");

    const results = [];
    for (let index = 0; index < request.items.length; index += 1) {
      const expected = request.items[index];
      log(`正在查询库存 ${index + 1}/${request.items.length}：${expected.productCode}`);
      await productInput.focus();
      await productInput.press("Meta+A");
      await productInput.fill(expected.productCode);
      await page.waitForTimeout(500);
      const candidate = balanceFrame.locator("tr:visible, li:visible, div:visible")
        .filter({ hasText: new RegExp(`(?:^|\\s)${expected.productCode}(?:\\s|$)`, "i") })
        .filter({ hasText: expected.productName }).last();
      const visibleCandidate = await firstVisible(candidate);
      if (visibleCandidate) {
        const selected = await visibleCandidate.click().then(() => true).catch(() => false);
        if (!selected) await productInput.press("Enter");
      } else {
        await productInput.press("Enter");
      }
      if (!(await queryButton.isVisible().catch(() => false))) {
        throw new Error("库存查询按钮已被页面遮挡或隐藏，请重试");
      }
      await queryButton.click().catch(() => {
        throw new Error("无法点击可见的库存查询按钮，页面可能正在刷新");
      });
      await page.waitForTimeout(900);

      const tables = balanceFrame.locator("table:visible");
      let resultTable = null;
      let headerTexts = [];
      for (let tableIndex = 0; tableIndex < await tables.count(); tableIndex += 1) {
        const table = tables.nth(tableIndex);
        const texts = (await table.locator("thead th, tr th").allTextContents())
          .map(text => text.replace(/\s+/g, ""));
        if (texts.some(text => text.includes("商品编号")) &&
            texts.some(text => text.includes("商品名称"))) {
          resultTable = table;
          headerTexts = texts;
          break;
        }
      }
      if (!resultTable) throw new Error("找不到库存查询结果表");
      const codeColumn = headerTexts.findIndex(text => text.includes("商品编号"));
      const nameColumn = headerTexts.findIndex(text => text.includes("商品名称"));
      const quantityColumn = headerTexts.findIndex(text =>
        /可用库存|库存数量|即时库存|结存数量|基本数量/.test(text)
      );
      if (codeColumn < 0 || nameColumn < 0 || quantityColumn < 0) {
        throw new Error(`库存余额表列结构无法识别：${headerTexts.join(" | ")}`);
      }
      const rows = resultTable.locator("tbody tr:visible");
      if (!(await rows.count())) {
        results.push({
          productCode: expected.productCode,
          productName: expected.productName,
          availableQuantity: 0,
          empty: true,
        });
        continue;
      }
      let matched = null;
      const foundCodes = [];
      for (let rowIndex = 0; rowIndex < await rows.count(); rowIndex += 1) {
        const cells = await rows.nth(rowIndex).locator("td").allTextContents();
        const rowCode = (cells[codeColumn] || "").trim();
        if (rowCode) foundCodes.push(rowCode);
        if (rowCode.toUpperCase() === expected.productCode.toUpperCase()) {
          matched = cells;
          break;
        }
      }
      if (!matched && !foundCodes.length) {
        results.push({
          productCode: expected.productCode,
          productName: expected.productName,
          availableQuantity: 0,
          empty: true,
        });
        continue;
      }
      if (!matched) {
        throw new Error(`查询结果中找不到商品 ${expected.productCode}，实际编号：${foundCodes.slice(0, 5).join("、")}`);
      }
      const quantityText = (matched[quantityColumn] || "").replace(/,/g, "").trim();
      const availableQuantity = Number(quantityText);
      if (!Number.isFinite(availableQuantity)) {
        throw new Error(`商品 ${expected.productCode} 的库存数量无法解析：${quantityText || "空"}`);
      }
      results.push({
        productCode: (matched[codeColumn] || "").trim(),
        productName: (matched[nameColumn] || "").trim(),
        availableQuantity,
        empty: false,
      });
    }
    process.stdout.write(JSON.stringify({ ok: true, results }));
  } else {
    let exactRows = [];
    let existingDocumentNumber = "";
    let formFrame;
    let isUpdate = false;
    log(`正在按备注精确查询历史出库单：${request.orderName}`);
    const listFrame = await openOtherOutboundList(page);
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
          !isOtherOutboundListURL(frame.url())
        );
        if (!formFrame) throw new Error(`无法打开旧出库单 ${existingDocumentNumber}`);
        const edit = formFrame.locator(
          '#edit:visible, #editBills:visible, button:visible, a:visible',
        ).filter({ hasText: /编辑|修改/ }).first();
        if (!(await edit.count()) || await edit.isDisabled().catch(() => false)) {
          throw new Error(`旧出库单 ${existingDocumentNumber} 不可编辑，请人工处理；不会新建重复单`);
        }
        await edit.click();
        formFrame = await waitForOtherOutboundFormFrame(page);
        if (!formFrame) throw new Error(`旧出库单 ${existingDocumentNumber} 编辑表单未加载完成`);
        isUpdate = true;
      }
    }

    if (exactRows.length === 0) {
      if (request.knownDocumentNumber) {
        throw new Error(
          `本机已有出库单 ${request.knownDocumentNumber}，但库存系统查不到备注“${request.orderName}”对应原单；已停止，不新建重复出库单`
        );
      }
      log("未找到同备注旧单，正在打开新增其他出库单");
      await openOtherOutboundMenuItem(page);
      await page.mouse.move(800, 80);
      log("已打开新增其他出库单页面并收起菜单");
      formFrame = await waitForOtherOutboundFormFrame(page);
    }
    if (exactRows.length !== 1 || request.changed) {
      if (!formFrame) throw new Error("找不到其他出库单内嵌表单，页面结构可能已变化");
    await formFrame.waitForLoadState("domcontentloaded").catch(() => {});
    await page.waitForTimeout(1500);
    log("已进入其他出库单表单");

    const production = formFrame.getByText("生产领料", { exact: true });
    const businessInput = formFrame.getByPlaceholder(/业务类型/);
    let businessEditor = await firstVisible(businessInput);
    if (!businessEditor) {
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
      businessEditor = input;
    }
    const currentBusinessType = (await businessEditor.inputValue().catch(() => "")).trim();
    if (currentBusinessType !== "生产领料") {
      await businessEditor.click();
      const visibleProduction = await firstVisible(production);
      if (!visibleProduction) {
        throw new Error("业务类型下拉菜单中找不到“生产领料”选项");
      }
      await visibleProduction.click();
    } else {
      log("业务类型已经是生产领料");
    }
    const verifiedBusinessType = (await businessEditor.inputValue().catch(() => "")).trim();
    if (verifiedBusinessType !== "生产领料") {
      throw new Error(`业务类型设置未生效：页面回读为“${verifiedBusinessType || "空"}”`);
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
      let materialRows = await outboundMaterialRows(formFrame);
      while (materialRows.length > request.items.length) {
        const last = materialRows[materialRows.length - 1].row;
        await last.click();
        const remove = formFrame.locator(
          '.ui-icon-minus:visible, .icon-delete:visible, .delete-row:visible, [title*="删除行"]:visible',
        ).first();
        if (!(await remove.count())) {
          throw new Error(`旧出库单 ${existingDocumentNumber} 有多余明细，但找不到删除行按钮，已停止保存`);
        }
        await remove.click({ force: true });
        await page.waitForTimeout(200);
        materialRows = await outboundMaterialRows(formFrame);
      }
      if ((await outboundMaterialRows(formFrame)).length !== request.items.length) {
        throw new Error(`旧出库单 ${existingDocumentNumber} 明细行数未能完整替换，已停止保存`);
      }
      log(`旧出库单 ${existingDocumentNumber} 的全部明细已替换`);
    }

    await assertOutboundFormMatchesRequest(formFrame, request.items, quantityColumnId);
    log("保存前已核对备注、商品明细、数量和行数");

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
  keepBrowserOpenOnExit = false;
  let pageInfo = "";
  try {
    const body = (await page.locator("body").innerText()).replace(/\s+/g, " ").slice(0, 300);
    pageInfo = `；当前页面：${page.url()}；页面提示：${body}`;
  } catch {}
  process.stderr.write(`库存系统自动操作失败：${error?.message || String(error)}${pageInfo}\n`);
  process.exitCode = 1;
} finally {
  // This Browser came from connectOverCDP. Playwright's close() disconnects
  // its client connection for this case; it does not quit the user's Chrome.
  if (remoteBrowser) await remoteBrowser.close();
  else if (context && (!keepBrowserOpenOnExit || temporaryProfile)) await context.close();
  if (typeof temporaryProfile === "string" && temporaryProfile) {
    await fs.promises.rm(temporaryProfile, { recursive: true, force: true }).catch(() => {});
  }
}
