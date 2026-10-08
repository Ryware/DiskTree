// Renders promo.html to an MP4 frame by frame: each frame calls window.render(t),
// so the timing is exact regardless of how fast the machine is.
//   node promo/render.mjs [out.mp4] [fps] [--stills t1,t2,...]
import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const stillsArg = args.indexOf('--stills');
const out = args[0] && !args[0].startsWith('--') ? args[0] : path.join(here, 'headroom-promo.mp4');
const fps = Number(args[1]) || 30;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(path.join(here, 'promo.html')).href);
await page.evaluate(() => document.fonts.ready);

if (stillsArg >= 0) {
  for (const t of args[stillsArg + 1].split(',').map(Number)) {
    await page.evaluate(t => window.render(t), t);
    await page.screenshot({ path: path.join(path.dirname(out), `still-${t}.png`) });
  }
  await browser.close();
  process.exit(0);
}

const duration = await page.evaluate(() => window.DURATION);
const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps), '-i', '-',
  '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-preset', 'slow', '-crf', '18', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
const frames = Math.round(duration * fps);
for (let i = 0; i < frames; i++) {
  await page.evaluate(t => window.render(t), i / fps);
  const buf = await page.screenshot({ type: 'png' });
  if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
  if (i % fps === 0) process.stdout.write(`\r${(i / fps).toFixed(0)}/${duration}s`);
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));
await browser.close();
console.log(`\nwrote ${out}`);
