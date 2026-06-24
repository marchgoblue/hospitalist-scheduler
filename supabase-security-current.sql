-- Current security reference for Hospitalist Scheduler.
--
-- This app uses Supabase Auth plus application tables:
--   profiles    = one row per auth.users user
--   memberships = user -> group -> role -> optional provider doc_id
--   groups      = one row per hospitalist site
--
-- The old custom users/password_hash login is intentionally not used.
-- Review before running in an existing project because policy names may differ.

create table if not exists groups (
  id text primary key,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  is_master_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists memberships (
  user_id uuid not null references auth.users(id) on delete cascade,
  group_id text not null references groups(id) on update cascade on delete cascade,
  role text not null check (role in ('admin','physician')),
  doc_id text,
  created_at timestamptz not null default now(),
  primary key (user_id, group_id)
);

alter table versions
  add column if not exists group_id text not null default 'main';

create index if not exists profiles_email_idx on profiles(email);
create index if not exists memberships_group_id_idx on memberships(group_id);
create index if not exists memberships_user_id_idx on memberships(user_id);
create index if not exists versions_group_id_idx on versions(group_id);

create or replace function public.is_master_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from profiles p
    where p.user_id = auth.uid()
      and p.is_master_admin = true
  );
$$;

create or replace function public.is_group_member(gid text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_master_admin()
    or exists (
      select 1
      from memberships m
      where m.user_id = auth.uid()
        and m.group_id = gid
    );
$$;

create or replace function public.is_group_admin(gid text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_master_admin()
    or exists (
      select 1
      from memberships m
      where m.user_id = auth.uid()
        and m.group_id = gid
        and m.role = 'admin'
    );
$$;

alter table profiles enable row level security;
alter table memberships enable row level security;
alter table groups enable row level security;
alter table schedule_data enable row level security;
alter table versions enable row level security;

drop policy if exists profiles_select_self_or_master on profiles;
create policy profiles_select_self_or_master
on profiles for select
using (user_id = auth.uid() or public.is_master_admin());

drop policy if exists profiles_update_self_or_master on profiles;
create policy profiles_update_self_or_master
on profiles for update
using (user_id = auth.uid() or public.is_master_admin())
with check (user_id = auth.uid() or public.is_master_admin());

drop policy if exists memberships_select_relevant on memberships;
create policy memberships_select_relevant
on memberships for select
using (
  user_id = auth.uid()
  or public.is_master_admin()
  or public.is_group_admin(group_id)
);

drop policy if exists memberships_write_admin on memberships;
create policy memberships_write_admin
on memberships for all
using (public.is_master_admin() or public.is_group_admin(group_id))
with check (public.is_master_admin() or public.is_group_admin(group_id));

drop policy if exists groups_select_member on groups;
create policy groups_select_member
on groups for select
using (public.is_group_member(id));

drop policy if exists groups_write_master on groups;
create policy groups_write_master
on groups for all
using (public.is_master_admin())
with check (public.is_master_admin());

drop policy if exists schedule_data_select_member on schedule_data;
create policy schedule_data_select_member
on schedule_data for select
using (public.is_group_member(id));

drop policy if exists schedule_data_write_admin on schedule_data;
create policy schedule_data_write_admin
on schedule_data for all
using (public.is_group_admin(id))
with check (public.is_group_admin(id));

drop policy if exists versions_select_member on versions;
create policy versions_select_member
on versions for select
using (public.is_group_member(group_id));

drop policy if exists versions_write_admin on versions;
create policy versions_write_admin
on versions for all
using (public.is_group_admin(group_id))
with check (public.is_group_admin(group_id));
