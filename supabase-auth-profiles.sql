-- First Supabase Auth migration for the hospitalist scheduler.
--
-- This creates the app profile row that links a Supabase Auth user to
-- application-level permissions. It intentionally does not enable RLS yet.
-- Enable RLS after the app is fully using Supabase Auth tokens.

create table if not exists profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  is_master_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists profiles_email_idx on profiles(email);

alter table profiles
  add column if not exists group_id text,
  add column if not exists group_name text,
  add column if not exists doc_id text;

-- After creating your Auth user in Authentication > Users, copy that user's UID
-- and run an insert like this:
--
-- insert into profiles (
--   user_id,
--   email,
--   display_name,
--   is_master_admin
-- )
-- values (
--   'PASTE-AUTH-USER-UID-HERE',
--   'your.email@example.com',
--   'Christopher March',
--   true
-- )
-- on conflict (user_id) do update
-- set
--   email = excluded.email,
--   display_name = excluded.display_name,
--   is_master_admin = true;
