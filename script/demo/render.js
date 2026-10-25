// Renders every .html file in a folder to a PDF of the same name, at the page
// size the file names in <meta name="page-size" content="WIDTH HEIGHT">.
//
//   node script/demo/render.js IN_DIR OUT_DIR
const { chromium } = require("playwright")
const fs = require("node:fs")
const path = require("node:path")
const { pathToFileURL } = require("node:url")

async function main() {
  const [inDir, outDir] = process.argv.slice(2)
  if (!inDir || !outDir) {
    console.error("usage: node script/demo/render.js IN_DIR OUT_DIR")
    process.exit(1)
  }

  const browser = await chromium.launch()
  const page = await browser.newPage()
  for (const file of fs.readdirSync(inDir).filter((name) => name.endsWith(".html")).sort()) {
    const source = path.join(inDir, file)
    const size = fs.readFileSync(source, "utf8").match(/name="page-size" content="([^"]+)"/)?.[1] || "8.5in 11in"
    const [width, height] = size.split(" ")
    await page.goto(pathToFileURL(source).href)
    await page.pdf({ path: path.join(outDir, path.basename(file, ".html") + ".pdf"), width, height, printBackground: true })
  }
  await browser.close()
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
