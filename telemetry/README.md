# DevSpace statistics Worker

Receives opt-in, anonymous events from DevSpace and stores them in Cloudflare D1. No IP address, user agent, host
name, user name or path is stored; the request schema rejects any field that isn't listed in `src/schema.ts`.

| Endpoint | |
|---|---|
| `POST /v1/events` | `first_launch`, `app_open` (once per install per day), `cleanup` (section + bytes). 204 on success |
| `GET /v1/stats` | Aggregates: installs, weekly/monthly active, installs and actives by day, versions, macOS, architecture, bytes cleaned per section, and installs not seen for 30 days (≈ uninstalled). Needs `Authorization: Bearer <STATS_TOKEN>` |

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

Consider a Cloudflare rate-limiting rule on `/v1/events` (dashboard → Security → WAF) once it's public.

## Develop

```sh
cp .dev.vars.example .dev.vars                 # set a local STATS_TOKEN
npm run db:migrate:local
npm run dev                                    # http://127.0.0.1:8787
npm run typecheck && npm test
```

A Debug build of the app accepts `TELEMETRY_ENDPOINT=http://127.0.0.1:8787`; Release builds require HTTPS.
After changing `wrangler.jsonc`, run `npm run types` and commit `worker-configuration.d.ts`.
