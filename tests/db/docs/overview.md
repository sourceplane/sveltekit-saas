# db-tests

The migrations' tests (the manifest, upstream's two migrations byte for byte, and the schema they leave on a Supabase-shaped Postgres in process — the profile trigger, the bucket and row-level security)

The test suite for **db**. It deploys nothing: its lane installs, builds and runs the tests.

|              |                      |
| ------------ | -------------------- |
| Type         | `turbo-package`      |
| Source       | `tests/db`           |
| Package      | `@app/db-tests`      |
| Environments | `dev`: `quick-check` |

## Depends on

- (none)

## Depended on by

- (none)
