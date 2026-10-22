import { z } from "zod";

/** Everything the app may send. Anything else is rejected, so nothing personal can slip in. */
const base = {
  installId: z.uuid(),
  appVersion: z.string().regex(/^\d{1,4}(\.\d{1,4}){0,3}$/),
  osVersion: z.string().regex(/^\d{1,3}(\.\d{1,3}){0,2}$/),
  arch: z.enum(["arm64", "x86_64"]),
};

const sections = [
  "apps",
  "applications",
  "xcode",
  "ides",
  "packages",
  "simulators",
  "docker",
  "largeFiles",
  "duplicates",
  "inspector",
] as const;

export const eventSchema = z.discriminatedUnion("event", [
  z.strictObject({ ...base, event: z.literal("first_launch") }),
  z.strictObject({ ...base, event: z.literal("app_open") }),
  z.strictObject({
    ...base,
    event: z.literal("cleanup"),
    section: z.enum(sections),
    // Up to 100 TB per cleanup — anything larger is a bug or abuse.
    bytesCleaned: z.int().min(0).max(100_000_000_000_000),
  }),
]);

export type TelemetryEvent = z.infer<typeof eventSchema>;

/** Largest request body accepted, in bytes. Real events are ~200 bytes. */
export const MAX_BODY_BYTES = 4096;
