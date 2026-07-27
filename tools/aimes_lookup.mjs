import { chromium } from "playwright";

const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const request = JSON.parse(Buffer.concat(chunks).toString("utf8"));
let browser;
let page;
try {
  process.stderr.write("AIMES阶段：启动隔离浏览器\n");
  browser = await chromium.launch({
    executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    headless: true,
    args: [
      "--password-store=basic",
      "--use-mock-keychain",
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-background-networking",
    ],
  });
  process.stderr.write("AIMES阶段：浏览器已启动，打开登录页\n");
  page = await browser.newPage();
  const passportUrl = "https://passport.3vjia.com/login?pageTitle=%E9%A6%96%E9%A1%B5&appId=aimes-web&extKey=&redirect_uri=https%3A%2F%2Faimes.3vjia.com%2Fdashboard%2Fworkbench";
  await page.goto(passportUrl, { waitUntil: "domcontentloaded", timeout: 30000 });
  process.stderr.write(`AIMES阶段：首页已打开 ${page.url()}\n`);
  const passwordInput = page.locator('input[type="password"]');
  if (!page.url().includes("/dashboard/")) {
    await passwordInput.waitFor({ state: "visible", timeout: 15000 });
    process.stderr.write("AIMES阶段：登录表单已出现\n");
    const account = page.locator('input[type="text"]');
    if (await account.count() !== 1) throw new Error("AIMES 登录页用户名输入框结构发生变化");
    if (await passwordInput.count() !== 1) throw new Error("AIMES 登录页密码输入框结构发生变化");
    await account.fill(request.username);
    await passwordInput.fill(request.password);
    await passwordInput.press("Enter");
    process.stderr.write("AIMES阶段：登录信息已提交\n");
  }
  await Promise.race([
    page.waitForURL(
      url => url.hostname === "aimes.3vjia.com" && url.pathname.startsWith("/dashboard/"),
      { timeout: 20000 },
    ),
    page.getByText("账号或密码错误", { exact: true }).waitFor({ state: "visible", timeout: 8000 })
      .then(() => { throw new Error("AIMES 账号或密码错误"); })
      .catch(error => {
        if (String(error?.message || error).includes("AIMES 账号或密码错误")) throw error;
        return new Promise(() => {});
      }),
  ]);
  process.stderr.write("AIMES阶段：登录成功\n");
  const omsMenu = page.getByText("OMS", { exact: true });
  await omsMenu.waitFor({ state: "visible", timeout: 10000 });
  await omsMenu.click();
  const factoryOrderMenu = page.getByText("工厂订单", { exact: true });
  await factoryOrderMenu.waitFor({ state: "visible", timeout: 10000 });
  await factoryOrderMenu.click();
  const input = page.getByPlaceholder("请输入工厂单号");
  await input.waitFor({ state: "visible", timeout: 15000 });
  process.stderr.write("AIMES阶段：工厂订单页面已打开\n");
  const output = {};
  for (const factoryOrder of request.factoryOrders) {
    await input.fill(factoryOrder);
    await page.getByRole("button", { name: "查询", exact: true }).click();
    const row = page.locator("tbody tr").filter({ hasText: factoryOrder });
    await row.waitFor({ state: "visible", timeout: 20000 });
    const cells = row.locator("td");
    const values = await cells.allTextContents();
    const orderIndex = values.findIndex((value) => value.trim() === factoryOrder);
    if (orderIndex < 0 || !values[orderIndex + 1]?.trim()) {
      throw new Error(`找不到工厂单名称：${factoryOrder}`);
    }
    output[factoryOrder] = values[orderIndex + 1].trim();
  }
  process.stdout.write(JSON.stringify(output));
} catch (error) {
  let pageInfo = "";
  if (page) {
    try {
      const text = (await page.locator("body").innerText()).replace(/\s+/g, " ").slice(0, 500);
      pageInfo = `；当前页面：${page.url()}；页面提示：${text}`;
    } catch {}
  }
  process.stderr.write(`AIMES 自动查询失败：${error?.message || String(error)}${pageInfo}\n`);
  process.exitCode = 1;
} finally {
  if (browser) await browser.close();
}
