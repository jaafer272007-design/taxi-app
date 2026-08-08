/**
 * Print docs/APP_TOUR.html to docs/APP_TOUR.pdf.
 *
 * Uses the Chromium that the browser E2E specs already install, so there is no
 * extra toolchain: `cd apps/rider/e2e && npm install` first if it is missing.
 *
 *   python3 docs/build_app_tour.py && node docs/print_app_tour.mjs
 */
import { chromium } from '../apps/rider/e2e/node_modules/playwright/index.mjs';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const src = path.join(root, 'docs', 'APP_TOUR.html');
const out = path.join(root, 'docs', 'APP_TOUR.pdf');

const browser = await chromium.launch({
  args: ['--no-proxy-server', '--enable-unsafe-swiftshader'],
});
const page = await browser.newPage();

// file:// so the embedded data: URIs and fonts resolve with no network at all.
await page.goto(pathToFileURL(src).href, { waitUntil: 'load' });
// The screenshots are lazy-loaded; force every one to decode before printing or
// the PDF comes out with holes where images had not painted yet.
await page.evaluate(async () => {
  document.querySelectorAll('img').forEach((i) => { i.loading = 'eager'; });
  await Promise.all(
    [...document.images].map((i) => (i.complete ? null : i.decode().catch(() => {}))),
  );
  await document.fonts.ready;
});
await page.waitForTimeout(1500);

await page.pdf({
  path: out,
  format: 'A4',
  printBackground: true,
  preferCSSPageSize: true,
});

await browser.close();
console.log(`wrote ${path.relative(root, out)}`);
