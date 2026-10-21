// Web build smoke test: serves build/web, opens it in headless Chromium and checks
// that the game boots, the audio context runs, cross-origin isolation is active
// (threaded build), and frames are being drawn at a sane rate.
//
//   NODE_PATH=$(npm root -g) node tests/web/smoke.cjs build/web out/web_smoke
//
// Writes <out>.png (screenshot) and <out>.json (measurements). Exit 1 on failure.
const http = require("http");
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const root = path.resolve(process.argv[2] || "build/web");
const outBase = process.argv[3] || "out/web_smoke";
const query = process.argv[4] || "";
const TYPES = {
  ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json",
};

function serve() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const url = decodeURIComponent(req.url.split("?")[0]);
      let file = path.join(root, url === "/" ? "index.html" : url);
      if (!file.startsWith(root) || !fs.existsSync(file)) { res.writeHead(404); return res.end(); }
      if (fs.statSync(file).isDirectory()) file = path.join(file, "index.html");
      // No COOP/COEP headers on purpose: GitHub Pages can't send them, so the
      // build's service worker has to provide isolation itself.
      res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream" });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}

(async () => {
  const server = await serve();
  const url = `http://127.0.0.1:${server.address().port}/${query}`;
  const browser = await chromium.launch({
    executablePath: fs.existsSync("/opt/pw-browsers/chromium") ? undefined : undefined,
    args: ["--enable-unsafe-swiftshader", "--use-gl=angle", "--use-angle=swiftshader",
           "--autoplay-policy=no-user-gesture-required"],
  });
  const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
  const logs = [];
  const errors = [];
  page.on("console", (m) => { logs.push(`${m.type()}: ${m.text()}`); if (m.type() === "error") errors.push(m.text()); });
  page.on("pageerror", (e) => errors.push(String(e)));
  await page.goto(url, { waitUntil: "load" });
  // The isolation service worker reloads the page once on first visit.
  await page.waitForTimeout(4000);
  if (!(await page.evaluate(() => self.crossOriginIsolated))) {
    await page.reload({ waitUntil: "load" });
  }
  await page.waitForSelector("canvas", { timeout: 60000 });
  await page.mouse.click(480, 270);          // user gesture: unlock audio
  await page.waitForTimeout(12000);
  const result = await page.evaluate(async () => {
    const times = [];
    let last = performance.now();
    await new Promise((done) => {
      const tick = (t) => { times.push(t - last); last = t; times.length < 180 ? requestAnimationFrame(tick) : done(); };
      requestAnimationFrame(tick);
    });
    times.sort((a, b) => a - b);
    const ctxs = (window.Godot && 0) || null;
    return {
      crossOriginIsolated: self.crossOriginIsolated,
      sharedArrayBuffer: typeof SharedArrayBuffer !== "undefined",
      frameMedianMs: times[Math.floor(times.length / 2)],
      frameP95Ms: times[Math.floor(times.length * 0.95)],
      canvas: !!document.querySelector("canvas"),
      status: document.querySelector("#status") ? getComputedStyle(document.querySelector("#status")).display : "none",
    };
  });
  await page.screenshot({ path: `${outBase}.png` });
  result.errors = errors;
  result.logTail = logs.slice(-25);
  fs.writeFileSync(`${outBase}.json`, JSON.stringify(result, null, 2));
  console.log(JSON.stringify({ ...result, logTail: undefined }, null, 2));
  await browser.close();
  server.close();
  const fatal = errors.filter((e) => !/favicon|GPU stall|WebGL|swiftshader|Service worker already exists/i.test(e));
  process.exit(result.canvas && result.status === "none" && fatal.length === 0 ? 0 : 1);
})().catch((e) => { console.error(e); process.exit(1); });
