import { sveltekit } from "@sveltejs/kit/vite"
import { defineConfig, type Plugin } from "vitest/config"
import Handlebars from "handlebars"
import fs from "node:fs"
import { buildAndCacheSearchIndex } from "./src/lib/build_index"

// The site's public origin, which `$env/static/public` inlines into the
// sitemap, the RSS feed and the emails (src/config.ts). A deploy sets it to
// the environment's SITE_URL or its workers.dev URL (component.yaml); a local
// build leaves it empty and config.ts falls back to the dev server's origin.
// `$env/static/public` refuses a name that is not set at all, hence the
// default here.
process.env.PUBLIC_SITE_URL ??= ""

// Workers refuse to generate code from strings, so email templates are
// precompiled here: `import x from "./t.hbs?hbs"` is the template, ready to
// render with the Handlebars runtime alone (src/lib/emails/templates.ts).
const precompiledHandlebars = (): Plugin => ({
  name: "precompiled-handlebars",
  enforce: "pre",
  load(id) {
    const [file, query] = id.split("?")
    if (!file.endsWith(".hbs") || query !== "hbs") return null
    const spec = Handlebars.precompile(fs.readFileSync(file, "utf8"))
    return `import Handlebars from "handlebars/runtime"\nexport default Handlebars.template(${spec})\n`
  },
})

export default defineConfig({
  plugins: [
    precompiledHandlebars(),
    sveltekit(),
    {
      name: "vite-build-search-index",
      writeBundle: {
        order: "post",
        sequential: false,
        handler: async () => {
          console.log("Building search index...")
          await buildAndCacheSearchIndex()
        },
      },
    },
  ],
  test: {
    include: ["src/**/*.{test,spec}.{js,ts}"],
    globals: true, /// allows to skip import of test functions like `describe`, `it`, `expect`, etc.
  },
})
