#!/usr/bin/env node
// Deploy-time wiring for deployables whose composition has no wire-live step
// (cloudflare-workers-assets-turbo). Reads the wiring documents the infra
// components lease-publish — WIRING_<COMPONENT>_<ENV> in the job env, each a
// JSON document — into a temp dir and renders the wrangler template with
// render.mjs. Fails loudly on any unresolved token.
//
//   node live.mjs --template wrangler.template.jsonc --out wrangler.jsonc \
//     --components cloudflare-kv,cloudflare-r2 --env stage \
//     [--fixture wiring.fixture.json --fixture-envs dev]
//
// A VERIFY-ONLY ENVIRONMENT HAS NO WIRING DOCUMENT. `dev` deploys nothing and
// no infra component applies there, so nothing ever publishes
// WIRING_<COMPONENT>_DEV; its lane still builds and dry-deploys the Worker.
// `--fixture-envs` names those environments, and for them — only them — a
// missing document renders from the committed fixture instead. Every other
// environment needs the real document: a deploy job resolves it before its
// first step (the component's secretEnv), so a missing one here is a real
// fault, never a reason to deploy a placeholder id.
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

const template = arg("template");
const out = arg("out");
const components = (arg("components") ?? "").split(",").filter(Boolean);
const env = arg("env");
const envs = (arg("envs") ?? env ?? "stage,prod").split(",").filter(Boolean);
const fixture = arg("fixture");
const fixtureEnvs = new Set((arg("fixture-envs") ?? "").split(",").filter(Boolean));
if (!template || !out || components.length === 0 || (fixtureEnvs.size > 0 && !fixture)) {
  console.error(
    "usage: live.mjs --template <file> --out <file> --components a,b (--env stage | --envs stage,prod) [--fixture <file> --fixture-envs dev]",
  );
  process.exit(2);
}

const fixtureMap = fixture ? JSON.parse(fs.readFileSync(fixture, "utf8")) : {};
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "wiring-"));
const missing = [];
const fromFixture = [];
for (const component of components) {
  for (const env of envs) {
    const key = `WIRING_${component.toUpperCase().replace(/-/g, "_")}_${env.toUpperCase()}`;
    let value = process.env[key];
    if (!value && fixtureEnvs.has(env) && fixtureMap[`${component}/${env}`]) {
      value = JSON.stringify(fixtureMap[`${component}/${env}`]);
      fromFixture.push(`${component}/${env}`);
    }
    if (!value) {
      missing.push(key);
      continue;
    }
    fs.writeFileSync(path.join(dir, `${component}__${env}.json`), value);
  }
}
if (missing.length > 0) {
  console.error("wire: missing wiring documents in the environment:");
  for (const m of missing) console.error(`  ${m}`);
  fs.rmSync(dir, { recursive: true, force: true });
  process.exit(1);
}
for (const f of fromFixture) {
  console.log(`wire: ${f} is verify-only — rendered from ${path.basename(fixture)}, not a published document`);
}

// A single-environment render (the workers-assets composition deploys one
// environment per job, with no wrangler `--env`): `__ENV__` in the template
// becomes that environment before the wiring tokens are resolved.
let templatePath = template;
if (env) {
  const text = fs.readFileSync(template, "utf8").replace(/__ENV__/g, env);
  templatePath = path.join(dir, path.basename(template));
  fs.writeFileSync(templatePath, text);
}

const render = path.join(path.dirname(fileURLToPath(import.meta.url)), "render.mjs");
const result = spawnSync(
  process.execPath,
  [render, "--template", templatePath, "--out", out, "--secrets-dir", dir],
  { stdio: "inherit" },
);
fs.rmSync(dir, { recursive: true, force: true });
process.exit(result.status ?? 1);
