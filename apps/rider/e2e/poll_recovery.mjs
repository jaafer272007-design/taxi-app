/**
 * A HUNG POLL MUST NOT SILENCE A SCREEN FOR EVER.
 *
 * `Poller._inFlight` is a latch: until an `onPoll` future completes, every
 * later tick returns at the guard. So one await that never finishes takes that
 * screen's refresh out permanently — and `isTicking` goes on reporting true,
 * which is a silent failure that reports itself as healthy.
 *
 * On THIS platform the HTTP call itself is not the risk: `dio_web_adapter` sets
 * `xhr.timeout = connectTimeout + receiveTimeout`, and a stalled endpoint was
 * measured aborting at 15s and recovering. (That is a web-only guarantee — on
 * Android `receiveTimeout` is an inter-chunk idle timer, which is why
 * `kRequestDeadline` exists. This spec cannot reach that platform.)
 *
 * What it CAN reach is the await Dio's budget does not cover on any platform,
 * because Dio applies timeouts in its adapter — after the whole interceptor
 * chain: `tokenStore.read()` in ApiClient.onRequest, which goes to the platform
 * keystore.
 *
 * This reproduces exactly that, in the real production build, with no test hook
 * in the app: on web `flutter_secure_storage` decrypts the stored JWT with
 * `crypto.subtle.decrypt`, so replacing that one browser API with a promise
 * that never resolves hangs the token read the same way a wedged platform
 * channel would.
 *
 * The observable is the number of token-read ATTEMPTS, not requests on the
 * wire: once the read is bounded the request is rejected before the adapter, so
 * nothing reaches the network — but a live poller keeps trying, once per
 * interval, and a latched one tries exactly once, for ever.
 *
 *   before the bound:  1 attempt,  then silence for ever
 *   after  the bound:  one attempt per poll interval, and full recovery
 */
import {
  API, freshPhone, launch, loginThroughUi, requireApiLog, seedRider,
} from './harness.mjs';

requireApiLog();

const phone = freshPhone('4');
await seedRider(phone);

const browser = await launch();
const ctx = await browser.newContext({ viewport: { width: 420, height: 860 } });
const page = await ctx.newPage();

const t0 = Date.now();
const ms = () => Date.now() - t0;
const wire = [];
page.on('request', (r) => {
  if (r.url().startsWith(API)) {
    wire.push({ ms: ms(), path: r.url().slice(API.length).split('?')[0] });
  }
});

const fail = (m) => { console.error(`\nFAIL: ${m}`); process.exitCode = 1; };
const notifs = (from, to = Infinity) =>
  wire.filter((h) => h.ms >= from && h.ms < to && h.path === '/notifications').length;

await loginThroughUi(page, phone);
if (!wire.some((h) => h.path === '/auth/verify-otp')) {
  await page.screenshot({ path: 'e2e-recovery-login-failed.png' });
  fail('could not log in through the UI (screenshot: e2e-recovery-login-failed.png)');
  await browser.close();
  process.exit(1);
}

// ── A: healthy ────────────────────────────────────────────────────────────
const a = ms();
await page.waitForTimeout(70000);
const healthy = notifs(a);
console.log(`A healthy      : ${healthy} /notifications`);

// ── B: hang the token read, the one await outside Dio's budget ───────────
const b = ms();
await page.evaluate(() => {
  window.__decryptAttempts = 0;
  window.__realDecrypt = window.crypto.subtle.decrypt.bind(window.crypto.subtle);
  window.crypto.subtle.decrypt = (...args) => {
    window.__decryptAttempts++;
    return new Promise(() => {}); // never resolves — a wedged keystore
  };
});
await page.waitForTimeout(100000);
const attempts = await page.evaluate(() => window.__decryptAttempts);
console.log(`B token read hung: ${attempts} read attempts over 100s, ${notifs(b)} reached the wire`);

// ── C: unhang it — the app must come back on its own ─────────────────────
await page.evaluate(() => { window.crypto.subtle.decrypt = window.__realDecrypt; });
const c = ms();
await page.waitForTimeout(80000);
const recovered = notifs(c);
console.log(`C recovered    : ${recovered} /notifications`);

console.log('\nwire:');
for (const h of wire) console.log(`  ${(h.ms / 1000).toFixed(1).padStart(7)}s ${h.path}`);

if (healthy < 1) fail(`polling never started (A=${healthy})`);

// THE ASSERTION. A latched poller reads the token once and never again. A
// bounded one keeps trying — 100s at a 30s beat is 3, allow 2 for CI jitter.
if (attempts < 2) {
  fail(
    `the poller latched: only ${attempts} token-read attempt(s) in 100s. One ` +
      'hung read has silenced the scope. See kTokenReadTimeout in ' +
      'packages/shared/lib/net/api_client.dart and kPollWatchdog in ' +
      'packages/shared/lib/polling/poller.dart',
  );
}
if (recovered < 1) fail(`polling did not resume once the read worked again (C=${recovered})`);

if (!process.exitCode) {
  console.log('\nPASS: a hung token read is bounded, the poller keeps trying, and it recovers.');
}
await browser.close();
