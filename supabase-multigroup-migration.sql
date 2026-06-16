-- Multi-group storage support for the hospitalist scheduler.
--
-- Current app behavior remains compatible with the existing "main" group.
-- Future groups should get a stable group_id such as "athens", "st-marys",
-- or a generated UUID-like slug. Users with no group_id default to "main".

create table if not exists groups (
  id text primary key,
  name text not null,
  created_at timestamptz not null default now()
);

insert into groups (id, name)
values ('main', 'Main')
on conflict (id) do nothing;

alter table users
  add column if not exists group_id text not null default 'main',
  add column if not exists group_name text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'users_group_id_fkey'
  ) then
    alter table users
      add constraint users_group_id_fkey
      foreign key (group_id) references groups(id)
      on update cascade
      on delete restrict;
  end if;
end $$;

alter table versions
  add column if not exists group_id text not null default 'main';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'versions_group_id_fkey'
  ) then
    alter table versions
      add constraint versions_group_id_fkey
      foreign key (group_id) references groups(id)
      on update cascade
      on delete restrict;
  end if;
end $$;

create index if not exists users_group_id_idx on users(group_id);
create index if not exists versions_group_id_idx on versions(group_id);

-- The existing schedule_data table can store one row per group using its id:
--   schedule_data.id = groups.id
--
-- Existing data should already live at schedule_data.id = 'main'.
-- To onboard a new group, create a groups row, create admin users with that
-- group_id, then the app will save that group's blank/imported schedule into
-- schedule_data.id = group_id on first save.
