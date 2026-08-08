/**
 * Shared plumbing for the rider browser E2Es: seed a rider, boot the real
 * `flutter build web` output in Chromium, and walk the real OTP login.
 *
 * Extracted so the two specs cannot drift: driving Flutter's canvas from
 * Playwright is fiddly enough (semantics tree, shadow roots, an RTL page whose
 * OTP boxes are laid out LTR) that a second hand-rolled copy would rot.
 */
import { chromium } from 'playwright';
import { execSync } from 'node:child_process';

export const WEB = process.env.WEB_URL || 'http://127.0.0.1:8088';
export const API = process.env.API_URL || 'http://127.0.0.1:3000';
const API_LOG = process.env.API_LOG;

export const requireApiLog = () => {
  if (!API_LOG) {
    throw new Error('API_LOG must point at the API stdout log (the dev OTP goes there)');
  }
  return API_LOG;
};

export const apiCall = async (path, { method = 'GET', token, body } = {}) => {
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
export const otpFor = (phone) => {
  const log = execSync(`tail -500 ${requireApiLog()}`).toString();
  const m = [...log.matchAll(new RegExp(`OTP for \\${phone} is (\\d{4,8})`, 'g'))];
  if (!m.length) throw new Error(`no OTP for ${phone} in ${requireApiLog()}`);
  return m[m.length - 1][1];
};

/** A phone of this run's own, so a rerun is never throttled by an earlier one. */
export const freshPhone = (band) => {
  // Iraqi mobiles are 10 local digits (77x + 7 more); `band` keeps concurrent
  // specs off each other's numbers.
  const suffix = String(process.pid).slice(-4).padStart(4, '0');
  const local = `77${band}${suffix}000`;
  if (local.length !== 10) throw new Error(`bad phone: ${local}`);
  return { local, e164: `+964${local}` };
};

/** Give the rider a completed profile up front, so the browser only walks phone → OTP. */
export const seedRider = async (phone) => {
  await apiCall('/auth/request-otp', { method: 'POST', body: { phone: phone.e164 } });
  await new Promise((r) => setTimeout(r, 500));
  const out = await apiCall('/auth/verify-otp', {
    method: 'POST',
    body: { phone: phone.e164, code: otpFor(phone.e164) },
  });
  await apiCall('/auth/me', {
    method: 'PATCH',
    token: out.accessToken ?? out.token,
    body: { name: 'راكب الاختبار', gender: 'MALE' },
  });
};

export const launch = async () =>
  chromium.launch({
    headless: true,
    // SwiftShader: CI runners have no GPU and Chromium now refuses the silent
    // software fallback, which leaves CanvasKit rendering nothing at all.
    args: ['--no-proxy-server', '--enable-unsafe-swiftshader'],
  });

/** Flutter web keeps its accessibility DOM behind shadow roots. */
export const deep = (page, sel) =>
  page.evaluate((s) => {
    const found = [];
    const scan = (root) => {
      root.querySelectorAll(s).forEach((e) => {
        const r = e.getBoundingClientRect();
        found.push({
          x: Math.round(r.x + r.width / 2),
          y: Math.round(r.y + r.height / 2),
          h: Math.round(r.height),
        });
      });
      root.querySelectorAll('*').forEach((e) => { if (e.shadowRoot) scan(e.shadowRoot); });
    };
    scan(document);
    return found;
  }, sel);

const fields = async (page, label) => {
  const deadline = Date.now() + 40000;
  while (Date.now() < deadline) {
    const ph = page.locator('flt-semantics-placeholder');
    // A trusted click on the placeholder is what turns the a11y DOM on, which
    // is the only way to address Flutter's canvas from Playwright.
    if (await ph.count()) await ph.dispatchEvent('click').catch(() => {});
    await page.waitForTimeout(2000);
    const found = (await deep(page, 'flt-semantics input')).filter((i) => i.h > 10 && i.h < 120);
    if (found.length) return found;
  }
  throw new Error(`no input field for step: ${label}`);
};

/** Walk the real onboarding: phone → OTP → home shell. */
export const loginThroughUi = async (page, phone) => {
  await page.goto(WEB, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(12000);

  const phoneField = await fields(page, 'phone');
  await page.mouse.click(phoneField[0].x, phoneField[0].y);
  await page.waitForTimeout(600);
  await page.keyboard.type(phone.local, { delay: 60 });
  await page.waitForTimeout(600);
  const send = await deep(page, 'flt-semantics[role=button]');
  await page.mouse.click(send[send.length - 1].x, send[send.length - 1].y);
  await page.waitForTimeout(3000);

  const boxes = await fields(page, 'otp');
  // OtpInput wraps its Row in Directionality.ltr, so box 0 is the LEFTMOST even
  // on this RTL page, and it advances focus per digit — type one at a time and
  // let the DOM input swap settle, or every keystroke lands in the same box.
  const first = boxes.slice().sort((a, b) => a.x - b.x)[0];
  await page.mouse.click(first.x, first.y);
  await page.waitForTimeout(600);
  for (const ch of otpFor(phone.e164)) {
    await page.keyboard.press(ch);
    await page.waitForTimeout(450);
  }
  await page.waitForTimeout(8000);
};
