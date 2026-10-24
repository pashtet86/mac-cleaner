# Disk Cleaner statistics and website Workers

Receives opt-in, anonymous events from Disk Cleaner and stores them in Cloudflare D1. No IP address, user agent, host
name, user name or path is stored; the request schema rejects any field that isn't listed in `src/schema.ts`.

| Endpoint | |
|---|---|
| `POST /v1/events` | `first_launch`, `app_open` (once per install per day), `cleanup` (section + bytes). 204 on success |
| `GET /dashboard/` | Statistics dashboard: asks for `STATS_TOKEN`, keeps it for the browser tab only, reads `/v1/stats` |
| `GET /v1/stats` | Aggregates: installs, weekly/monthly active, installs and actives by day, versions, macOS, architecture, bytes cleaned per section, and installs not seen for 30 days (≈ uninstalled), website downloads. Needs `Authorization: Bearer <STATS_TOKEN>` |

The same package also holds the **website Worker** (`wrangler.site.jsonc`, `src/site.ts`): it serves `../website` as
static files and answers `/download` with a redirect to the current DMG (`DOWNLOAD_URL`), adding one to the
`downloads` counter for that day and version. Link previews, crawlers and prefetches aren't counted; no IP, user agent,
referrer or cookie is stored. Both Workers bind the same D1 database.

## Deploy (once)

Needs a Cloudflare account (the free plan is enough).

```sh
cd telemetry
npm ci
npx wrangler login
npx wrangler d1 create devspace-telemetry      # put the printed database_id on the existing "DB" binding
npm run db:migrate:remote
npx wrangler secret put STATS_TOKEN            # paste the output of: openssl rand -hex 32
npm run deploy                                 # prints https://devspace-telemetry.<account>.workers.dev
```

If `d1 create` offers to add the binding to `wrangler.jsonc` itself, decline (or delete the extra entry
afterwards): the Worker and migrations use the binding named `DB`.

Then build the app with that URL: `TELEMETRY_ENDPOINT=https://… make dmg`.

Read the numbers:

```sh
curl -s -H "Authorization: Bearer $STATS_TOKEN" https://devspace-telemetry.<account>.workers.dev/v1/stats | jq
```

Or open `https://devspace-telemetry.<account>.workers.dev/dashboard/` and paste the token.

### Website

```sh
npm run db:migrate:remote                      # adds the downloads table (0002) if not applied yet
npm run site:deploy                            # serves machealthapps.com and www (workers.dev is off)
```

Then attach the domain: add `machealthapps.com` as a zone on the account, uncomment `routes` in
`wrangler.site.jsonc` and deploy again (or Workers → machealthapps-site → Settings → Domains). If the site is still on
Cloudflare Pages, remove the domain from the Pages project first. The public download link is
`https://machealthapps.com/download`.

**Google Analytics (optional).** Put the GA4 Measurement ID (`G-…`, from Analytics → Admin → Data streams) in
`GA_MEASUREMENT_ID` in `wrangler.site.jsonc` and run `npm run site:deploy`. The Worker adds it to `/analytics.js`, which
shows a consent banner and loads `gtag.js` only after the visitor accepts (no Tag Manager container). Download clicks
are sent as `file_download` events. Leave the ID empty to turn analytics and the banner off.

On each release: upload the DMG, update `DOWNLOAD_URL` in `wrangler.site.jsonc` and the release block in
`website/index.html`, then `npm run site:deploy`.

Consider a Cloudflare rate-limiting rule on `/v1/events` (dashboard → Security → WAF) once it's public.

## Develop

```sh
cp .dev.vars.example .dev.vars                 # set a local STATS_TOKEN
npm run db:migrate:local
npm run dev                                    # stats: http://127.0.0.1:8787/dashboard/
npm run site:dev                               # website: http://127.0.0.1:8788
npm run typecheck && npm test
```

A Debug build of the app accepts `TELEMETRY_ENDPOINT=http://127.0.0.1:8787`; Release builds require HTTPS.
After changing `wrangler.jsonc`, run `npm run types` and commit `worker-configuration.d.ts`.
