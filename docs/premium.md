# Premium with Paddle — plan

Status: **plan, nothing implemented.** Disk Cleaner stays a notarized, direct-download app (the App Store sandbox
would remove its core features). Premium is sold through **Paddle Billing** as merchant of record: Paddle is the
seller, collects and remits VAT worldwide, sends receipts and handles refunds and chargebacks. Checkout offers cards,
Apple Pay, iDEAL, PayPal and local methods.

Paddle Billing has no built-in licence keys, so we issue our own: Paddle tells our Worker about a purchase, the Worker
creates a licence and signs it, and the app verifies the signature offline.

## Decisions to make first

| Question | Options | Suggestion |
|---|---|---|
| Pricing model | one-time licence · yearly subscription · both | One-time licence with 1 year of updates (developers prefer it); add a subscription later if needed |
| Price | — | Decide with a quick look at comparable Mac utilities |
| What is Premium | — | Free: all scans and manual cleanup. Premium: Security and Network audits, Environments update commands, scheduled scans, menu-bar monitor |
| Macs per licence | 1 · 2 · 3 | 3 activations, self-service deactivation |
| How buyers get the key | email from us · shown after checkout | Email (needs an email provider) + “restore by email” |

## How it fits together

```
website /pricing ──Paddle.js overlay──▶ Paddle checkout (cards, Apple Pay, iDEAL…)
                                             │ transaction.completed (signed webhook)
                                             ▼
                         stats Worker  /v1/paddle/webhook ──▶ D1: licenses
                                             │ email with licence key
                                             ▼
app: Settings → License  ──POST /v1/licenses/activate──▶ signed token (Ed25519)
app verifies the token offline with its built-in public key; re-checks weekly
```

Everything server-side goes into the existing stats Worker (`telemetry/`), next to `/v1/events` and `/v1/stats`.

## Paddle setup

1. Create a **sandbox** account (sandbox-vendors.paddle.com) for development, and the live account (vendors.paddle.com)
   with the company's details. The legal name must match the name on the website exactly.
2. **Domain approval** for `machealthapps.com` — Paddle reviews the live site, typically a few business days. Before
   submitting, the site needs: HTTPS ✓, product description ✓, a visible **price**, and **Terms, Refund Policy and
   Privacy Policy** reachable from the navigation, with the company name and **Paddle named as merchant of record**. A
   “no refunds” clause gets rejected; offer 14–30 days.
3. Catalog: product “Disk Cleaner Premium”, one price (one-time). Note the `pri_…` ID.
4. **Client-side token** (`test_…` / `live_…`, public) for Paddle.js.
5. **Notification destination** → `https://devspace-telemetry.<account>.workers.dev/v1/paddle/webhook` with events
   `transaction.completed`, `adjustment.created`, `adjustment.updated` (refunds and chargebacks). Paddle generates a
   secret for this destination.

## Configuration

| Name | Kind | Worker | Notes |
|---|---|---|---|
| `PADDLE_ENV` | var | site | `sandbox` or `production` |
| `PADDLE_CLIENT_TOKEN` | var | site | public, used by Paddle.js |
| `PADDLE_PRICE_ID` | var | site | `pri_…` |
| `PADDLE_WEBHOOK_SECRET` | **secret** | stats | from the notification destination |
| `LICENSE_SIGNING_KEY` | **secret** | stats | Ed25519 private key (PKCS#8, base64). The public half is compiled into the app |
| `EMAIL_API_KEY` | **secret** | stats | for sending licence keys, if we use an email provider |

Secrets go in with `npx wrangler secret put <NAME>`, never in a file. Keep a backup of `LICENSE_SIGNING_KEY` in a
password manager: losing it means no new licences can be verified by existing app versions.

## Data (D1 migration `0003_licenses.sql`)

```sql
CREATE TABLE licenses (
    id TEXT PRIMARY KEY,                 -- random, e.g. lic_…
    key_hash TEXT NOT NULL UNIQUE,       -- SHA-256 of the licence key; the key itself is never stored
    email TEXT NOT NULL,                 -- for restore and support
    paddle_transaction_id TEXT NOT NULL UNIQUE,
    plan TEXT NOT NULL,                  -- premium
    updates_until TEXT NOT NULL,         -- purchase date + 1 year
    status TEXT NOT NULL,                -- active | refunded | chargeback
    created_at TEXT NOT NULL
);
CREATE TABLE activations (
    license_id TEXT NOT NULL REFERENCES licenses(id),
    activation_id TEXT NOT NULL,         -- random UUID created by the app, kept in the Keychain
    created_at TEXT NOT NULL,
    last_seen TEXT NOT NULL,
    PRIMARY KEY (license_id, activation_id)
);
```

No hardware serials, Mac names or user names: the app identifies itself only by a random activation ID (same rule as
telemetry). This table holds personal data (email), so the Privacy Policy changes.

## Worker endpoints (stats Worker)

| Endpoint | Does |
|---|---|
| `POST /v1/paddle/webhook` | Reads the **raw** body, checks `Paddle-Signature` (`ts=…;h1=…`): HMAC-SHA256 of `ts:rawBody` with `PADDLE_WEBHOOK_SECRET`, constant-time compare, reject if `ts` is older than a few minutes, accept any `h1` during secret rotation. Idempotent on the event ID. `transaction.completed` → create licence + email key. Approved refund/chargeback adjustment → `status = refunded` |
| `POST /v1/licenses/activate` | `{ key, activationId, appVersion }` → checks status and the 3-activation limit → returns a signed token |
| `POST /v1/licenses/validate` | `{ token }` → fresh token, or `revoked`. Called by the app weekly |
| `POST /v1/licenses/deactivate` | `{ token }` → frees the slot |
| `POST /v1/licenses/restore` | `{ email }` → re-sends keys to that address (always answers the same, so it can't be used to probe emails); rate-limited |

All bodies validated with Zod strict schemas, all SQL parameterized, rate limiting on activate/restore (Cloudflare rule
or a Workers rate-limit binding).

### Licence token

`base64url(payload) + "." + base64url(Ed25519 signature)`, payload:

```json
{ "lic": "lic_…", "plan": "premium", "act": "<activationId>", "updatesUntil": "2027-10-23", "iat": 1792800000, "exp": 1795392000 }
```

`exp` ≈ 30 days: the app works offline for a month, re-validates weekly when online, and falls back to Free only after
the token expires and validation fails or says `revoked`. Workers sign with WebCrypto `Ed25519`; the app verifies with
CryptoKit `Curve25519.Signing.PublicKey`.

## App changes

- `Core/License/` (UI-free, `nonisolated`): token parsing and Ed25519 verification, Keychain storage of token and
  activation ID, weekly validation via `URLSession` (HTTPS only in Release, like telemetry).
- `Entitlements` — one place that answers “is Premium?”; sections and actions check it. Locked features show what they
  do and a **Buy Premium** button that opens `https://machealthapps.com/pricing?from=app`.
- Settings → **License**: enter key, see status / Macs used / updates until, deactivate this Mac, restore by email.
- Updates (Sparkle): a build released after `updatesUntil` keeps working as Free — or keep Premium for versions released
  before that date (decide; the second is friendlier).
- Telemetry (optional): add `plan: "free" | "premium"` to the strict schema — nothing else.
- Tests: token verification (valid, tampered, expired, wrong key), entitlement checks, Keychain in a test access group.

## Website changes

- `/pricing` section on the home page (Free vs Premium table, price, **Buy** button) and a `Pricing` header link.
- Paddle.js v2 (`https://cdn.paddle.com/paddle/v2/paddle.js`) loaded by our own `checkout.js`, configured from
  `PADDLE_*` vars the same way `analytics.js` gets `GA_MEASUREMENT_ID`. Overlay checkout; on `checkout.completed`
  show “Check your email for your licence key”.
- CSP in `website/_headers`: allow `https://cdn.paddle.com` (script), `https://buy.paddle.com` and
  `https://sandbox-buy.paddle.com` (frame), and Paddle's API hosts (connect).
- New `/refunds` page (e.g. 14 days, no questions), linked in the footer.
- Terms: Free + Premium licence, “Our order process is conducted by our online reseller Paddle.com. Paddle.com is the
  Merchant of Record for all our orders”, link to Paddle's buyer terms, EU right of withdrawal for digital content.
- Privacy Policy: Paddle processes payment data as merchant of record; we store the buyer's email, licence status and
  activation IDs for licence delivery and support.
- Dashboard: add sales (licences, refunds, active activations) to `/v1/stats`.

## Phases

| # | Phase | Est. |
|---|---|---|
| 0 | Decisions above; Paddle sandbox + live account; company details | 0.5 day |
| 1 | Website: pricing, refund page, Terms/Privacy updates → **submit domain approval** (runs in the background) | 1 day |
| 2 | Worker: migration, webhook + signature check, licence endpoints, signing, email, tests (sandbox) | 2–3 days |
| 3 | App: License core, Settings → License, entitlements, locked-feature UI, tests | 2–3 days |
| 4 | Checkout on the site, CSP, dashboard sales | 0.5–1 day |
| 5 | End-to-end in sandbox (Paddle test cards): buy → email → activate → 4th Mac refused → deactivate → refund → revoked after validation; offline for 30+ days; tampered token | 1 day |
| 6 | Go live: live token/price/secret, switch `PADDLE_ENV`, one real purchase + refund | 0.5 day |
| | **Total** | **≈ 8–10 working days** |

## Risks

- **Domain approval** can take several rounds — start phase 1 early.
- **Licence sharing / cracking** — offline signatures can't stop patched binaries; the activation limit handles casual
  sharing. Don't spend more than that.
- **Signing key loss or leak** — back it up; a leak means rotating the key and shipping an app update.
- **Webhook gaps** — handle retries idempotently; add a daily reconciliation against Paddle's API later if needed.
