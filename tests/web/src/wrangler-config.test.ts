// The Worker's config, held to what the build and the deploy rely on.
import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { describe, expect, it } from "vitest";

const app = path.resolve(__dirname, "../../../apps/web");
const read = (rel: string) => fs.readFileSync(path.join(app, rel), "utf8");

// JSONC → JSON, as tooling/wire/with-vars.mjs reads it.
function parse(text: string): Record<string, unknown> {
  const noComments = text.replace(/("(?:\\.|[^"\\])*")|\/\/[^\n]*|\/\*[\s\S]*?\*\//g, (_m, str) => str ?? "");
  return JSON.parse(noComments.replace(/,(\s*[}\]])/g, "$1"));
}

describe("wrangler.jsonc", () => {
  it("is the committed fixture render of wrangler.template.jsonc", () => {
    const out = path.join(fs.mkdtempSync(path.join(os.tmpdir(), "wire-")), "wrangler.jsonc");
    execFileSync("node", [
      "../../tooling/wire/render.mjs",
      "--template", "wrangler.template.jsonc",
      "--out", out,
      "--map", "wiring.fixture.json",
      "--env", "stage",
    ], { cwd: app, stdio: "pipe" });
    expect(read("wrangler.jsonc")).toBe(fs.readFileSync(out, "utf8"));
  });

  it("deploys adapter-cloudflare's Worker with its static output as assets", () => {
    const c = parse(read("wrangler.jsonc"));
    expect(c.main).toBe(".svelte-kit/cloudflare/_worker.js");
    expect(c.assets).toEqual({ directory: ".svelte-kit/cloudflare", binding: "ASSETS" });
    expect(c.compatibility_flags).toContain("nodejs_compat");
  });

  it("carries the project's URL and anon key as vars, rendered per environment, and no secret", () => {
    const t = parse(read("wrangler.template.jsonc"));
    expect(t.vars).toEqual({
      PUBLIC_SUPABASE_URL: "@@wiring(supabase/__ENV__:supabase_url)@@",
      PUBLIC_SUPABASE_ANON_KEY: "@@wiring(supabase/__ENV__:supabase_anon_key)@@",
    });
    for (const k of Object.keys(t.vars as object)) expect(k.startsWith("PUBLIC_")).toBe(true);
  });

  it("has a fixture for every environment the build renders", () => {
    const f = JSON.parse(read("wiring.fixture.json"));
    for (const env of ["dev", "stage", "prod"]) {
      expect(f[`supabase/${env}`]).toEqual({
        supabase_url: expect.stringMatching(/^https:\/\/[a-z-]+\.supabase\.co$/),
        supabase_anon_key: expect.any(String),
      });
    }
  });
});

describe("the app's secrets", () => {
  // $env/static/private would inline a secret into the server bundle at
  // build time. Every secret is a Worker secret, read at request time.
  it("are never read through $env/static/private", () => {
    const hits: string[] = [];
    const walk = (dir: string) => {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walk(p);
        else if (/\.(ts|js|svelte)$/.test(e.name) && fs.readFileSync(p, "utf8").includes("$env/static/private")) {
          hits.push(path.relative(app, p));
        }
      }
    };
    walk(path.join(app, "src"));
    expect(hits).toEqual([]);
  });

  it("are the five the component hands the Worker, and none reaches the build", () => {
    const component = read("component.yaml");
    const names = ["PRIVATE_SUPABASE_SERVICE_ROLE", "PRIVATE_STRIPE_API_KEY", "PRIVATE_RESEND_API_KEY", "PRIVATE_ADMIN_EMAIL", "PRIVATE_FROM_ADMIN_EMAIL"];
    const build = component.match(/^\s+buildCommand: (.*)$/m)?.[1] ?? "";
    for (const n of names) {
      expect(component).toMatch(new RegExp(`^\\s+${n}: "secret://`, "m"));
      expect(build).toContain(`-u ${n} `);
      expect(build).toContain(`--secret ${n}`);
    }
  });
});
