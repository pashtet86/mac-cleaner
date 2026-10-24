import { describe, expect, it } from "vitest";
import { isCountable, versionOf } from "../src/downloads";

const browser = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";
const get = (headers: Record<string, string> = {}, method = "GET") =>
  new Request("https://machealthapps.com/download", { method, headers });

describe("isCountable", () => {
  it("counts a person clicking the link", () => {
    expect(isCountable(get({ "user-agent": browser }))).toBe(true);
  });

  it("ignores link previews, crawlers and prefetches", () => {
    expect(isCountable(get({ "user-agent": "Slackbot-LinkExpanding 1.0" }))).toBe(false);
    expect(isCountable(get({ "user-agent": "Mozilla/5.0 (compatible; Googlebot/2.1)" }))).toBe(false);
    expect(isCountable(get({ "user-agent": browser, "sec-purpose": "prefetch" }))).toBe(false);
    expect(isCountable(get())).toBe(false);
    expect(isCountable(get({ "user-agent": browser }, "HEAD"))).toBe(false);
  });
});

describe("versionOf", () => {
  it("reads the version from the DMG name", () => {
    expect(versionOf("https://downloads.machealthapps.com/DiskCleaner-1.0.dmg")).toBe("1.0");
    expect(versionOf("https://downloads.machealthapps.com/DiskCleaner-1.2.3.dmg")).toBe("1.2.3");
  });

  it("falls back to unknown for anything else", () => {
    expect(versionOf("https://downloads.machealthapps.com/DiskCleaner.dmg")).toBe("unknown");
  });
});
