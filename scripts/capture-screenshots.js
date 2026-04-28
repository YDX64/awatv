#!/usr/bin/env node
/**
 * AWAtv — production screenshot capture.
 *
 * Walks the live site at https://awatv.pages.dev across the eight key user
 * journey screens and writes 16 PNGs (8 pages * 2 form factors: mobile +
 * desktop) into store/screenshots/.
 *
 * Run via scripts/capture-screenshots.sh which installs Playwright as a
 * transient (--no-save) dependency.
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const SITE = process.env.AWATV_URL || 'https://awatv.pages.dev';
const OUT_DIR = path.resolve(__dirname, '..', 'store', 'screenshots');

// Screens captured against the live production site. AWAtv guards
// /premium, /settings, and /remote behind playlist/onboarding state, so
// hitting those URLs in a brand-new browser context honestly redirects
// to /onboarding — that IS the production behaviour for a first-run user
// and is what we capture. The brief explicitly forbids faking onboarding
// completion or seeding playlists.
const PAGES = [
  { slug: '01-onboarding',          path: '/#/onboarding' },
  { slug: '02-add-playlist-m3u',    path: '/#/playlists/add' },
  { slug: '03-add-playlist-xtream', path: '/#/playlists/add', tab: 'Xtream' },
  { slug: '04-login',               path: '/#/login' },
  { slug: '05-premium',             path: '/#/premium' },
  { slug: '06-settings',            path: '/#/settings' },
  { slug: '07-remote-hub',          path: '/#/remote' },
  { slug: '08-remote-receive',      path: '/#/remote/receive' },
];

const FORMS = [
  {
    name: 'mobile',
    viewport: { width: 393, height: 852 },
    deviceScaleFactor: 2,
    isMobile: true,
    hasTouch: true,
    userAgent:
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
  },
  {
    name: 'desktop',
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 2,
    isMobile: false,
    hasTouch: false,
  },
];

async function ensureFlutterAccessibility(page) {
  // Flutter Web ships with a hidden accessibility placeholder; clicking it
  // makes the semantics tree reachable for Playwright queries (button names
  // by role, etc.). It is a no-op visually.
  try {
    await page.evaluate(() => {
      const ph = document.querySelector('flt-semantics-placeholder');
      if (ph) (ph).click();
    });
  } catch (_) {
    /* best-effort */
  }
}

async function waitForRender(page) {
  // Flutter Web boots on a canvas; networkidle is reached well before the UI
  // is visible. Wait until at least the rendering host element exists, then
  // give the splash a moment to fade.
  try {
    await page.waitForSelector('flt-glass-pane, flutter-view, flt-scene-host', {
      timeout: 12000,
    });
  } catch (_) {
    /* continue — splash may have failed but we still want a screenshot */
  }
  await page.waitForTimeout(2200);
}

async function tryClickByText(page, text) {
  const candidates = [
    page.getByRole('tab', { name: text }),
    page.getByRole('button', { name: text }),
    page.getByText(text, { exact: false }),
  ];
  for (const c of candidates) {
    try {
      await c.first().click({ timeout: 2500 });
      return true;
    } catch (_) {
      /* try next */
    }
  }
  return false;
}

async function main() {
  if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });

  const browser = await chromium.launch({ headless: true });
  const summary = [];

  for (const form of FORMS) {
    const ctx = await browser.newContext({
      viewport: form.viewport,
      deviceScaleFactor: form.deviceScaleFactor,
      isMobile: form.isMobile,
      hasTouch: form.hasTouch,
      userAgent: form.userAgent,
      colorScheme: 'dark',
      locale: 'en-US',
    });

    for (const spec of PAGES) {
      const url = SITE + spec.path;
      const file = path.join(OUT_DIR, `${spec.slug}-${form.name}.png`);
      const started = Date.now();
      const page = await ctx.newPage();
      let ok = false;
      let err = null;
      try {
        await page.goto(url, { waitUntil: 'networkidle', timeout: 45000 });
        await ensureFlutterAccessibility(page);
        await waitForRender(page);
        if (spec.tab) {
          await tryClickByText(page, spec.tab);
          await page.waitForTimeout(900);
        }
        await page.screenshot({ path: file, fullPage: false });
        ok = fs.existsSync(file);
      } catch (e) {
        err = e && e.message ? e.message : String(e);
      } finally {
        await page.close().catch(() => {});
      }
      const ms = Date.now() - started;
      const size = ok ? fs.statSync(file).size : 0;
      summary.push({ form: form.name, slug: spec.slug, ok, ms, size, err });
      const status = ok ? 'OK ' : 'FAIL';
      console.log(
        `[${status}] ${form.name.padEnd(7)} ${spec.slug.padEnd(28)} ${ms}ms  ${(size / 1024).toFixed(1)}KB  ${err ? '— ' + err : ''}`,
      );
    }
    await ctx.close();
  }
  await browser.close();

  const failures = summary.filter((s) => !s.ok);
  console.log('---');
  console.log(`Captured ${summary.length - failures.length}/${summary.length} screenshots`);
  if (failures.length) {
    console.log('Failures:');
    for (const f of failures) console.log(`  ${f.form}/${f.slug}: ${f.err}`);
    process.exit(1);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
