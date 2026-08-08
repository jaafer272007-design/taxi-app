/**
 * THE TEST THAT WOULD HAVE CAUGHT IT: رحلاتي went stale.
 *
 * Reported from live use: a rider books a seat, the driver's phone shows the
 * in-app notification (so app-wide polling was alive and well), and the رحلاتي
 * card behind it goes on showing the old seat count until the driver taps into
 * the trip. A driver glancing at that list to decide whether to wait for
 * another passenger is reading a number that may be minutes old.
 *
 * The cause was not subtle once looked for — that screen had no `PollingScope`
 * at all, and its `initState` loads only `if (!c.hasLoaded)`, so it fetched
 * once per app launch. **No widget test could have found that**: a widget test
 * asserts what the controller does when something calls it, and nothing was
 * calling it. The only way to see it is to have two real apps on one real
 * backend and touch neither of them.
 *
 * So this drives the actual `flutter build web` of BOTH apps in one browser:
 * the driver logs in and sits on رحلاتي, a rider books a seat over the API, and
 * the assertion is that the number on the driver's card changes **with no
 * interaction at all**. It fails if the poller is removed — verified by
 * removing it.
 *
 * Usage (see docs/RUN_LOCAL.md):
 *   API_LOG=/tmp/api.log DRIVER_URL=http://127.0.0.1:8089 \
 *   API_URL=http://127.0.0.1:3000 node apps/driver/e2e/my_trips_refresh.mjs
 */
import { chromium } from 'playwright';
import { execSync } from 'node:child_process';

const DRIVER_WEB = process.env.DRIVER_URL || 'http://127.0.0.1:8089';
const API = process.env.API_URL || 'http://127.0.0.1:3000';
const API_LOG = process.env.API_LOG;
if (!API_LOG) throw new Error('API_LOG must point at the API stdout log (the dev OTP goes there)');

const call = async (path, { method = 'GET', token, body } = {}) => {
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

const otpFor = (phone) => {
  const log = execSync(`tail -800 ${API_LOG}`).toString();
  const m = [...log.matchAll(new RegExp(`OTP for \\${phone} is (\\d{4,8})`, 'g'))];
  if (!m.length) throw new Error(`no OTP for ${phone} in ${API_LOG}`);
  return m[m.length - 1][1];
};

const stamp = String(process.pid).slice(-4).padStart(4, '0');
const driverPhone = { local: `775${stamp}000`, e164: `+964775${stamp}000` };
const riderPhone = { local: `776${stamp}000`, e164: `+964776${stamp}000` };
for (const p of [driverPhone, riderPhone]) {
  if (p.local.length !== 10) throw new Error(`bad phone: ${p.local}`);
}

const login = async (phone, name) => {
  await call('/auth/request-otp', { method: 'POST', body: { phone: phone.e164 } });
  await new Promise((r) => setTimeout(r, 500));
  const out = await call('/auth/verify-otp', {
    method: 'POST',
    body: { phone: phone.e164, code: otpFor(phone.e164) },
  });
  const token = out.accessToken ?? out.token;
  await call('/auth/me', { method: 'PATCH', token, body: { name, gender: 'MALE' } });
  return token;
};

// ── Seed: an APPROVED driver with a posted trip, and a rider ready to book ──
console.log('seeding…');
const driverToken = await login(driverPhone, 'سائق الاختبار');
const riderToken = await login(riderPhone, 'راكب الاختبار');

await call('/driver/profile', { method: 'POST', token: driverToken });
await call('/driver/vehicle', {
  method: 'POST', token: driverToken,
  body: { make: 'Toyota', model: 'Corolla', plate: `MT-${stamp}`, color: 'أبيض', seats: 4 },
});
// Approval is an admin action. Done through the real admin API rather than a
// direct UPDATE so this spec needs no database client on the runner and no
// knowledge of the schema — only the credentials CI already sets.
const adminLogin = await call('/admin/auth/login', {
  method: 'POST',
  body: {
    username: process.env.SUPER_ADMIN_USERNAME || 'e2e-superadmin',
    password: process.env.SUPER_ADMIN_PASSWORD || 'e2e-password-1234',
  },
});
const adminToken = adminLogin.accessToken ?? adminLogin.token;
const pending = await call('/admin/drivers?status=PENDING', { token: adminToken });
const mine = pending.find((d) => d.user?.phone === driverPhone.e164 || d.phone === driverPhone.e164);
if (!mine) throw new Error(`driver ${driverPhone.e164} not found among PENDING`);
await call(`/admin/drivers/${mine.id}/approve`, { method: 'POST', token: adminToken });

const corridors = await call('/corridors', { token: driverToken });
const corridor = corridors.find((c) => c.originCity === 'Najaf') ?? corridors[0];
const trip = await call('/trips', {
  method: 'POST', token: driverToken,
  body: {
    corridorId: corridor.id,
    departureTime: new Date(Date.now() + 3 * 3600_000).toISOString(),
    seatsTotal: 4,
    // The corridor's own suggestion, never a hardcoded number: every corridor
    // carries its own min/max band and the seed sets real ones, so a literal
    // here fails with TRIP_PRICE_OUT_OF_RANGE the moment the seed changes.
    pricePerSeat: corridor.suggestedPricePerSeat,
  },
});
console.log(`trip ${trip.id} posted with 4 seats free`);

// ── Drive the driver app ────────────────────────────────────────────────────
const browser = await chromium.launch({
  headless: true,
  args: ['--no-proxy-server', '--enable-unsafe-swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 420, height: 860 } });

const fail = (m) => { console.error(`\nFAIL: ${m}`); process.exitCode = 1; };

/** Flutter web keeps its accessibility DOM behind shadow roots. */
const deep = (sel) =>
  page.evaluate((s) => {
    const found = [];
    const scan = (root) => {
      root.querySelectorAll(s).forEach((e) => {
        const r = e.getBoundingClientRect();
        found.push({
          x: Math.round(r.x + r.width / 2),
          y: Math.round(r.y + r.height / 2),
          h: Math.round(r.height),
          label: (e.getAttribute('aria-label') || e.textContent || '').trim(),
        });
      });
      root.querySelectorAll('*').forEach((e) => { if (e.shadowRoot) scan(e.shadowRoot); });
    };
    scan(document);
    return found;
  }, sel);

const inputs = async (label) => {
  const deadline = Date.now() + 40000;
  while (Date.now() < deadline) {
    const ph = page.locator('flt-semantics-placeholder');
    if (await ph.count()) await ph.dispatchEvent('click').catch(() => {});
    await page.waitForTimeout(2000);
    const found = (await deep('flt-semantics input')).filter((i) => i.h > 10 && i.h < 120);
    if (found.length) return found;
  }
  throw new Error(`no input field for step: ${label}`);
};

await page.goto(DRIVER_WEB, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(12000);

const phoneField = await inputs('phone');
await page.mouse.click(phoneField[0].x, phoneField[0].y);
await page.waitForTimeout(600);
await page.keyboard.type(driverPhone.local, { delay: 60 });
await page.waitForTimeout(600);
const send = await deep('flt-semantics[role=button]');
await page.mouse.click(send[send.length - 1].x, send[send.length - 1].y);
await page.waitForTimeout(3000);

const boxes = await inputs('otp');
// OtpInput forces LTR internally, so box 0 is the LEFTMOST even on an RTL page.
const first = boxes.slice().sort((a, b) => a.x - b.x)[0];
await page.mouse.click(first.x, first.y);
await page.waitForTimeout(600);
for (const ch of otpFor(driverPhone.e164)) {
  await page.keyboard.press(ch);
  await page.waitForTimeout(450);
}
await page.waitForTimeout(9000);

/** Every bit of text Flutter has published to the semantics tree. */
const screenText = async () =>
  (await deep('flt-semantics')).map((n) => n.label).filter(Boolean).join(' | ');

// Open رحلاتي and STOP TOUCHING THE APP from here on.
const navTo = async (label) => {
  const nodes = await deep('flt-semantics[role=button]');
  const target = nodes.find((n) => n.label.includes(label));
  if (!target) throw new Error(`nav item «${label}» not found`);
  await page.mouse.click(target.x, target.y);
  await page.waitForTimeout(4000);
};
await navTo('رحلاتي');

// Assert on SeatGlyphs' exact Arabic label, not on a loose digit match.
//
// Arabic has a DUAL: `SeatGlyphs.label(2)` is «مقعدان متاحان», which carries no
// digit at all, and the label always ends «من ٤» with the total — so a naive
// "sees ٢, no longer sees ٤" can never come true and the test fails whatever
// the app does. Hence one seat booked, leaving THREE, which is a real numeral.
// (CLAUDE.md: fixture a count of 3 when a screen shows one.)
const FOUR_FREE = '٤ مقاعد متاحة';
const THREE_FREE = '٣ مقاعد متاحة';

const before = await screenText();
console.log(`رحلاتي on open: ${before.includes(FOUR_FREE) ? `«${FOUR_FREE}»` : 'seat label NOT FOUND'}`);
if (!before.includes(FOUR_FREE)) {
  await page.screenshot({ path: 'e2e-driver-mytrips.png' });
  fail(`could not read «${FOUR_FREE}» on رحلاتي (screenshot: e2e-driver-mytrips.png)`);
  await browser.close();
  process.exit(1);
}

// ── A rider books 1 seat. The driver does NOTHING. ─────────────────────────
console.log('\nrider books 1 seat… the driver app is not touched again.');
await call('/bookings', {
  method: 'POST', token: riderToken,
  body: {
    tripId: trip.id,
    pickup: { lat: 32.0, lng: 44.3, label: 'البيت' },
    dropoff: { lat: 32.6, lng: 44.0, label: 'الجامعة' },
    seatCount: 1,
  },
});

// 20s beat; allow three of them for a loaded CI runner.
let updated = false;
for (let i = 0; i < 12; i++) {
  await page.waitForTimeout(5000);
  if ((await screenText()).includes(THREE_FREE)) {
    updated = true;
    console.log(`  updated after ~${(i + 1) * 5}s`);
    break;
  }
}

const after = await screenText();
console.log(
  `رحلاتي after the booking: ${after.includes(THREE_FREE) ? `«${THREE_FREE}»` : `still «${FOUR_FREE}»`}`,
);

if (!updated) {
  await page.screenshot({ path: 'e2e-driver-mytrips-stale.png' });
  fail(
    'رحلاتي never refreshed: the seat count is still what it was when the tab ' +
      'was opened. A driver reading it would be deciding on a stale number. See ' +
      'the PollingScope in apps/driver/lib/trip/my_trips_screen.dart',
  );
}

if (!process.exitCode) {
  console.log('\nPASS: رحلاتي updated on its own, with no interaction.');
}
await browser.close();
