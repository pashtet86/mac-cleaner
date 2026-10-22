import { describe, expect, it } from "vitest";
import { eventSchema } from "../src/schema";

const base = {
  installId: "3f0c6f1e-8a4b-4c2d-9e7f-1a2b3c4d5e6f",
  appVersion: "1.2.0",
  osVersion: "26.1",
  arch: "arm64",
};

describe("eventSchema", () => {
  it("accepts the events the app sends", () => {
    expect(eventSchema.safeParse({ ...base, event: "first_launch" }).success).toBe(true);
    expect(eventSchema.safeParse({ ...base, event: "app_open" }).success).toBe(true);
    expect(
      eventSchema.safeParse({ ...base, event: "cleanup", section: "xcode", bytesCleaned: 4_200_000_000 }).success,
    ).toBe(true);
  });

  it("rejects unknown fields so nothing personal can be smuggled in", () => {
    expect(eventSchema.safeParse({ ...base, event: "app_open", hostName: "Someones-MacBook" }).success).toBe(false);
    expect(eventSchema.safeParse({ ...base, event: "cleanup", section: "xcode", bytesCleaned: 1, path: "~/x" }).success).toBe(false);
  });

  it("rejects malformed values", () => {
    expect(eventSchema.safeParse({ ...base, installId: "not-a-uuid", event: "app_open" }).success).toBe(false);
    expect(eventSchema.safeParse({ ...base, appVersion: "1.0; DROP TABLE events", event: "app_open" }).success).toBe(false);
    expect(eventSchema.safeParse({ ...base, arch: "ppc", event: "app_open" }).success).toBe(false);
    expect(eventSchema.safeParse({ ...base, event: "cleanup", section: "xcode", bytesCleaned: -1 }).success).toBe(false);
    expect(eventSchema.safeParse({ ...base, event: "cleanup", section: "/etc", bytesCleaned: 1 }).success).toBe(false);
    expect(eventSchema.safeParse({ ...base, event: "uninstall" }).success).toBe(false);
  });

  it("requires cleanup details only on cleanup events", () => {
    expect(eventSchema.safeParse({ ...base, event: "cleanup" }).success).toBe(false);
    expect(eventSchema.safeParse({ ...base, event: "app_open", bytesCleaned: 1 }).success).toBe(false);
  });
});
