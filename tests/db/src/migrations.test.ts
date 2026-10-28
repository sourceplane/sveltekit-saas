import { describe, expect, it } from "vitest";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { PGlite } from "@electric-sql/pglite";
import { manifest } from "@saas/db/manifest";
import { runMigrations } from "@saas/db/runner";
import type { MigrationAdapter } from "@saas/db/runner";
import { SUPABASE_PRELUDE } from "./supabase";

const migrationsDir = path.resolve(__dirname, "../../../packages/db/src/migrations");

// scosman/CMSaasStarter's supabase/migrations at 2e61406, by sha256: the app
// migrations are upstream's files byte for byte.
const UPSTREAM = {
  "010_initial": "734210df1340e56e55fdff6eb71161f562814725030a1fde06b88456639e987c", // 20240730010101_initial.sql
  "020_add_unsubscribed_to_profiles": "d45389f3e51aa9e3ea76c3fb2ecb9175cda644a201332282480fddb847150352", // 20240731051052_add_unsubscribed_to_profiles.sql
};

// The runner's adapter over an in-process Postgres (PGlite): the same calls
// the Management API adapter makes, one statement batch per call.
function pgliteAdapter(db: PGlite): MigrationAdapter {
  return {
    async connect() {},
    async disconnect() {},
    async acquireAdvisoryLock() { return true; },
    async releaseAdvisoryLock() {},
    async getAppliedMigrations() {
      try {
        const { rows } = await db.query<{ id: string; context: string; checksum: string; applied_at: string }>(
          "select id, context, checksum, applied_at::text as applied_at from _migrations.applied order by id",
        );
        return rows;
      } catch (e) {
        if (String(e).includes("does not exist")) return [];
        throw e;
      }
    },
    async beginTransaction() {},
    async commitTransaction() {},
    async rollbackTransaction() {},
    async executeSql(sql) { await db.exec(sql); },
    async recordMigration(entry) {
      await db.query(
        "insert into _migrations.applied (id, context, checksum) values ($1, $2, $3) on conflict (id) do nothing",
        [entry.id, entry.context, entry.checksum],
      );
    },
  };
}

describe("the migration manifest (packages/db)", () => {
  it("starts with the control migration and names every file with its checksum", () => {
    expect(manifest.migrations[0]?.id).toBe("000_control_baseline");
    for (const entry of manifest.migrations) {
      const file = readFileSync(path.join(migrationsDir, entry.path));
      expect(createHash("sha256").update(file).digest("hex"), entry.id).toBe(entry.checksum);
    }
  });

  it("applies upstream's two migrations, byte for byte, in upstream's order", () => {
    const app = manifest.migrations.filter((m) => m.context === "app");
    expect(app.map((m) => m.id)).toEqual(Object.keys(UPSTREAM));
    for (const entry of app) expect(entry.checksum, entry.id).toBe(UPSTREAM[entry.id as keyof typeof UPSTREAM]);
  });

  it("plans every migration as pending offline", async () => {
    const result = await runMigrations(manifest, { mode: "plan", migrationsDir, adapter: null });
    expect(result.failed).toBeNull();
    expect(result.applied).toEqual(manifest.migrations.map((m) => m.id));
  });

  it("applies every migration once to a Supabase-shaped Postgres, and a second apply applies nothing", async () => {
    const db = new PGlite();
    await db.exec(SUPABASE_PRELUDE);
    const first = await runMigrations(manifest, { mode: "apply", migrationsDir, adapter: pgliteAdapter(db) });
    expect(first.failed).toBeNull();
    expect(first.applied).toEqual(manifest.migrations.map((m) => m.id));
    const again = await runMigrations(manifest, { mode: "apply", migrationsDir, adapter: pgliteAdapter(db) });
    expect(again.failed).toBeNull();
    expect(again.applied).toEqual([]);
    expect(again.skipped).toEqual(manifest.migrations.map((m) => m.id));
  }, 60_000);
});
