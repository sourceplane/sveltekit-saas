import adapter from "@sveltejs/adapter-cloudflare"
import { vitePreprocess } from "@sveltejs/vite-plugin-svelte"

/** @type {import('@sveltejs/kit').Config} */
const config = {
  kit: {
    // adapter-auto becomes adapter-cloudflare: the build emits one Worker
    // (.svelte-kit/cloudflare/_worker.js) with the pre-rendered pages and the
    // hashed assets beside it, which wrangler.jsonc deploys as Workers Static
    // Assets. `platformProxy` points `vite dev` at the same config, so the
    // dev server sees the vars and secrets the Worker does.
    adapter: adapter({ platformProxy: { configPath: "wrangler.jsonc" } }),
    // allow up to 150kb of style to be inlined with the HTML
    // Faster FCP (First Contentful Paint) by reducing the number of requests
    inlineStyleThreshold: 150000,
  },
  preprocess: vitePreprocess(),
}

export default config
