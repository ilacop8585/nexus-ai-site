// Guest-only NEXUS Word Italian-first language regression gate.
// Read-only against production: no login, no chat sending, no task creation, no charges.
// Prerequisites: Node.js, puppeteer, Chrome/Chromium. Run: node tests/language-smoke.cjs
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const puppeteer = require('puppeteer');

const URL_TO_TEST = process.env.NEXUS_TEST_URL || 'https://nexusword.it/';
const chromeCandidates = [
  process.env.NEXUS_CHROME_BIN,
  process.platform === 'win32' ? 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe' : null,
  process.platform === 'darwin' ? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' : null,
  process.platform === 'linux' ? '/usr/bin/google-chrome' : null,
  process.platform === 'linux' ? '/usr/bin/chromium' : null
].filter(Boolean);
const chromePath = chromeCandidates.find(path => fs.existsSync(path));

function inspect(page) {
  return page.evaluate(() => {
    const select = document.querySelector('#nexusLanguage');
    const bounds = select?.getBoundingClientRect();
    return {
      htmlLang: document.documentElement.lang,
      value: select?.value,
      options: select ? [...select.options].map(option => option.value) : [],
      storage: localStorage.getItem('nexus_ui_language_v1'),
      heading: document.querySelector('#betaReleaseStrip strong')?.textContent?.trim(),
      projectNav: document.querySelector('#projectsBtn span')?.textContent?.trim(),
      href: location.href,
      width: innerWidth,
      scrollWidth: document.documentElement.scrollWidth,
      box: bounds && { left: bounds.left, right: bounds.right, top: bounds.top, width: bounds.width, height: bounds.height }
    };
  });
}

(async () => {
  const browser = await puppeteer.launch({
    headless: true,
    ...(chromePath ? { executablePath: chromePath } : {}),
    args: ['--no-sandbox', '--disable-dev-shm-usage']
  });
  let checked = 0;
  const failures = [];
  try {
    const page = await browser.newPage(); // isolated temporary Chrome profile
    page.on('pageerror', error => failures.push('pageerror: ' + error.message));
    page.on('requestfailed', request => failures.push('requestfailed: ' + request.url() + ' ' + request.failure()?.errorText));
    await page.setViewport({ width: 1280, height: 720 });
    await page.goto(URL_TO_TEST, { waitUntil: 'networkidle2', timeout: 35000 });
    await page.waitForSelector('#nexusLanguage', { timeout: 12000 });

    let state = await inspect(page);
    assert.equal(state.htmlLang, 'it', 'first visit must be Italian');
    assert.equal(state.value, 'it');
    assert.deepEqual(state.options, ['it', 'en']);
    assert.equal(state.storage, null);
    assert.match(state.heading, /IN SVILUPPO/);
    assert.ok(state.box?.width > 0 && state.box.right <= state.width, 'selector must fit desktop');
    assert.ok(state.scrollWidth <= state.width, 'no desktop overflow');
    console.log('PASS: fresh guest defaults to Italian, with visible IT/EN selector'); checked++;

    await page.select('#nexusLanguage', 'en');
    state = await inspect(page);
    assert.equal(state.htmlLang, 'en');
    assert.equal(state.storage, 'en');
    assert.equal(state.projectNav, 'Projects');
    assert.match(state.heading, /ACTIVE DEVELOPMENT/);
    assert.match(state.href, /[?&]lang=en(?:&|$)/);
    console.log('PASS: switch to English updates UI, URL and storage'); checked++;

    await page.reload({ waitUntil: 'networkidle2' });
    state = await inspect(page);
    assert.equal(state.htmlLang, 'en');
    assert.equal(state.value, 'en');
    console.log('PASS: English persists through full reload'); checked++;

    await page.select('#nexusLanguage', 'it');
    await page.reload({ waitUntil: 'networkidle2' });
    state = await inspect(page);
    assert.equal(state.htmlLang, 'it');
    assert.equal(state.value, 'it');
    assert.equal(state.storage, 'it');
    assert.equal(state.projectNav, 'Progetti');
    assert.match(state.heading, /IN SVILUPPO/);
    console.log('PASS: returning to Italian persists'); checked++;

    await page.setViewport({ width: 390, height: 844, isMobile: true, hasTouch: true });
    state = await inspect(page);
    assert.equal(state.htmlLang, 'it');
    assert.ok(state.box?.width > 0 && state.box.left >= 0 && state.box.right <= state.width, 'selector must fit 390px mobile');
    assert.ok(state.scrollWidth <= state.width, 'no 390px horizontal overflow');
    console.log('PASS: 390px mobile selector visible without horizontal overflow'); checked++;

    assert.deepEqual(failures, [], 'page JS errors / failed network requests');
    console.log('PASS: zero page errors and failed requests'); checked++;
    console.log('NEXUS_LANGUAGE_GATE_PASS checks=' + checked);
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error('NEXUS_LANGUAGE_GATE_FAIL', error.stack || error);
  process.exitCode = 1;
});
