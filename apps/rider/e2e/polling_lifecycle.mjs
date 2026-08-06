/**
 * THE TEST THAT WOULD HAVE CAUGHT IT.
 *
 * Every unit and widget test in this repo passed while polling was dead in
 * live use, and they could not have done otherwise: a widget test decides for
 * itself what `AppLifecycleState.inactive` means. Only a real engine can tell
 * you that a browser window losing focus IS `inactive` — Flutter's web engine
 * binds `window.addEventListener('blur')` straight to it.
 *
 * So this runs the actual `flutter build web` output in Chromium, against the
 * actual API, logs in through the actual OTP flow, and then measures requests
 * on the wire while doing NOTHING. The load-bearing assertion is the middle
 * one: dispatch a plain window `blur` — exactly what the browser fires when you
 * click the driver app — and the polls must keep coming.
 *
 * Before the fix this measured 4 requests / 0 / 5. It is the regression guard
 * for `appIsVisible` in packages/shared/lib/polling/polling_scope.dart.
 *
 * Usage (see docs/RUN_LOCAL.md):
 *   API_LOG=/path/to/api.log WEB_URL=http://127.0.0.1:8088 \
 *   API_URL=http://127.0.0.1:3000 node apps/rider/e2e/polling_lifecycle.mjs
 */
import { chromium } from 'playwright';
import { execSync } from 'node:child_process';

const WEB = process.env.WEB_URL || 'http://127.0.0.1:8088';
const API = process.env.API_URL || 'http://127.0.0.1:3000';
const API_LOG = process.env.API_LOG;
if (!API_LOG) throw new Error('API_LOG must point at the API stdout log (the dev OTP goes there)');

// A phone of its own, so a rerun is never throttled by a previous run's OTPs.
const SUFFIX = String(process.pid).slice(-4).padStart(4, '0');
const PHONE_LOCAL = `77012${SUFFIX}0`;
const PHONE_E164 = `+964${PHONE_LOCAL}`;

const fail = (msg) => {
  console.error(`\nFAIL: ${msg}`);
  process.exitCode = 1;
};

const api = async (path, { method = 'GET', token, body } = {}) => {
  const res = await fetch(API + path, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status} ${text.slice(0, 300)}`);
  try { return JSON.parse(text); } catch { return text; }
};

/** The dev fallback prints the code to the API log when WhatsApp is unconfigured. */
const otpFor = (phone) => {
  const log = execSync(`tail -500 ${API_LOG}`).toString();
  const m = [...log.matchAll(new RegExp(`OTP for \\${phone} is (\\d{4,8})`, 'g'))];
  if (!m.length) throw new Error(`no OTP for ${phone} in ${API_LOG}`);
  return m[m.length - 1][1];
};

// Give the rider a completed profile up front, so the browser only has to walk
// phone → OTP and lands straight on the home shell.
await api('/auth/request-otp', { method: 'POST', body: { phone: PHONE_E164 } });
await new Promise((r) => setTimeout(r, 500));
const seeded = await api('/auth/verify-otp', {
  method: 'POST',
  body: { phone: PHONE_E164, code: otpFor(PHONE_E164) },
});
await api('/auth/me', {
  method: 'PATCH',
  token: seeded.accessToken ?? seeded.token,
  body: { name: 'راكب الاختبار', gender: 'MALE' },
});

const browser = await chromium.launch({
  headless: true,
  // SwiftShader: CI runners have no GPU and Chromium now refuses the silent
  // software fallback, which leaves CanvasKit rendering nothing at all.
  args: ['--no-proxy-server', '--enable-unsafe-swiftshader'],
});
const ctx = await browser.newContext({ viewport: { width: 420, height: 860 } });
const page = await ctx.newPage();

const t0 = Date.now();
const hits = [];
page.on('request', (r) => {
  if (r.url().startsWith(API)) {
    hits.push({ ms: Date.now() - t0, path: r.url().slice(API.length).split('?')[0] });
  }
});

/** Flutter web keeps its accessibility DOM behind shadow roots. */
const deep = (sel) =>
  page.evaluate((s) => {
    const found = [];
    const scan = (root) => {
      root.querySelectorAll(s).forEach((e) => {
        const r = e.getBoundingClientRect();
        found.push({ x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2), h: Math.round(r.height) });
      });
      root.querySelectorAll('*').forEach((e) => { if (e.shadowRoot) scan(e.shadowRoot); });
    };
    scan(document);
    return found;
  }, sel);

const fields = async (label) => {
  const deadline = Date.now() + 40000;
  while (Date.now() < deadline) {
    const ph = page.locator('flt-semantics-placeholder');
    // A trusted click on the placeholder is what turns the a11y DOM on, which
    // is the only way to address Flutter's canvas from Playwright.
    if (await ph.count()) await ph.dispatchEvent('click').catch(() => {});
    await page.waitForTimeout(2000);
    const found = (await deep('flt-semantics input')).filter((i) => i.h > 10 && i.h < 120);
    if (found.length) return found;
  }
  throw new Error(`no input field for step: ${label}`);
};

await page.goto(WEB, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(12000);

const phone = await fields('phone');
await page.mouse.click(phone[0].x, phone[0].y);
await page.waitForTimeout(600);
await page.keyboard.type(PHONE_LOCAL, { delay: 60 });
await page.waitForTimeout(600);
const send = await deep('flt-semantics[role=button]');
await page.mouse.click(send[send.length - 1].x, send[send.length - 1].y);
await page.waitForTimeout(3000);

const boxes = await fields('otp');
// OtpInput forces Directionality.ltr, so box 0 is the LEFTMOST even on this RTL
// page, and it advances focus per digit — type one at a time and let it settle.
const first = boxes.slice().sort((a, b) => a.x - b.x)[0];
await page.mouse.click(first.x, first.y);
await page.waitForTimeout(600);
for (const ch of otpFor(PHONE_E164)) {
  await page.keyboard.press(ch);
  await page.waitForTimeout(450);
}
await page.waitForTimeout(8000);

if (!hits.some((h) => h.path === '/auth/verify-otp')) {
  await page.screenshot({ path: 'e2e-login-failed.png' });
  fail('could not log in through the UI (screenshot: e2e-login-failed.png)');
  await browser.close();
  process.exit(1);
}

const count = (from, to = Infinity) =>
  hits.filter((h) => h.ms >= from && h.ms < to && h.path === '/notifications').length;

// ── A: focused and idle ───────────────────────────────────────────────────
const a = Date.now() - t0;
await page.waitForTimeout(70000);

// ── B: window blurred — still fully visible, just not focused ─────────────
await page.evaluate(() => window.dispatchEvent(new FocusEvent('blur')));
const b = Date.now() - t0;
await page.waitForTimeout(70000);

// ── C: focus returns ──────────────────────────────────────────────────────
await page.evaluate(() => window.dispatchEvent(new FocusEvent('focus')));
const c = Date.now() - t0;
await page.waitForTimeout(70000);
const end = Date.now() - t0;

const focused = count(a, b);
const blurred = count(b, c);
const refocused = count(c, end);

console.log(`GET /notifications  focused=${focused}  blurred=${blurred}  refocused=${refocused}`);
console.log(hits.map((h) => `  ${(h.ms / 1000).toFixed(1)}s ${h.path}`).join('\n'));

// 70s at a 30s beat is 2 polls; allow 1 to absorb scheduling jitter on a
// loaded CI runner. Zero is the failure this test exists for.
if (focused < 1) fail(`polling never started (focused=${focused})`);
if (blurred < 1) {
  fail(
    'a window blur stopped every poll — AppLifecycleState.inactive is being ' +
      'treated as backgrounded. See appIsVisible in packages/shared/lib/polling/polling_scope.dart',
  );
}
if (refocused < 1) fail(`polling did not resume after refocus (refocused=${refocused})`);

if (!process.exitCode) console.log('\nPASS: polling survives losing window focus.');
await browser.close();
