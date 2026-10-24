/** Shared by the site Worker (counts) and the stats Worker (reads). */

/** Link previews, crawlers and prefetches shouldn't count as downloads. */
const NOT_A_PERSON = /bot|crawl|spider|slurp|preview|facebookexternalhit|embedly|whatsapp|telegram|discord|slack/i;

export function isCountable(request: Request): boolean {
  if (request.method !== "GET") return false;
  const purpose = request.headers.get("sec-purpose") ?? request.headers.get("purpose") ?? "";
  if (/prefetch|prerender/i.test(purpose)) return false;
  const agent = request.headers.get("user-agent") ?? "";
  return agent !== "" && !NOT_A_PERSON.test(agent);
}

/** The version in a DMG URL like `.../DiskCleaner-1.0.dmg`, or "unknown". */
export function versionOf(downloadUrl: string): string {
  const match = /-(\d{1,4}(?:\.\d{1,4}){0,3})\.dmg$/.exec(new URL(downloadUrl).pathname);
  return match?.[1] ?? "unknown";
}

export async function countDownload(db: D1Database, version: string): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  await db
    .prepare(
      `INSERT INTO downloads (day, version, count) VALUES (?1, ?2, 1)
       ON CONFLICT (day, version) DO UPDATE SET count = count + 1`,
    )
    .bind(day, version)
    .run();
}
