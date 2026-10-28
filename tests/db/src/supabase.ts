// What a Supabase project has before any migration runs, as far as this
// schema touches it: the API roles, `auth.users` and `auth.uid()`, and
// Storage's `buckets` and `objects`. Supabase creates these itself; a test
// database needs them for upstream's migration to mean here what it means
// there (a trigger on auth.users, policies keyed on auth.uid(), a bucket).
//
// auth.uid() reads the request's JWT subject the way Supabase's own does:
// PostgREST sets `request.jwt.claims` (and the older `request.jwt.claim.sub`)
// for every request it runs as `authenticated`.
export const SUPABASE_PRELUDE = `
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(
    coalesce(
      current_setting('request.jwt.claim.sub', true),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    ),
    ''
  )::uuid
$$;

create schema storage;
create table storage.buckets (
  id text primary key,
  name text not null unique,
  public boolean default false,
  created_at timestamptz default now()
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text,
  owner uuid,
  created_at timestamptz default now()
);
alter table storage.objects enable row level security;

grant usage on schema public, auth, storage to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
`;
