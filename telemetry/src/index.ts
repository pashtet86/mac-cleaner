import { eventSchema, MAX_BODY_BYTES, type TelemetryEvent } from "./schema";

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/v1/events") {
        if (request.method !== "POST") return error(405, "method not allowed");
        return await ingest(request, env);
      }
      if (url.pathname === "/v1/stats") {
        if (request.method !== "GET") return error(405, "method not allowed");
        if (!(await authorized(request, env))) return error(401, "unauthorized");
        return Response.json(await stats(env), { headers: { "Cache-Control": "no-store" } });
      }
      return error(404, "not found");
    } catch (e) {
      console.error(
        JSON.stringify({ message: "request failed", path: url.pathname, error: e instanceof Error ? e.message : String(e) }),
      );
      return error(500, "internal error");
    }
  },
} satisfies ExportedHandler<Env>;

async function ingest(request: Request, env: Env): Promise<Response> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) return error(413, "payload too large");

  // Bounded read: stop as soon as the body grows past the limit, whatever the header said.
  const raw = await readBounded(request, MAX_BODY_BYTES);
  if (raw === null) return error(413, "payload too large");

  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    return error(400, "invalid json");
  }
  const parsed = eventSchema.safeParse(json);
  if (!parsed.success) return error(400, "invalid event");

  await insert(env, parsed.data);
  return new Response(null, { status: 204 });
}

async function insert(env: Env, event: TelemetryEvent): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  const isCleanup = event.event === "cleanup";
  // Parameterized only; OR IGNORE drops repeated first_launch / app_open for the same day.
  await env.DB.prepare(
    `INSERT OR IGNORE INTO events (install_id, event, day, app_version, os_version, arch, section, bytes_cleaned)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`,
  )
    .bind(
      event.installId,
      event.event,
      day,
      event.appVersion,
      event.osVersion,
      event.arch,
      isCleanup ? event.section : null,
      isCleanup ? event.bytesCleaned : null,
    )
    .run();
}

async function readBounded(request: Request, limit: number): Promise<string | null> {
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > limit) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const body = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(body);
}

/** Bearer token compared in constant time (both sides hashed first so length doesn't leak). */
async function authorized(request: Request, env: Env): Promise<boolean> {
  const header = request.headers.get("authorization") ?? "";
  const provided = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!env.STATS_TOKEN || !provided) return false;
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(provided)),
    crypto.subtle.digest("SHA-256", encoder.encode(env.STATS_TOKEN)),
  ]);
  return crypto.subtle.timingSafeEqual(a, b);
}

async function stats(env: Env) {
  const db = env.DB;
  const results = await db.batch([
    db.prepare(
      `SELECT
         (SELECT COUNT(DISTINCT install_id) FROM events WHERE event = 'first_launch') AS installs,
         (SELECT COUNT(DISTINCT install_id) FROM events WHERE event = 'app_open' AND day >= date('now', '-6 days')) AS weekly_active,
         (SELECT COUNT(DISTINCT install_id) FROM events WHERE event = 'app_open' AND day >= date('now', '-29 days')) AS monthly_active`,
    ),
    db.prepare(
      `SELECT day, COUNT(DISTINCT install_id) AS installs FROM events
       WHERE event = 'first_launch' AND day >= date('now', '-29 days') GROUP BY day ORDER BY day`,
    ),
    db.prepare(
      `SELECT day, COUNT(DISTINCT install_id) AS active FROM events
       WHERE event = 'app_open' AND day >= date('now', '-29 days') GROUP BY day ORDER BY day`,
    ),
    db.prepare(latestBy("app_version")),
    db.prepare(latestBy("os_version")),
    db.prepare(latestBy("arch")),
    db.prepare(
      `SELECT section, COUNT(*) AS cleanups, SUM(bytes_cleaned) AS bytes FROM events
       WHERE event = 'cleanup' GROUP BY section ORDER BY bytes DESC`,
    ),
    // No app_open for 30 days: most likely uninstalled (apps can't report their own removal).
    db.prepare(
      `SELECT COUNT(*) AS churned FROM (
         SELECT install_id, MAX(day) AS last_seen FROM events GROUP BY install_id
       ) WHERE last_seen < date('now', '-30 days')`,
    ),
  ]);
  const rows = (index: number) => results[index]?.results ?? [];
  return {
    totals: rows(0)[0] ?? null,
    installsByDay: rows(1),
    activeByDay: rows(2),
    appVersions: rows(3),
    osVersions: rows(4),
    architectures: rows(5),
    cleaned: rows(6),
    churned: rows(7)[0] ?? null,
  };
}

/** Distribution of a field among installs active in the last 30 days, using each install's latest event. */
function latestBy(column: "app_version" | "os_version" | "arch"): string {
  return `SELECT ${column} AS value, COUNT(*) AS installs FROM (
            SELECT install_id, ${column}, MAX(id) FROM events
            WHERE day >= date('now', '-29 days') GROUP BY install_id
          ) GROUP BY ${column} ORDER BY installs DESC`;
}

function error(status: number, message: string): Response {
  return Response.json({ error: message }, { status });
}
