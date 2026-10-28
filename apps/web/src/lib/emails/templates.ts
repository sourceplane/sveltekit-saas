// The email templates, precompiled.
//
// Upstream compiled each .hbs file with handlebars.compile() when an email was
// sent. That generates JavaScript from a string, which Workers refuse. So the
// Vite plugin in vite.config.ts precompiles every template at build
// (`?hbs` imports) into a template spec, and this renders it with the
// Handlebars runtime alone, which generates no code. The templates and their
// output are unchanged.
const compiled = import.meta.glob<(context: Record<string, string>) => string>(
  "./*.hbs",
  { query: "?hbs", import: "default", eager: true },
)

export const templateNames = Object.keys(compiled).map((p) =>
  p.replace(/^\.\//, "").replace(/\.hbs$/, ""),
)

// Renders `<name>.hbs` (e.g. "welcome_email_text"), or throws if there is no
// such template.
export const renderTemplate = (
  name: string,
  properties: Record<string, string>,
): string => {
  const template = compiled[`./${name}.hbs`]
  if (!template) {
    throw new Error(`no email template ${name}.hbs`)
  }
  return template(properties)
}
