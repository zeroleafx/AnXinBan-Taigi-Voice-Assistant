-- Device identities must be authenticated (anonymous Auth is suitable for elders).
create table public.family_device_links (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 elder_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 constraint different_users check(owner_id <> elder_id),
 unique(owner_id, elder_id)
);
create index family_device_links_elder_idx on public.family_device_links(elder_id);
alter table public.family_device_links enable row level security;
revoke all on public.family_device_links from anon, authenticated;
grant select, delete on public.family_device_links to authenticated;
create policy participants_read on public.family_device_links for select to authenticated
 using ((select auth.uid()) in (owner_id, elder_id));
create policy participants_unlink on public.family_device_links for delete to authenticated
 using ((select auth.uid()) in (owner_id, elder_id));
-- No client INSERT: a validated pairing operation must establish a link.
create policy paired_elders_read on public.family_settings for select to authenticated
 using (exists (select 1 from public.family_device_links l
 where l.owner_id = family_settings.owner_id and l.elder_id = (select auth.uid())));
