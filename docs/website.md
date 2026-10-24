# machealthapps.com

The product site, download link, statistics dashboard and their Cloudflare setup.

## Architecture

| Piece | Where | Code |
|---|---|---|
| Website | `https://machealthapps.com` (`www` redirects to it) | `website/` — static HTML/CSS/JS, no build step |
| Site Worker `machealthapps-site` | serves `website/` as static assets; handles `/download` and `/analytics.js` | `telemetry/src/site.ts`, `telemetry/wrangler.site.jsonc` |
| DMG hosting | `https://downloads.machealthapps.com` → R2 bucket `mac-health-app` | uploaded by `scripts/release.sh` |
| Stats Worker `devspace-telemetry` | `https://devspace-telemetry.<account>.workers.dev` — app events, `/v1/stats`, `/dashboard/` | `telemetry/src/index.ts`, `telemetry/wrangler.jsonc`, `telemetry/public/` |
| Database | D1 `devspace-telemetry`, bound as `DB` in both Workers | `telemetry/migrations/` |

Both Workers live in the `telemetry/` npm package and share its dependencies and tests.

## Pages

| Path | |
|---|---|
| `/` | Product page: hero with rotating examples (8, one at a time: cleanups — “X GB can be cleaned” — alternating with end-of-life toolchains — “Node.js 18 · End of life · update to 24 LTS”; every 3.5 s a blur crossfade with no movement, logo → name → size → label, `examples.js`; logos from Simple Icons, CC0), Clean (what it cleans, as icon cards), Toolchains, Security & network, stack (endless chip marquee), safety (line-icon cards that fade up and draw their icons on scroll, `reveal.js`) |
| `/privacy` | Privacy Policy: app statistics, Check Online, download counts, Google Analytics, rights (Dutch DPA), contact |
| `/terms` | Terms of Use: licence, user decides what is removed, no warranty, limitation of liability, Dutch law |
| `/download` | Counts one download for the day and version, then 302 to `DOWNLOAD_URL` |
| `/analytics.js` | GA consent banner + gtag.js loader with the configured Measurement ID; a no-op when none is set |
| 404 | `404.html` for any unknown path |
| `robots.txt`, `sitemap.xml` | `/download` is disallowed for crawlers |
| `llms.txt` | Summary for AI assistants ([llmstxt.org](https://llmstxt.org) format): facts, what it cleans, safety, links. Update it with the page |

## Configuration

| Setting | Where | Notes |
|---|---|---|
| `DOWNLOAD_URL` | `vars` in `telemetry/wrangler.site.jsonc` | The DMG `/download` redirects to. The version in its file name is what download counts are grouped by |
| `GA_MEASUREMENT_ID` | `vars` in `telemetry/wrangler.site.jsonc` | GA4 ID `G-…`. Empty = no analytics, no banner. Set it in the file: deploys overwrite dashboard variables |
| `STATS_TOKEN` | secret on the stats Worker (`npx wrangler secret put STATS_TOKEN`) | Protects `/v1/stats` and the dashboard. Never commit it |
| Custom domains | `routes` in `telemetry/wrangler.site.jsonc` | `machealthapps.com` and `www.machealthapps.com`; the site's workers.dev URL is off |
| Security headers | `website/_headers` (site), `telemetry/public/_headers` (dashboard) | Strict CSP; the site allows only Google Analytics hosts besides itself |
| `TELEMETRY_ENDPOINT` | app build variable | The stats Worker URL; without it a build never sends statistics |

## Deploy

```sh
cd telemetry
npm ci
npm run typecheck && npm test
npm run db:migrate:remote      # only when telemetry/migrations has something new
npm run deploy                 # stats Worker + dashboard
npm run site:deploy            # website + /download + /analytics.js
```

Local preview: `npm run site:dev` (http://127.0.0.1:8788) and `npm run dev` (http://127.0.0.1:8787/dashboard/), after
`npm run db:migrate:local`. A plain static preview also works: `python3 -m http.server 8000 --directory website`
(no `/download` or analytics there).

## Each release

1. `scripts/release.sh <version>` — uploads the versioned DMG, `DiskCleaner.dmg` (latest) and the appcast to the
   `mac-health-app` bucket.
2. Update `DOWNLOAD_URL` in `telemetry/wrangler.site.jsonc` to the new versioned DMG.
3. Update the release line in `website/index.html` (version and size) — the script prints the size and SHA-256.
4. `cd telemetry && npm run site:deploy`.

## Statistics

- **Downloads** — counted by the site Worker per day and version. Link previews, crawlers, prefetches and requests
  without a user agent are skipped. No IP, user agent, referrer or cookie is stored.
- **Installs, activity, cleanups** — sent by the app only after the user opts in (random install ID, versions,
  architecture, section and bytes cleaned). So these numbers are lower than reality.
- **Uninstalls** — an app can't report its own removal; "likely uninstalled" = installs not seen for 30 days.
- **Dashboard** — `https://devspace-telemetry.<account>.workers.dev/dashboard/`. Paste `STATS_TOKEN`; it's kept for
  that browser tab only and sent as a Bearer header.
- **Google Analytics** — website only, after consent in the banner; download clicks are `file_download` events.

## Status

Done:

- New positioning and copy: “Know your Mac's health. All in one app.”, built for developers; sticky header with
  smooth scrolling; header brand reads “Mac Cleaner”.
- Site moved from Cloudflare Pages to the `machealthapps-site` Worker on the custom domains.
- `/download` counter (D1 migration `0002_downloads.sql`) and the statistics dashboard — deployed.
- DMG 1.0 (notarized) in R2 behind `downloads.machealthapps.com`; release line shows its size.
- Terms of Use and expanded Privacy Policy (Netherlands); consent note under the download buttons.
- Google Analytics prepared with a consent banner — off until `GA_MEASUREMENT_ID` is set.
- Typography: Geist and Geist Mono (Google Fonts, SIL OFL) self-hosted in `website/assets/fonts/` — no request goes to
  Google, so no consent is needed and the CSP stays `'self'`.

Open:

- Set `GA_MEASUREMENT_ID` and redeploy to turn on Google Analytics; check the Accept path once.
- Product name: the header says “Mac Cleaner”, everything else (page copy, title, DMG, app) still says
  “Disk Cleaner”.
- Make sure release builds set `TELEMETRY_ENDPOINT`, or opted-in installs never reach the dashboard.
- Add a Cloudflare rate-limiting rule on `/download` and `/v1/events` so counts can't be inflated.
- Consider a licence prompt in the DMG (Agree/Disagree when it's opened) for stronger acceptance of the Terms, and a
  lawyer review of the Terms and Privacy Policy.
- Security and Network sections are advertised on the page; ship them in the next release.
