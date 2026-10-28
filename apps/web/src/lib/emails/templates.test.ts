import { describe, it, expect } from "vitest"
import Handlebars from "handlebars"
import fs from "node:fs"
import path from "node:path"
import { renderTemplate, templateNames } from "./templates"

const dir = path.resolve("src/lib/emails")

describe("precompiled email templates", () => {
  it("cover every .hbs file", () => {
    const files = fs
      .readdirSync(dir)
      .filter((f) => f.endsWith(".hbs"))
      .map((f) => f.replace(/\.hbs$/, ""))
      .sort()
    expect([...templateNames].sort()).toEqual(files)
    expect(files).toEqual(["welcome_email_html", "welcome_email_text"])
  })

  it("render exactly what handlebars.compile rendered", () => {
    const props = {
      companyName: "Acme & Co <b>",
      WebsiteBaseUrl: "https://acme.example.com",
    }
    for (const name of templateNames) {
      const source = fs.readFileSync(path.join(dir, `${name}.hbs`), "utf8")
      expect(renderTemplate(name, props)).toBe(
        Handlebars.compile(source)(props),
      )
    }
  })

  it("refuse a template that does not exist", () => {
    expect(() => renderTemplate("no_such_email", {})).toThrow(/no_such_email/)
  })

  it("need no code generation at runtime: no handlebars.compile in the app", () => {
    const walk = (d: string): string[] =>
      fs.readdirSync(d, { withFileTypes: true }).flatMap((e) => {
        const p = path.join(d, e.name)
        return e.isDirectory() ? walk(p) : [p]
      })
    const offenders = walk(path.resolve("src"))
      .filter((p) => /\.(ts|js|svelte)$/.test(p) && !p.endsWith(".test.ts"))
      .filter((p) =>
        fs
          .readFileSync(p, "utf8")
          .split("\n")
          .some((l) => !/^\s*(\/\/|\*)/.test(l) && /\.compile\(/.test(l)),
      )
    expect(offenders).toEqual([])
  })
})
