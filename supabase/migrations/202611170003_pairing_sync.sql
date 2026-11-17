create table public.family_snapshots (
 owner_id uuid primary key references auth.users(id) on delete cascade,
 entries jsonb not null default '[]' check(jsonb_typeof(entries)='array' and jsonb_array_length(entries)<=200),
 revision bigint not null default 1,
 updated_at timestamptz not null default now()
);
alter table public.family_snapshots enable row level security;
revoke all on public.family_snapshots from anon,authenticated;
grant select on public.family_snapshots to authenticated;
create policy snapshot_read on public.family_snapshots for select to authenticated using(owner_id=(select auth.uid()) or exists(select 1 from public.family_device_links l where l.owner_id=family_snapshots.owner_id and l.elder_id=(select auth.uid())));
create table public.family_invitations (
 token uuid primary key default gen_random_uuid(),
 owner_id uuid not null unique references auth.users(id) on delete cascade,
 expires_at timestamptz not null default now()+interval '10 minutes'
);
alter table public.family_invitations enable row level security;
revoke all on public.family_invitations from anon,authenticated;
alter table public.family_device_links add column applied_revision bigint not null default 0;
alter table public.family_device_links add column applied_at timestamptz;
create unique index one_family_per_elder on public.family_device_links(elder_id);
create function public.create_family_invitation() returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 insert into public.family_invitations(owner_id) values(auth.uid()) on conflict(owner_id) do update set token=gen_random_uuid(),expires_at=now()+interval '10 minutes' returning token into result;
 return result;
end $$;
create function public.accept_family_invitation(code uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare owner uuid;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 delete from public.family_invitations where token=code and expires_at>now() and owner_id<>auth.uid() returning owner_id into owner;
 if owner is null then raise exception 'Invalid or expired invitation'; end if;
 insert into public.family_device_links(owner_id,elder_id) values(owner,auth.uid());
 return owner;
end $$;
create function public.publish_family_settings(items jsonb, expected_revision bigint) returns bigint language plpgsql security definer set search_path='' as $$
declare current_revision bigint; new_revision bigint;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if jsonb_typeof(items)<>'array' or jsonb_array_length(items)>200 or octet_length(items::text)>200000 then raise exception 'Invalid settings'; end if;
 if exists(select 1 from jsonb_array_elements(items) e where jsonb_typeof(e)<>'object' or not(e ?& array['kind','label','aliases','value']) or e->>'kind' not in ('contact','place') or length(e->>'label') not between 1 and 100 or length(e->>'value') not between 1 and 1000 or jsonb_typeof(e->'aliases')<>'string') then raise exception 'Invalid entry'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select revision into current_revision from public.family_snapshots where owner_id=auth.uid();
 if coalesce(current_revision,0)<>expected_revision then raise exception 'Settings changed; reload first'; end if;
 insert into public.family_snapshots(owner_id,entries) values(auth.uid(),items) on conflict(owner_id) do update set entries=excluded.entries,revision=family_snapshots.revision+1,updated_at=now() returning revision into new_revision;
 return new_revision;
end $$;
create function public.ack_family_settings(version bigint) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.family_device_links l set applied_revision=version,applied_at=now() where elder_id=auth.uid() and exists(select 1 from public.family_snapshots s where s.owner_id=l.owner_id and s.revision=version);
end $$;
revoke all on function public.create_family_invitation(),public.accept_family_invitation(uuid),public.publish_family_settings(jsonb,bigint),public.ack_family_settings(bigint) from public,anon;
grant execute on function public.create_family_invitation(),public.accept_family_invitation(uuid),public.publish_family_settings(jsonb,bigint),public.ack_family_settings(bigint) to authenticated;
