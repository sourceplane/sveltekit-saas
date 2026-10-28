import type { MigrationManifest } from "./types.js";

// Every migration the runner applies, in order, with the sha256 of its file.
// `pnpm --filter @saas/db run manifest:check` verifies the checksums;
// `manifest:fix` rewrites them after a migration file changes (only ever
// before that migration has been applied anywhere — an applied migration's
// checksum is immutable).
export const manifest: MigrationManifest = {
  version: 1,
  migrations: [
    {
      id: "000_control_baseline",
      context: "control",
      path: "000_control/up.sql",
      checksum:
        "2a5d7f30684c99e3ff441ca8a2c38038dedd1bab4db4a40e92cd36bb22be297f",
      description:
        "Baseline control migration — creates the migration tracking schema",
    },
    {
      id: "010_initial",
      context: "app",
      path: "010_initial/up.sql",
      checksum:
        "734210df1340e56e55fdff6eb71161f562814725030a1fde06b88456639e987c",
      description:
        "The template's schema (supabase/migrations/20240730010101_initial.sql, verbatim): profiles, stripe_customers and contact_requests with row-level security, the trigger that creates a profile for every new auth.users row, and the avatars storage bucket with its policies",
    },
    {
      id: "020_add_unsubscribed_to_profiles",
      context: "app",
      path: "020_add_unsubscribed_to_profiles/up.sql",
      checksum:
        "d45389f3e51aa9e3ea76c3fb2ecb9175cda644a201332282480fddb847150352",
      description:
        "profiles.unsubscribed (supabase/migrations/20240731051052_add_unsubscribed_to_profiles.sql, verbatim): the email opt-out the account settings write",
    },
  ],
};
