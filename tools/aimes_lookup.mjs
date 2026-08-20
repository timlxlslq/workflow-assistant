import { chromium } from "playwright";
import fs from "node:fs";

const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const request = JSON.parse(Buffer.concat(chunks).toString("utf8"));
const processStartedAt = performance.now();
const timings = [];
const safePageURL = () => {
  try {
    if (!page) return "";
    const current = new URL(page.url());
    return `${current.origin}${current.pathname}`;
  } catch {
    return "";
  }
};
const log = (message, details = {}) => process.stderr.write(`${JSON.stringify({
  event: "progress",
  message: `[+${((performance.now() - processStartedAt) / 1000).toFixed(2)}s] ${message}`,
  page_url: safePageURL(),
  ...details,
})}\n`);
const recordStage = (stage, label, startedAt) => {
  const durationSeconds = Number(((performance.now() - startedAt) / 1000).toFixed(2));
  timings.push({ stage, label, duration_seconds: durationSeconds });
  log(`${label}完成`, { stage, stage_label: label, duration_seconds: durationSeconds });
};
let browser;
let page;
try {
  const configuredBrowser = process.env.TRAVELER_BROWSER_EXECUTABLE || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  const browserOptions = {
    headless: true,
    args: ["--password-store=basic", "--use-mock-keychain", "--no-first-run", "--no-default-browser-check"],
  };
  if (fs.existsSync(configuredBrowser)) browserOptions.executablePath = configuredBrowser;
  const browserStartedAt = performance.now();
  log("启动 AIMES 浏览器", { stage: "browser_launch", stage_label: "启动 AIMES 浏览器" });
  browser = await chromium.launch({
    ...browserOptions,
  });
  recordStage("browser_launch", "启动 AIMES 浏览器", browserStartedAt);
  page = await browser.newPage();
  const login = "https://passport.3vjia.com/login?pageTitle=%E9%A6%96%E9%A1%B5&appId=aimes-web&extKey=&redirect_uri=https%3A%2F%2Faimes.3vjia.com%2Fdashboard%2Fworkbench";
  const loginStartedAt = performance.now();
  log("打开 AIMES 登录网页（网址参数已省略）");
  await page.goto(login, { waitUntil: "domcontentloaded", timeout: 30000 });
  if (!page.url().includes("/dashboard/")) {
    log("在 AIMES 登录页填写账号和密码（内容已省略）");
    await page.locator('input[type="text"]').fill(request.username);
    await page.locator('input[type="password"]').fill(request.password);
    log("提交 AIMES 登录");
    await page.locator('input[type="password"]').press("Enter");
  }
  await page.waitForURL(url => url.hostname === "aimes.3vjia.com" && url.pathname.startsWith("/dashboard/"), { timeout: 30000 });
  recordStage("login", "登录 AIMES", loginStartedAt);
  const pageLoadStartedAt = performance.now();
  log("读取 AIMES 工作台页面");
  log("点击 AIMES 菜单 OMS");
  await page.getByText("OMS", { exact: true }).click();
  log("点击 AIMES 菜单工厂订单");
  await page.getByText("工厂订单", { exact: true }).click();
  const input = page.getByPlaceholder("请输入工厂单号");
  await input.waitFor({ state: "visible", timeout: 30000 });
  await page.locator("tbody tr").first().waitFor({ state: "visible", timeout: 30000 });
  recordStage("page_load", "加载 AIMES 工厂订单页面", pageLoadStartedAt);
  const output = {};
  if (request.recentLimit) {
    const requestedLimit = Math.max(1, Number(request.recentLimit));
    const metadataRows = [];
    const seenFactories = new Set();
    let pageNumber = 0;

    // Keep the original AIMES behavior: read only the current page of 50
    // factory orders. Select 50 explicitly in case the browser remembers a
    // previous page-size choice.
    const pageSizeControl = page.locator([
      '.el-pagination .el-select',
      '.ant-pagination-options .ant-select',
      '.ant-pagination-options',
    ].join(', ')).first();
    const currentPageSize = page.getByText(/(?:50|100)\s*条\s*\/\s*页/).last();
    if (await currentPageSize.count() > 0 && (await currentPageSize.innerText()).replace(/\s/g, '') !== '50条/页') {
      await currentPageSize.click();
      const fiftyOption = page.getByText(/50\s*条\s*\/\s*页/).last();
      if (await fiftyOption.count() === 0 && await pageSizeControl.count() > 0) {
        await pageSizeControl.click();
      }
      const option = page.locator([
        '.el-select-dropdown__item',
        '.ant-select-item-option',
        '[role="option"]',
      ].join(', ')).filter({ hasText: /50\s*条\s*\/\s*页/ }).last();
      if (await option.count() > 0) await option.click();
      else if (await fiftyOption.count() > 0) await fiftyOption.click();
      await page.waitForTimeout(500);
    }
    const tableReadStartedAt = performance.now();
    log("读取 AIMES 工厂订单表格", { stage: "table_read", stage_label: "读取 AIMES 工厂订单表格" });
    while (metadataRows.length < requestedLimit && pageNumber < 100) {
      const headerRows = page.locator("thead tr");
      let headers = [];
      for (let index = 0; index < await headerRows.count(); index += 1) {
        const candidate = (await headerRows.nth(index).locator("th").allTextContents()).map(value => value.trim());
        if (candidate.length > headers.length) headers = candidate;
      }
      const findColumn = aliases => headers.findIndex(header => aliases.some(alias => header === alias || header.includes(alias)));
      const factoryColumn = findColumn(["工厂单号"]);
      const factoryNameColumn = findColumn(["工厂单名称"]);
      const salesOrderColumn = findColumn(["销售单名称"]);
      const splitTimeColumn = findColumn(["拆单时间"]);
      if (request.includeOrderMetadata && [factoryColumn, factoryNameColumn, salesOrderColumn, splitTimeColumn].some(index => index < 0)) {
        throw new Error(`AIMES 工厂订单表缺少必要列；当前表头：${headers.join(" | ")}`);
      }

      const rows = page.locator("tbody tr");
      const rowCount = await rows.count();
      for (let index = 0; index < rowCount && metadataRows.length < requestedLimit; index += 1) {
        const values = (await rows.nth(index).locator("td").allTextContents()).map(value => value.trim());
        const fallbackFactoryColumn = values.findIndex(value => /^F\d+$/i.test(value));
        const resolvedFactoryColumn = factoryColumn >= 0 ? factoryColumn : fallbackFactoryColumn;
        const factoryOrder = values[resolvedFactoryColumn]?.toUpperCase() || "";
        if (!/^F\d+$/i.test(factoryOrder) || seenFactories.has(factoryOrder)) continue;
        const factoryName = values[factoryNameColumn >= 0 ? factoryNameColumn : resolvedFactoryColumn + 1]?.trim() || "";
        seenFactories.add(factoryOrder);
        if (request.includeOrderMetadata) {
          metadataRows.push({
            factory_order: factoryOrder,
            factory_name: factoryName,
            sales_order_name: values[salesOrderColumn]?.trim() || "",
            split_time: values[splitTimeColumn]?.trim() || "",
          });
        } else if (factoryName) {
          output[factoryOrder] = factoryName;
          metadataRows.push({ factory_order: factoryOrder });
        }
      }

      if (metadataRows.length >= requestedLimit) break;
      const nextButton = page.locator([
        '.el-pagination .btn-next',
        '.ant-pagination-next button',
        'button[aria-label*="next" i]',
        'button[aria-label*="下一"]',
        'button[title*="下一"]',
      ].join(", ")).first();
      if (await nextButton.count() === 0) break;
      const disabled = await nextButton.isDisabled().catch(() => false)
        || (await nextButton.getAttribute("aria-disabled")) === "true"
        || (await nextButton.getAttribute("class") || "").toLowerCase().includes("disabled");
      if (disabled) break;
      const firstFactoryBefore = metadataRows.at(-1)?.factory_order || "";
      await nextButton.click();
      await page.waitForTimeout(500);
      if (firstFactoryBefore) {
        await page.waitForFunction(
          previous => !document.querySelector("tbody")?.innerText.includes(previous),
          firstFactoryBefore,
          { timeout: 10000 },
        ).catch(() => {});
      }
      pageNumber += 1;
    }
    recordStage("table_read", "读取 AIMES 工厂订单表格", tableReadStartedAt);
    output.recent_rows = metadataRows;
    if (!request.verifyFactoryOrders) {
      process.stdout.write(JSON.stringify(request.includeOrderMetadata ? { rows: metadataRows, timings } : { ...output, timings }));
      await browser.close();
      process.exit(0);
    }
  }
  if (request.verifyFactoryOrders) {
    const rows = [];
    const missing = [];
    const verificationStartedAt = performance.now();
    const recentFactoryOrders = new Set(
      (output.recent_rows || []).map(row => String(row.factory_order || "").toUpperCase()),
    );
    const verificationOrders = request.recentLimit
      ? request.factoryOrders.filter(factoryOrder => !recentFactoryOrders.has(String(factoryOrder).toUpperCase()))
      : request.factoryOrders;
    for (const factoryOrder of verificationOrders) {
      log("在 AIMES 工厂订单页精确核验工厂单存在性（内容已省略）");
      const beforeQuery = await page.locator("tbody").innerText().catch(() => "");
      await input.fill(factoryOrder);
      await page.getByRole("button", { name: "查询", exact: true }).click();
      await page.waitForFunction(
        ({ factoryOrder: expectedFactoryOrder, before }) => {
          const body = document.querySelector("tbody");
          if (!body) return false;
          const loading = document.querySelector(
            ".el-loading-mask, .el-loading-spinner, .ant-spin-spinning, [aria-busy='true']",
          );
          const text = body.innerText || "";
          return !loading && (text !== before || text.includes(expectedFactoryOrder));
        },
        { factoryOrder, before: beforeQuery },
        { timeout: 5000 },
      ).catch(() => page.waitForTimeout(150));
      const matchingRows = page.locator("tbody tr").filter({ hasText: factoryOrder });
      if (await matchingRows.count() === 0) {
        missing.push(factoryOrder.toUpperCase());
        continue;
      }
      const row = matchingRows.first();
      const values = (await row.locator("td").allTextContents()).map(value => value.trim());
      const index = values.findIndex(value => value === factoryOrder);
      if (index < 0 || !values[index + 1]) {
        missing.push(factoryOrder.toUpperCase());
        continue;
      }
      rows.push({
        factory_order: factoryOrder.toUpperCase(),
        factory_name: values[index + 1],
        sales_order_name: values.find((value, column) => column !== index && /^\s*(PP\d{4}(?:-\d+)?|CS\d{3})\s*$/i.test(value)) || "",
        split_time: "",
      });
    }
    recordStage("factory_order_verify", "精确核验工厂单存在性", verificationStartedAt);
    const payload = request.recentLimit
      ? { rows: output.recent_rows || [], verify_rows: rows, missing, timings }
      : { rows, missing, timings };
    process.stdout.write(JSON.stringify(payload));
    await browser.close();
    process.exit(0);
  }
  for (const factoryOrder of request.factoryOrders) {
    log("在 AIMES 工厂订单页填写查询条件（内容已省略）");
    await input.fill(factoryOrder);
    log("点击 AIMES 查询按钮");
    await page.getByRole("button", { name: "查询", exact: true }).click();
    const row = page.locator("tbody tr").filter({ hasText: factoryOrder });
    await row.waitFor({ state: "visible", timeout: 20000 });
    const values = await row.locator("td").allTextContents();
    const index = values.findIndex(value => value.trim() === factoryOrder);
    if (index < 0 || !values[index + 1]?.trim()) throw new Error(`找不到工厂单名称：${factoryOrder}`);
    output[factoryOrder] = values[index + 1].trim();
  }
  process.stdout.write(JSON.stringify(output));
} catch (error) {
  process.stderr.write(`AIMES 自动查询失败：${error?.message || String(error)}${page ? `；当前页面：${page.url()}` : ""}\n`);
  process.exitCode = 1;
} finally {
  if (browser) await browser.close();
}
