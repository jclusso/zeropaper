// Takes the README and website screenshot, in light and dark, from a running
// demo library (see script/demo/reset). Saves PNGs to docs/screenshots.
//
//   node script/demo/screenshots.js [BASE_URL]
//
// BASE_URL defaults to http://localhost:3999.
const { chromium } = require("playwright")
const path = require("node:path")
const fs = require("node:fs")
const { spawnSync } = require("node:child_process")

const BASE = process.argv[2] || "http://localhost:3999"
const OUT = path.join(__dirname, "../../docs/screenshots")
const VIEWPORT = { width: 1440, height: 900 }

// Finds the link whose text includes the given words, and returns its path.
// With last, the last such link: the original of a document that has a
// newer copy with the same title.
async function hrefFor(page, listPath, text, { last = false } = {}) {
  await page.goto(BASE + listPath)
  const links = page.locator("a", { hasText: text })
  const link = last ? links.last() : links.first()
  return new URL(await link.getAttribute("href"), BASE).pathname
}

async function settle(page) {
  await page.waitForLoadState("networkidle")
  await page.evaluate(() => document.fonts.ready)
  await page.waitForTimeout(400)
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true })
  const browser = await chromium.launch()

  for (const theme of ["light", "dark"]) {
    const context = await browser.newContext({ viewport: VIEWPORT, deviceScaleFactor: 2, colorScheme: theme })
    const page = await context.newPage()
    await page.goto(BASE + "/session/new")
    await page.fill("input[name=email_address]", "sam@example.com")
    await page.fill("input[name=password]", "zeropaper-demo")
    await page.click("input[type=submit]")
    await page.waitForURL((url) => !url.pathname.startsWith("/session"))

    await page.goto(BASE + await hrefFor(page, "/", "Electric bill September 2026", { last: true }))
    await page.getByRole("button", { name: "Side by side" }).click()
    await page.locator("canvas").first().waitFor({ timeout: 10000 }).catch(() => {})
    await settle(page)

    const file = path.join(OUT, `document${theme === "dark" ? "-dark" : ""}.png`)
    await page.screenshot({ path: file })
    // Shrinks the file when pngquant is installed; skipped otherwise.
    spawnSync("pngquant", ["--force", "--skip-if-larger", "--ext", ".png", "--quality", "85-98", file])
    console.log("saved", path.relative(process.cwd(), file))
    await context.close()
  }
  await browser.close()
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
