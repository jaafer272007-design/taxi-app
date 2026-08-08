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
import {
  API, freshPhone, launch, loginThroughUi, requireApiLog, seedRider,
} from './harness.mjs';

requireApiLog();

const phone = freshPhone('2');
await seedRider(phone);

const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 420, height: 860 } });
const page = await ctx.newPage();

const t0 = Date.now();
const hits = [];
page.on('request', (r) => {
  if (r.url().startsWith(API)) {
    hits.push({ ms: Date.now() - t0, path: r.url().slice(API.length).split('?')[0] });
  }
});

const fail = (msg) => {
  console.error(`\nFAIL: ${msg}`);
  process.exitCode = 1;
};

await loginThroughUi(page, phone);

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
