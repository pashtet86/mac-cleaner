import { countDownload, isCountable, versionOf } from "./downloads";

/** The website Worker: static files from ../website, plus a counted /download link. */
interface SiteEnv {
  ASSETS: Fetcher;
  DB: D1Database;
  /** The current DMG, e.g. https://downloads.machealthapps.com/DiskCleaner-1.0.dmg. Fixed config, never user input. */
  DOWNLOAD_URL: string;
  /** GA4 Measurement ID ("G-…"). Empty or unset: no analytics and no consent banner. */
  GA_MEASUREMENT_ID?: string;
}

const MEASUREMENT_ID = /^G-[A-Z0-9]{4,16}$/;

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/download" || url.pathname === "/download/") {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return new Response("method not allowed", { status: 405 });
      }
      if (isCountable(request)) {
        // Counting must never delay or break the download.
        ctx.waitUntil(
          countDownload(env.DB, versionOf(env.DOWNLOAD_URL)).catch((e: unknown) =>
            console.error(JSON.stringify({ message: "download count failed", error: String(e) })),
          ),
        );
      }
      return new Response(null, {
        status: 302,
        headers: { Location: env.DOWNLOAD_URL, "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" },
      });
    }
    if (url.pathname === "/analytics.js") return analyticsScript(request, env);
    return env.ASSETS.fetch(request);
  },
} satisfies ExportedHandler<SiteEnv>;

/** The static analytics.js with the configured Measurement ID in front of it. */
async function analyticsScript(request: Request, env: SiteEnv): Promise<Response> {
  const asset = await env.ASSETS.fetch(request);
  if (!asset.ok) return asset;
  const id = env.GA_MEASUREMENT_ID?.trim() ?? "";
  // Validated so the variable can only ever produce a quoted ID, never code.
  const prefix = MEASUREMENT_ID.test(id) ? `self.GA_MEASUREMENT_ID = ${JSON.stringify(id)};\n` : "";
  const headers = new Headers(asset.headers);
  headers.set("Content-Type", "text/javascript; charset=utf-8");
  headers.set("Cache-Control", "public, max-age=300");
  headers.delete("ETag");
  headers.delete("Content-Length");
  return new Response(prefix + (await asset.text()), { status: 200, headers });
}
