import { test, expect, type Page } from "@playwright/test";

import { NORMAL_ADMIN_STATE } from "./fixtures";

/**
 * The locked numeral rule, checked where it actually breaks: on screen.
 *
 * ## Why this measures pixels instead of reading text
 *
 * `innerText` returns text in LOGICAL order — the order the characters appear
 * in the source. Bidi reordering happens at layout time, so a string assertion
 * cannot see it at all: the source `· ٤ مقاعد` reads as perfectly fine text
 * while the browser paints the `·` on the far side of the digit.
 *
 * That is not hypothetical. It shipped here. In an RTL run the separator
 * resolves to the RIGHT of an Arabic-Indic digit, which is precisely where a
 * `٠` sits in a two-digit number (digits run left-to-right inside RTL text).
 * Cairo draws `·` and `٠` as the same small mid-height dot, so
 * `E2E-1001 · ٤ مقاعد` and `E2E-1001 ٤٠ مقاعد` — four seats and forty — were
 * separated by a 3px space against a 7px digit.
 *
 * So this walks every character the browser painted, sorts by x to recover
 * VISUAL order, and fails if a dot-like glyph was painted within
 * {@link MIN_GAP_PX} of an Arabic-Indic digit.
 */
test.use({ storageState: NORMAL_ADMIN_STATE });

/**
 * Separators that can be mistaken for `٠`. Deliberately NOT the Arabic
 * thousands separator `٬` or decimal separator `٫` — those are *part* of the
 * number and are supposed to touch the digits.
 */
const DOT_LIKE = ["·", "•", ".", "∙", "‧", "⋅"];

/**
 * Half a digit's advance width at the panel's 14px Cairo (a digit is ~7px).
 * The broken version measured 3px; the fix separates by the flex gap, 24px.
 * Anything under this reads as one numeral run.
 */
const MIN_GAP_PX = 6;

interface Painted {
  ch: string;
  left: number;
  right: number;
  top: number;
}

/** Every character the page painted, with the rect it was painted into. */
async function paintedChars(page: Page): Promise<Painted[]> {
  return page.evaluate(() => {
    // The whole page, not just <main>: the sidebar carries the pending-drivers
    // badge, which is a bare Arabic-Indic numeral sitting next to a label.
    const root = document.body;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const out: Painted[] = [];
    let node: Node | null;
    while ((node = walker.nextNode())) {
      const data = (node as Text).data;
      for (let i = 0; i < data.length; i++) {
        if (data[i] === " " || data[i] === "\n") continue;
        const range = document.createRange();
        range.setStart(node, i);
        range.setEnd(node, i + 1);
        const r = range.getBoundingClientRect();
        if (r.width === 0 && r.height === 0) continue;
        out.push({ ch: data[i], left: r.left, right: r.right, top: Math.round(r.top) });
      }
    }
    return out;
  });
}

/**
 * Dot-like glyphs painted too close to an Arabic-Indic digit, in either
 * direction, on the same visual line.
 */
function findFusions(chars: Painted[]): string[] {
  const isDigit = (c: Painted) => /[٠-٩]/.test(c.ch);
  const isDot = (c: Painted) => DOT_LIKE.includes(c.ch);

  const byLine = new Map<number, Painted[]>();
  for (const c of chars) {
    if (!byLine.has(c.top)) byLine.set(c.top, []);
    byLine.get(c.top)!.push(c);
  }

  const problems: string[] = [];
  for (const line of byLine.values()) {
    line.sort((a, b) => a.left - b.left);
    for (let i = 0; i < line.length - 1; i++) {
      const a = line[i];
      const b = line[i + 1];
      if (!((isDot(a) && isDigit(b)) || (isDigit(a) && isDot(b)))) continue;
      const gap = b.left - a.right;
      if (gap < MIN_GAP_PX) {
        const context = line
          .slice(Math.max(0, i - 6), i + 7)
          .map((c) => c.ch)
          .join("");
        problems.push(
          `"${a.ch}" and "${b.ch}" painted ${gap.toFixed(1)}px apart ` +
            `(visual context, left→right: "${context}")`,
        );
      }
    }
  }
  return problems;
}

for (const path of ["/drivers", "/dashboard", "/corridors"]) {
  test(`${path}: no dot-like separator is painted against an Arabic-Indic digit`, async ({
    page,
  }) => {
    await page.goto(path);
    // Wait for real content: an empty page would make this vacuously green.
    await expect(page.locator("main")).toContainText(/[٠-٩]/);

    const problems = findFusions(await paintedChars(page));
    expect(
      problems,
      `${path} renders a separator fused to a numeral — it will be read as an extra ٠.\n` +
        `Join with a strong Arabic word/letter (بـ / لـ / الساعة) or split into ` +
        `separate elements so layout does the separating.\n  ` +
        problems.join("\n  "),
    ).toEqual([]);
  });
}

test("the drivers page states the seat count as four, not forty", async ({ page }) => {
  // Pins the VALUE, and the fixture that makes the test above meaningful: a
  // count of 3+ is required, because formatSeats returns the Arabic dual
  // («مقعدان») at 2 and a bare word at 1 — neither carries a digit for a
  // separator to fuse with, so a fixture of 1 or 2 renders clean either way.
  //
  // It does NOT catch the fusion, and cannot: this assertion passed against the
  // broken code, because getByText matches LOGICAL order and the bug is purely
  // in how the characters were laid out. That is exactly why the pixel-level
  // test above exists rather than a string check.
  await page.goto("/drivers");
  await expect(page.getByText("٤ مقاعد").first()).toBeVisible();
  await expect(page.getByText("٤٠ مقاعد")).toHaveCount(0);
});
