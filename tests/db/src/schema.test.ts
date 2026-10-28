import { beforeAll, describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { PGlite } from "@electric-sql/pglite";
import { manifest } from "@saas/db/manifest";
import { SUPABASE_PRELUDE } from "./supabase";

// The schema the app reads, as every migration db-migrate applies leaves it on
// a Supabase-shaped Postgres (PGlite, in process): the three tables with
// row-level security, the trigger that gives every new user a profile, the
// avatars bucket, and the profile policies — a user reads and writes their own
// row only, the anon key reads nothing, and the two server-only tables answer
// no API role at all (the app's server reaches them with the service-role key,
// which bypasses row-level security).
const migrationsDir = path.resolve(__dirname, "../../../packages/db/src/migrations");

async function migrated(): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(SUPABASE_PRELUDE);
  for (const entry of manifest.migrations) {
    await db.exec(readFileSync(path.join(migrationsDir, entry.path), "utf8"));
  }
  return db;
}

async function as<T>(db: PGlite, role: string, sub: string | null, fn: () => Promise<T>): Promise<T> {
  await db.exec(`set role ${role}`);
  await db.query("select set_config('request.jwt.claims', $1, false)", [sub ? JSON.stringify({ sub, role }) : ""]);
  try {
    return await fn();
  } finally {
    await db.exec("reset role");
    await db.query("select set_config('request.jwt.claims', '', false)");
  }
}

const ALICE = "00000000-0000-4000-8000-00000000a11c";
const BOB = "00000000-0000-4000-8000-000000000b0b";

describe("the schema after every migration", () => {
  let db: PGlite;
  beforeAll(async () => {
    db = await migrated();
    await db.query(
      "insert into auth.users (id, email, raw_user_meta_data) values ($1, 'alice@example.invalid', $2), ($3, 'bob@example.invalid', '{}')",
      [ALICE, JSON.stringify({ full_name: "Alice A", avatar_url: "https://example.invalid/a.png" }), BOB],
    );
  }, 60_000);

  it("has the template's three tables, each with row-level security", async () => {
    const { rows } = await db.query<{ relname: string; relrowsecurity: boolean }>(`
      select c.relname, c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relkind = 'r' order by c.relname`);
    expect(rows).toEqual([
      { relname: "contact_requests", relrowsecurity: true },
      { relname: "profiles", relrowsecurity: true },
      { relname: "stripe_customers", relrowsecurity: true },
    ]);
  });

  it("gives every new user a profile, from their sign-up metadata, subscribed to email", async () => {
    const { rows } = await db.query<{ id: string; full_name: string | null; avatar_url: string | null; unsubscribed: boolean }>(
      "select id, full_name, avatar_url, unsubscribed from profiles order by full_name nulls last",
    );
    expect(rows).toEqual([
      { id: ALICE, full_name: "Alice A", avatar_url: "https://example.invalid/a.png", unsubscribed: false },
      { id: BOB, full_name: null, avatar_url: null, unsubscribed: false },
    ]);
  });

  it("lets a signed-in user read and update their own profile, and nobody else's", async () => {
    const seen = await as(db, "authenticated", ALICE, () => db.query<{ id: string }>("select id from profiles"));
    expect(seen.rows.map((r) => r.id)).toEqual([ALICE]);
    await as(db, "authenticated", ALICE, () =>
      db.query("update profiles set company_name = 'Acme', unsubscribed = true where id = $1", [ALICE]));
    const touched = await as(db, "authenticated", ALICE, () =>
      db.query<{ n: number }>("with u as (update profiles set company_name = 'Hijack' where id = $1 returning 1) select count(*)::int as n from u", [BOB]));
    expect(touched.rows[0]!.n).toBe(0);
    const { rows } = await db.query<{ id: string; company_name: string | null; unsubscribed: boolean }>(
      "select id, company_name, unsubscribed from profiles order by id");
    expect(rows).toEqual([
      { id: BOB, company_name: null, unsubscribed: false },
      { id: ALICE, company_name: "Acme", unsubscribed: true },
    ]);
  });

  it("refuses a profile written for somebody else", async () => {
    await db.query("delete from profiles where id = $1", [BOB]);
    await expect(
      as(db, "authenticated", ALICE, () => db.query("insert into profiles (id, full_name) values ($1, 'not me')", [BOB])),
    ).rejects.toThrow(/row-level security/);
  });

  it("shows the anon key nothing, and the server-only tables to no API role", async () => {
    await db.query("insert into contact_requests (email, message_body) values ('x@example.invalid', 'hi')");
    await db.query("insert into stripe_customers (user_id, stripe_customer_id) values ($1, 'cus_1')", [ALICE]);
    for (const [role, sub] of [["anon", null], ["authenticated", ALICE]] as const) {
      for (const table of ["contact_requests", "stripe_customers"]) {
        const { rows } = await as(db, role, sub, () => db.query<{ n: number }>(`select count(*)::int as n from ${table}`));
        expect(rows[0]!.n, `${role} on ${table}`).toBe(0);
      }
    }
    const anonProfiles = await as(db, "anon", null, () => db.query<{ n: number }>("select count(*)::int as n from profiles"));
    expect(anonProfiles.rows[0]!.n).toBe(0);
  });

  it("creates the avatars bucket, readable by anyone", async () => {
    const { rows } = await db.query<{ id: string; name: string }>("select id, name from storage.buckets");
    expect(rows).toEqual([{ id: "avatars", name: "avatars" }]);
    const { rows: policies } = await db.query<{ policyname: string; cmd: string }>(
      "select policyname, cmd from pg_policies where schemaname = 'storage' order by policyname");
    expect(policies).toEqual([
      { policyname: "Anyone can upload an avatar.", cmd: "INSERT" },
      { policyname: "Avatar images are publicly accessible.", cmd: "SELECT" },
    ]);
  });
});
