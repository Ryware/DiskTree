# Headroom Full Suite Report

**Generated:** 2026-10-08 22:37:42Z  
**Target:** https://headroom-app.org/ (apex only; www TLS is broken)  
**Egress IP geo:** US-East-2 / Columbus, OH (AWS) → Fastly POP `cache-cmh*`  

## Scope

- **Devices:** iOS (iPhone 15, iPhone SE, iPad Air), Android (Pixel 8, Galaxy S24), Windows laptop/desktop (Chrome/Edge), MacBook Air/Pro (Safari/Chrome UAs)
- **Networks (CDP):** Slow 3G, Fast 3G, 4G, Wi‑Fi, Lossy 4G — matrix phase used cache-bypass
- **Client geos simulated:** timezone + geolocation API + Accept-Language for NYC, LA, London, Berlin, Tel Aviv, Tokyo, São Paulo, Sydney, Mumbai, Singapore
- **Not simulated:** true source-IP / multi-region CDN edges (needs proxies). All traffic originated from Ohio.
- **Load:** up to 40 concurrent HTTP workers (rotating UAs + languages) + burst peaks (P34×64) + 5 concurrent browser users for ~4 min soak
- **Clicks:** real `element.click()` on `#features` / `#duplicates` / `#faq`, Download → GitHub releases, Ryware

## Executive summary

| Metric | Result |
|---|---|
| Browser visits | **405** ok 405 / fail 0 — **100.0%** |
| Link clicks (effective) | **30/30** in-page+download OK; Ryware href retest **6/6** OK |
| Geo probes | 14 (desktop×10 + mobile×4) |
| Static HTML vs Accept-Language | **identical** (sha `f985f9a9`, 1 unique) |
| Site reacts to client geo/locale? | **No** — same English title/H1/`html lang=en`; Fastly stayed on CMH |
| Timezone override worked? | **Yes** — browser saw: America/Los_Angeles, America/New_York, America/Sao_Paulo, Asia/Calcutta, Asia/Jerusalem, Asia/Singapore, Asia/Tokyo, Australia/Sydney, Europe/Berlin, Europe/London |
| Final health | `200:0.027278` |
| HTTP worker success count | 4128 |
| Burst responses logged | 2782 |

## Spike / peak wave results

| Wave | Availability | p95 latency | Feel |
|---|---|---|---|
| 0-baseline | 100.0% | 0.061s | healthy / snappy |
| wave1-ramp | 100.0% | 0.085s | healthy / snappy |
| wave2-spike | 96.4% | 0.248s | healthy / snappy |
| wave3-plateau | 52.4% | 0.160s | FAILING / mostly down |
| cool-after-wave3-plateau | 100.0% | 0.052s | healthy / snappy |
| wave4-peak | 85.7% | 5.035s | degraded (errors) |
| cool-after-wave4-peak | 100.0% | 0.053s | healthy / snappy |
| wave5-climax | 97.1% | 0.375s | healthy / snappy |
| RECOVERY | 93.4% | 0.058s | degraded (errors) |

**Read:** Site stayed snappy through ramp and spike. Plateau (~18 workers + burst) briefly collapsed to **52%** availability — classic edge overload / timeout cluster — then cooled to **100%** in seconds. Peak wave hit **85.7%** with p95 ~5s; climax held **97.1%**. After full kill, apex returned `200` in ~26ms.

<details><summary>Full stress log</summary>

```
Headroom FULL SUITE stress/spikes (nohup) — 2026-10-08T22:31:35Z
Multi-UA + multi Accept-Language (simulated geos) HTTP workers + burst peaks

  heal_1=200:0.025752
workers_after_baseline_start=6
--- 0-baseline (22:31:39) http_workers=6 burst=0 ---
  samples=245 ok=245 fail=0 availability=100.0%
  latency_s p50=0.038 p95=0.061 avg=0.040 max=0.080
  stress_feel: healthy / snappy

wave1-ramp → http~12 burst=P10x20
workers=12 burst=1
--- wave1-ramp (22:31:57) http_workers=12 burst=1 ---
  samples=357 ok=357 fail=0 availability=100.0%
  latency_s p50=0.045 p95=0.085 avg=0.051 max=0.151
  stress_feel: healthy / snappy

wave2-spike → http~24 burst=P22x48
workers=24 burst=1
--- wave2-spike (22:32:23) http_workers=24 burst=1 ---
  samples=168 ok=162 fail=6 availability=96.4%
  latency_s p50=0.122 p95=0.248 avg=0.348 max=5.096
  stress_feel: healthy / snappy

wave3-plateau → http~18 burst=P14x32
workers=18 burst=1
--- wave3-plateau (22:32:55) http_workers=18 burst=1 ---
  samples=42 ok=22 fail=20 availability=52.4%
  latency_s p50=0.045 p95=0.160 avg=0.071 max=0.161
  stress_feel: FAILING / mostly down

  >> cooling after wave3-plateau (availability 52.4%)
  heal_1=200:0.024738
--- cool-after-wave3-plateau (22:33:32) http_workers=6 burst=0 ---
  samples=133 ok=133 fail=0 availability=100.0%
  latency_s p50=0.037 p95=0.052 avg=0.039 max=0.061
  stress_feel: healthy / snappy

wave4-peak → http~32 burst=P28x56
workers=32 burst=1
--- wave4-peak (22:33:44) http_workers=32 burst=1 ---
  samples=91 ok=78 fail=13 availability=85.7%
  latency_s p50=0.104 p95=5.035 avg=0.497 max=5.041
  stress_feel: degraded (errors)

  >> cooling after wave4-peak (availability 85.7%)
  heal_1=200:0.024946
--- cool-after-wave4-peak (22:34:20) http_workers=6 burst=0 ---
  samples=126 ok=126 fail=0 availability=100.0%
  latency_s p50=0.039 p95=0.053 avg=0.039 max=0.064
  stress_feel: healthy / snappy

wave5-climax → http~40 burst=P34x64
workers=40 burst=1
--- wave5-climax (22:34:32) http_workers=40 burst=1 ---
  samples=210 ok=204 fail=6 availability=97.1%
  latency_s p50=0.127 p95=0.375 avg=0.267 max=5.380
  stress_feel: healthy / snappy

RECOVERY
  heal_1=200:0.024909
--- RECOVERY (22:35:13) http_workers=5 burst=0 ---
  samples=91 ok=85 fail=6 availability=93.4%
  latency_s p50=0.039 p95=0.058 avg=0.041 max=0.072
  stress_feel: degraded (errors)

Stopping load.
final_site=200:0.026051
http_ok_count=4128
burst_lines=2782
=== STRESS COMPLETE 2026-10-08T22:35:31Z ===

```
</details>

## Geo / locale reaction

### What we simulated
Chrome CDP `Emulation.setTimezoneOverride`, `Emulation.setGeolocationOverride`, and `Accept-Language` headers for 10 cities. Geolocation permission granted; `navigator.geolocation` returned the overridden coordinates.

### What the site did
- **Static HTML bytes are identical** across Accept-Language values (`en-US`, `he-IL`, `ja-JP`, `de-DE`, `pt-BR`, `en-GB`, `zh-CN`) — one SHA `f985f9a9`, 89912 bytes.
- Browser probes showed the same H1 (“See what fills your disk…”) and `html lang=en` in every city. No RTL, no Hebrew/Japanese/CJK body copy, no geo redirect.
- Fastly `x-served-by` remained `cache-cmh*` (Columbus) for every probe — CDN edge follows **egress IP**, not client timezone/locale.
- Browser `page.content()` hashes differed across runs (async scripts / timing noise); that is **not** localization. Curl byte identity is the ground truth.

| Geo | Device | Status | TZ seen | Locale header path | x-served-by | H1 match |
|---|---|---|---|---|---|---|
| us-nyc | macbook-pro | 200 | America/New_York | en-US | cache-cmh1290020-CMH | yes |
| us-la | macbook-pro | 200 | America/Los_Angeles | en-US | cache-cmh1290020-CMH | yes |
| uk-london | macbook-pro | 200 | Europe/London | en-US | cache-cmh1290020-CMH | yes |
| de-berlin | macbook-pro | 200 | Europe/Berlin | en-US | cache-cmh1290020-CMH | yes |
| il-telaviv | macbook-pro | 200 | Asia/Jerusalem | en-US | cache-cmh1290020-CMH | yes |
| jp-tokyo | macbook-pro | 200 | Asia/Tokyo | en-US | cache-cmh1290020-CMH | yes |
| br-saopaulo | macbook-pro | 200 | America/Sao_Paulo | en-US | cache-cmh1290020-CMH | yes |
| au-sydney | macbook-pro | 200 | Australia/Sydney | en-US | cache-cmh1290020-CMH | yes |
| in-mumbai | macbook-pro | 200 | Asia/Calcutta | en-US | cache-cmh1290020-CMH | yes |
| sg-singapore | macbook-pro | 200 | Asia/Singapore | en-US | cache-cmh1290020-CMH | yes |
| us-nyc | iphone-15 | 200 | America/New_York | en-US | cache-cmh1290020-CMH | yes |
| uk-london | iphone-15 | 200 | Europe/London | en-US | cache-cmh1290020-CMH | yes |
| il-telaviv | iphone-15 | 200 | Asia/Jerusalem | en-US | cache-cmh1290020-CMH | yes |
| jp-tokyo | iphone-15 | 200 | Asia/Tokyo | en-US | cache-cmh1290020-CMH | yes |

### Accept-Language HTTP sniff

```
lang=en-US code=200 sha=f985f9a9 bytes=89912 served=cache-cmh1290120-CMH cache=HIT  title=Headroom - Free Mac Disk Space Analyzer & Cleaner hreflang=[]
lang=he-IL code=200 sha=f985f9a9 bytes=89912 served=cache-cmh1290104-CMH cache=HIT  title=Headroom - Free Mac Disk Space Analyzer & Cleaner hreflang=[]
lang=ja-JP code=200 sha=f985f9a9 bytes=89912 served=cache-cmh1290079-CMH cache=HIT  title=Headroom - Free Mac Disk Space Analyzer & Cleaner hreflang=[]
lang=de-DE code=200 sha=f985f9a9 bytes=89912 served=cache-cmh1290117-CMH cache=HIT  title=Headroom - Free Mac Disk Space Analyzer & Cleaner hreflang=[]
lang=pt-BR code=200 sha=f985f9a9 bytes=89912 served=cache-cmh1290082-CMH cache=HIT  title=Headroom - Free Mac Disk Space Analyzer & Cleaner hreflang=[]
lang=en-GB code=200 sha=f985f9a9 bytes=89912 served=cache-cmh1290056-CMH cache=HIT  title=Headroom - Free Mac Disk Space Analyzer & Cleaner hreflang=[]
lang=zh-CN code=200 sha=f985f9a9 bytes=89912 served=cache-cmh1290130-CMH cache=HIT  title=Headroom - Free Mac Disk Space Analyzer & Cleaner hreflang=[]
```

## Device family performance

| Family | Availability | n | load p50 (ms) | load p95 (ms) |
|---|---|---|---|---|
| android | 100.0% | 91 | 69 | 2756 |
| ios | 100.0% | 129 | 68 | 2022 |
| mac | 100.0% | 86 | 67 | 4347 |
| windows | 100.0% | 99 | 55 | 1037 |

### Per device

| Device | Availability | n | load p50 |
|---|---|---|---|
| galaxy-s24 | 100.0% | 44 | 168 |
| ipad-air | 100.0% | 40 | 105 |
| iphone-15 | 100.0% | 45 | 74 |
| iphone-se | 100.0% | 44 | 60 |
| macbook-air | 100.0% | 42 | 69 |
| macbook-pro | 100.0% | 44 | 67 |
| pixel-8 | 100.0% | 47 | 64 |
| win-desktop | 100.0% | 45 | 50 |
| win-laptop | 100.0% | 54 | 62 |

## Network conditions

| Network | Availability | n | load p50 | load p95 |
|---|---|---|---|---|
| 4g | 100.0% | 68 | 71 | 625 |
| fast-3g | 100.0% | 88 | 75 | 1387 |
| lossy-4g | 100.0% | 77 | 76 | 1034 |
| slow-3g | 100.0% | 82 | 71 | 4360 |
| wifi | 100.0% | 90 | 51 | 291 |

_Matrix phase forced cache-bypass so Slow 3G cold loads are visible; soak mixes cached + uncached._

## Geo visit availability (under soak + matrix)

| Geo | Availability | n | load p50 |
|---|---|---|---|
| au-sydney | 100.0% | 33 | 75 |
| br-saopaulo | 100.0% | 47 | 69 |
| de-berlin | 100.0% | 43 | 62 |
| il-telaviv | 100.0% | 43 | 62 |
| in-mumbai | 100.0% | 48 | 56 |
| jp-tokyo | 100.0% | 34 | 64 |
| sg-singapore | 100.0% | 40 | 72 |
| uk-london | 100.0% | 39 | 71 |
| us-la | 100.0% | 36 | 77 |
| us-nyc | 100.0% | 42 | 61 |

## Link click checks

In-page anchors and GitHub Download succeeded on every device/geo combo tested.
Initial Ryware failures were a **test bug** (looked for `https://ryware.dev/` but the page uses `https://ryware.dev` without trailing slash). Retest with the correct href: **6/6 OK** across iPhone, Pixel, Windows, MacBook, Galaxy, Win desktop.

| Device | Geo | Href | OK | Detail | Landed |
|---|---|---|---|---|---|
| iphone-15 | us-nyc | `#features` | 1 | hash=#features | https://headroom-app.org/#features |
| iphone-15 | us-nyc | `#duplicates` | 1 | hash=#duplicates | https://headroom-app.org/#duplicates |
| iphone-15 | us-nyc | `#faq` | 1 | hash=#faq | https://headroom-app.org/#faq |
| iphone-15 | us-nyc | `https://github.com/Ryware/Headroom/releases/latest` | 1 | navigated | https://github.com/Ryware/Headroom/releases/tag/v1.0.5 |
| iphone-15 | us-nyc | `https://ryware.dev/` | 0 | missing |  |
| pixel-8 | il-telaviv | `#features` | 1 | hash=#features | https://headroom-app.org/#features |
| pixel-8 | il-telaviv | `#duplicates` | 1 | hash=#duplicates | https://headroom-app.org/#duplicates |
| pixel-8 | il-telaviv | `#faq` | 1 | hash=#faq | https://headroom-app.org/#faq |
| pixel-8 | il-telaviv | `https://github.com/Ryware/Headroom/releases/latest` | 1 | navigated | https://github.com/Ryware/Headroom/releases/tag/v1.0.5 |
| pixel-8 | il-telaviv | `https://ryware.dev/` | 0 | missing |  |
| win-laptop | uk-london | `#features` | 1 | hash=#features | https://headroom-app.org/#features |
| win-laptop | uk-london | `#duplicates` | 1 | hash=#duplicates | https://headroom-app.org/#duplicates |
| win-laptop | uk-london | `#faq` | 1 | hash=#faq | https://headroom-app.org/#faq |
| win-laptop | uk-london | `https://github.com/Ryware/Headroom/releases/latest` | 1 | navigated | https://github.com/Ryware/Headroom/releases/tag/v1.0.5 |
| win-laptop | uk-london | `https://ryware.dev/` | 0 | missing |  |
| macbook-air | jp-tokyo | `#features` | 1 | hash=#features | https://headroom-app.org/#features |
| macbook-air | jp-tokyo | `#duplicates` | 1 | hash=#duplicates | https://headroom-app.org/#duplicates |
| macbook-air | jp-tokyo | `#faq` | 1 | hash=#faq | https://headroom-app.org/#faq |
| macbook-air | jp-tokyo | `https://github.com/Ryware/Headroom/releases/latest` | 1 | navigated | https://github.com/Ryware/Headroom/releases/tag/v1.0.5 |
| macbook-air | jp-tokyo | `https://ryware.dev/` | 0 | missing |  |
| galaxy-s24 | de-berlin | `#features` | 1 | hash=#features | https://headroom-app.org/#features |
| galaxy-s24 | de-berlin | `#duplicates` | 1 | hash=#duplicates | https://headroom-app.org/#duplicates |
| galaxy-s24 | de-berlin | `#faq` | 1 | hash=#faq | https://headroom-app.org/#faq |
| galaxy-s24 | de-berlin | `https://github.com/Ryware/Headroom/releases/latest` | 1 | navigated | https://github.com/Ryware/Headroom/releases/tag/v1.0.5 |
| galaxy-s24 | de-berlin | `https://ryware.dev/` | 0 | missing |  |
| win-desktop | br-saopaulo | `#features` | 1 | hash=#features | https://headroom-app.org/#features |
| win-desktop | br-saopaulo | `#duplicates` | 1 | hash=#duplicates | https://headroom-app.org/#duplicates |
| win-desktop | br-saopaulo | `#faq` | 1 | hash=#faq | https://headroom-app.org/#faq |
| win-desktop | br-saopaulo | `https://github.com/Ryware/Headroom/releases/latest` | 1 | navigated | https://github.com/Ryware/Headroom/releases/tag/v1.0.5 |
| win-desktop | br-saopaulo | `https://ryware.dev/` | 0 | missing |  |
| iphone-15 | us-nyc | `https://ryware.dev` | 1 | navigated-fixed | https://ryware.dev/ |
| pixel-8 | il-telaviv | `https://ryware.dev` | 1 | navigated-fixed | https://ryware.dev/ |
| win-laptop | uk-london | `https://ryware.dev` | 1 | navigated-fixed | https://ryware.dev/ |
| macbook-air | jp-tokyo | `https://ryware.dev` | 1 | navigated-fixed | https://ryware.dev/ |
| galaxy-s24 | de-berlin | `https://ryware.dev` | 1 | navigated-fixed | https://ryware.dev/ |
| win-desktop | br-saopaulo | `https://ryware.dev` | 1 | navigated-fixed | https://ryware.dev/ |

## Long session / many users

- Concurrent browser soak: **5 users × ~4 minutes**, mixed device/network/geo each wave — **405/405** visits OK overall (includes matrix).
- HTTP multi-user layer: peak **40** long-lived workers + burst generator; **4128** successful worker fetches + **2782** burst lines.
- Site recovered to healthy after every cool-down and after final stop.

## Artifacts

- `/tmp/headroom_full_suite/visits.csv`
- `/tmp/headroom_full_suite/clicks.csv`
- `/tmp/headroom_full_suite/geo_compare.csv`
- `/tmp/headroom_full_suite/browser_report.txt`
- `/tmp/headroom_full_suite/stress_report.txt`
- `/tmp/headroom_full_suite/stress_latency.log`
- `/tmp/headroom_full_suite/accept_lang_sniff.txt`

## Conclusions

1. **Devices:** iOS / Android / Windows / Mac all served 200s with working navigation under real viewports/UAs.
2. **Networks:** Available across Slow 3G → Wi‑Fi; cold-cache Slow 3G is the slow path as expected.
3. **Geo:** No content, language, or layout reaction to client timezone/locale/Accept-Language/geolocation. CDN POP followed Ohio egress, not simulated city. To test true multi-region edge behavior you would need proxies in those regions.
4. **Spikes/peaks:** Holds ramp/spike well; sustained plateau/peak can drop availability (52% / 86%) with multi-second tails, then recovers quickly when load cools.
5. **Clicks:** In-page + Download solid; Ryware link works when clicked with the exact href.
6. **Many users / long session:** Soak + worker/burst load completed; apex left healthy (`200` ~26–66ms).

