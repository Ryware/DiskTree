const puppeteer = require('puppeteer-core');
const fs = require('fs');

const CHROME = process.env.CHROME_PATH || '/usr/bin/google-chrome-stable';
const WORKER = process.env.WORKER_ID || '0';
const LOG = `/tmp/headroom_browser_${WORKER}.log`;
const READ_LOG = `/tmp/headroom_read_${WORKER}.log`;

const log = (msg) => {
  const line = `${new Date().toISOString()} [w${WORKER}] ${msg}`;
  console.log(line);
  try { fs.appendFileSync(LOG, line + '\n'); } catch {}
};

const readLog = (msg) => {
  try { fs.appendFileSync(READ_LOG, `${new Date().toISOString()} ${msg}\n`); } catch {}
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const SECTIONS = ['#top', '#features', '#duplicates', '#menubar', '#safety', '#faq'];

async function readLineByLine(page) {
  // Extract visible text blocks and "read" them with pauses (line-by-line dwell)
  const blocks = await page.evaluate(() => {
    const nodes = Array.from(
      document.querySelectorAll('h1,h2,h3,h4,p,li,summary,figcaption,a.btn,a.button,[class*="cta"]')
    );
    return nodes
      .map((el) => (el.innerText || '').trim().replace(/\s+/g, ' '))
      .filter((t) => t.length > 2)
      .slice(0, 120);
  });

  log(`reading ${blocks.length} text blocks line-by-line`);
  for (let i = 0; i < blocks.length; i++) {
    const text = blocks[i];
    readLog(`[${i + 1}/${blocks.length}] ${text.slice(0, 200)}`);
    // Pause proportional to length — simulate reading
    const dwell = Math.min(8000, 600 + text.length * 25);
    // Keep page engaged: tiny scroll jitter
    await page.evaluate(() => {
      window.scrollBy({ top: 40 + Math.random() * 80, behavior: 'smooth' });
    }).catch(() => {});
    await sleep(dwell);
    if ((i + 1) % 10 === 0) log(`read_progress ${i + 1}/${blocks.length}`);
  }
  return blocks.length;
}

async function slowScrollFullPage(page) {
  const height = await page.evaluate(() => document.body?.scrollHeight || 4000);
  for (let y = 0; y < height; y += 120) {
    await page.evaluate((yy) => window.scrollTo({ top: yy, behavior: 'smooth' }), y);
    await sleep(700 + Math.floor(Math.random() * 900));
  }
}

async function openFaqs(page) {
  const summaries = await page.$$('summary, details > summary');
  for (const el of summaries.slice(0, 12)) {
    try {
      await el.click({ delay: 40 });
      await sleep(1500 + Math.floor(Math.random() * 2000));
    } catch {}
  }
}

async function oneDeepRead() {
  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--window-size=1440,900',
      '--lang=en-US',
    ],
    defaultViewport: { width: 1440, height: 900 },
  });

  try {
    const page = await browser.newPage();
    await page.setUserAgent(
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36'
    );

    const resp = await page.goto('https://headroom-app.org/', {
      waitUntil: 'networkidle2',
      timeout: 60000,
    });
    log(`home status=${resp && resp.status()}`);
    await sleep(2000);

    // Full slow scroll first
    await slowScrollFullPage(page);

    // Section-by-section deep read
    for (const hash of SECTIONS) {
      log(`section_enter ${hash}`);
      await page.goto(`https://headroom-app.org/${hash === '#top' ? '' : hash}`, {
        waitUntil: 'domcontentloaded',
        timeout: 45000,
      }).catch(() => {});
      await sleep(1500);
      if (hash === '#faq') await openFaqs(page);
      const n = await readLineByLine(page);
      log(`section_done ${hash} lines=${n}`);
      await sleep(2000 + Math.floor(Math.random() * 3000));
    }

    // Final full pass home
    await page.goto('https://headroom-app.org/', { waitUntil: 'domcontentloaded', timeout: 45000 });
    await slowScrollFullPage(page);
    await sleep(5000);
    await page.close().catch(() => {});
    log('deep_read_complete');
  } finally {
    await browser.close().catch(() => {});
  }
}

async function main() {
  log('worker start (line-by-line read mode)');
  while (true) {
    try {
      await oneDeepRead();
      log('session_ok');
    } catch (e) {
      log(`session_fail ${e.message}`);
      await sleep(3000);
    }
    // Brief pause between full re-reads (timer also restarts workers every 10 min)
    await sleep(5000 + Math.floor(Math.random() * 5000));
  }
}

main();
