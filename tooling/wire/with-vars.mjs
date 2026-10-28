#!/usr/bin/env node
// Run a command with a wrangler config's `vars` in its environment
// (zero-dependency).
//
//   node with-vars.mjs --config wrangler.jsonc -- vite build
//
// SvelteKit's `$env/static/public` is inlined at BUILD time, into the browser
// bundle and the Worker alike, from the build's environment. The Worker's own
// `vars` are only there at request time. So the build reads them from the
// config it is about to deploy — the render tooling/wire just wrote for this
// environment (from the wiring document on stage and prod, the fixture
// otherwise) — and the browser and the Worker always name the same Supabase
// project. A var in the config wins over the same name already in the
// environment: the render is what deploys.
//
// Only `vars` are read. Secrets never pass through here: they reach the Worker
// at request time (`$env/dynamic/private`), never a bundle.
import * as fs from "node:fs";
import { spawnSync } from "node:child_process";

const argv = process.argv.slice(2);
const sep = argv.indexOf("--");
const ci = argv.indexOf("--config");
if (sep < 0 || ci < 0 || ci > sep || !argv[ci + 1] || sep === argv.length - 1) {
  console.error("usage: with-vars.mjs --config <wrangler.jsonc> -- <command> [args…]");
  process.exit(2);
}
const configPath = argv[ci + 1];
const command = argv.slice(sep + 1);

// JSONC → JSON: drop // and /* */ comments outside strings, then trailing commas.
function stripJsonc(text) {
  let out = "";
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      let j = i + 1;
      while (j < text.length && text[j] !== '"') j += text[j] === "\\" ? 2 : 1;
      out += text.slice(i, j + 1);
      i = j;
    } else if (c === "/" && text[i + 1] === "/") {
      while (i < text.length && text[i] !== "\n") i++;
      out += "\n";
    } else if (c === "/" && text[i + 1] === "*") {
      i = text.indexOf("*/", i + 2);
      if (i < 0) break;
      i++;
    } else {
      out += c;
    }
  }
  return out.replace(/,(\s*[}\]])/g, "$1");
}

const config = JSON.parse(stripJsonc(fs.readFileSync(configPath, "utf8")));
const vars = config.vars ?? {};
const env = { ...process.env };
for (const [k, v] of Object.entries(vars)) {
  if (typeof v !== "string") continue;
  if (/@@wiring\(/.test(v)) {
    console.error(`with-vars: ${configPath} var ${k} is an unrendered wiring token — render the config first`);
    process.exit(1);
  }
  env[k] = v;
}
console.log(`with-vars: ${Object.keys(vars).join(", ") || "no vars"} from ${configPath}`);
const result = spawnSync(command[0], command.slice(1), { stdio: "inherit", env, shell: false });
process.exit(result.status ?? 1);
