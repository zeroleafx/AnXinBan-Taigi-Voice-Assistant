create table public.family_settings (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 label text not null check(length(label) between 1 and 100),
 kind text not null check(kind in ('contact','place')),
 aliases text[] not null default '{}',
 value text not null check(length(value) between 1 and 1000),
 updated_at timestamptz not null default now()
);
create index family_settings_owner_idx on public.family_settings(owner_id);
alter table public.family_settings enable row level security;
revoke all on public.family_settings from anon;
grant select,insert,update,delete on public.family_settings to authenticated;
create policy owner_select on public.family_settings for select to authenticated using(owner_id = (select auth.uid()));
create policy owner_insert on public.family_settings for insert to authenticated with check(owner_id = (select auth.uid()));
create policy owner_update on public.family_settings for update to authenticated using(owner_id = (select auth.uid())) with check(owner_id = (select auth.uid()));
create policy owner_delete on public.family_settings for delete to authenticated using(owner_id = (select auth.uid()));
comment on table public.family_settings is 'Family-owned contacts and named places. Device pairing and elder access are not enabled yet.';
