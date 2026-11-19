alter table public.family_device_links add column display_name text not null default '' check(length(display_name)<=40);
create table public.elder_snapshots (
 link_id uuid primary key references public.family_device_links(id) on delete cascade,
 entries jsonb not null default '[]' check(jsonb_typeof(entries)='array'),
 revision bigint not null default 0,
 updated_at timestamptz not null default now()
);
alter table public.elder_snapshots enable row level security;
revoke all on public.elder_snapshots from anon, authenticated;
grant select on public.elder_snapshots to authenticated;
create policy participants_read on public.elder_snapshots for select to authenticated
using(exists(select 1 from public.family_device_links l where l.id=link_id and (select auth.uid()) in(l.owner_id,l.elder_id)));
-- Preserve each existing elder's settings and acknowledgement revision.
insert into public.elder_snapshots(link_id,entries,revision)
select l.id,coalesce(s.entries,'[]'::jsonb),coalesce(s.revision,0)
from public.family_device_links l left join public.family_snapshots s on s.owner_id=l.owner_id;

create function public.initialize_elder_snapshot() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.elder_snapshots(link_id) values(new.id);
 return new;
end $$;
create trigger initialize_elder_snapshot after insert on public.family_device_links
for each row execute function public.initialize_elder_snapshot();
revoke all on function public.initialize_elder_snapshot() from public,anon,authenticated;

create function public.publish_elder_settings(link_id uuid,items jsonb,expected_revision bigint)
returns bigint language plpgsql security definer set search_path='' as $$
declare current_row public.elder_snapshots; result bigint;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 if not exists(select 1 from public.family_device_links l where l.id=link_id and l.owner_id=auth.uid()) then raise exception 'Not paired'; end if;
 if items is null or jsonb_typeof(items) is distinct from 'array' then raise exception 'Invalid settings'; end if;
 if jsonb_array_length(items)>200 or octet_length(items::text)>200000 then raise exception 'Invalid settings'; end if;
 if exists(select 1 from jsonb_array_elements(items) e where
   jsonb_typeof(e) is distinct from 'object' or not(e ?& array['kind','label','aliases','value'])
   or jsonb_typeof(e->'kind') is distinct from 'string'
   or e->>'kind' not in ('contact','place')
   or jsonb_typeof(e->'label') is distinct from 'string' or length(e->>'label') not between 1 and 100
   or jsonb_typeof(e->'value') is distinct from 'string' or length(e->>'value') not between 1 and 1000
   or jsonb_typeof(e->'aliases') is distinct from 'string') then raise exception 'Invalid entry'; end if;
 select s.* into current_row from public.elder_snapshots s where s.link_id=publish_elder_settings.link_id for update;
 if not found then raise exception 'Not paired'; end if;
 if current_row.entries=items then return current_row.revision; end if;
 if expected_revision is null or current_row.revision<>expected_revision then raise exception 'Settings changed; reload first'; end if;
 update public.elder_snapshots s set entries=items,revision=s.revision+1,updated_at=now()
 where s.link_id=publish_elder_settings.link_id returning s.revision into result;
 return result;
end $$;

create function public.ack_elder_settings(link_id uuid,version bigint) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.family_device_links l set applied_revision=version,applied_at=now()
 where l.id=link_id and l.elder_id=auth.uid() and exists(
 select 1 from public.elder_snapshots s where s.link_id=l.id and s.revision=version);
end $$;
create function public.rename_paired_elder(link_id uuid,display_name text) returns void language plpgsql security definer set search_path='' as $$
begin
 if display_name is null or length(trim(display_name)) not between 1 and 40 then raise exception 'Invalid name'; end if;
 update public.family_device_links l set display_name=trim(rename_paired_elder.display_name)
 where l.id=link_id and l.owner_id=auth.uid();
 if not found then raise exception 'Not paired'; end if;
end $$;
revoke all on function public.publish_elder_settings(uuid,jsonb,bigint),public.ack_elder_settings(uuid,bigint),public.rename_paired_elder(uuid,text) from public,anon;
grant execute on function public.publish_elder_settings(uuid,jsonb,bigint),public.ack_elder_settings(uuid,bigint),public.rename_paired_elder(uuid,text) to authenticated;
-- Old clients must upgrade; shared writes/acks must not masquerade as per-elder sync.
create or replace function public.publish_family_settings(items jsonb,expected_revision bigint) returns bigint language plpgsql security definer set search_path='' as $$
begin raise exception 'Please update the app to manage individual elder settings'; end $$;
create or replace function public.ack_family_settings(version bigint) returns void language plpgsql security definer set search_path='' as $$
begin raise exception 'Please update the app to sync individual elder settings'; end $$;
create or replace function public.delete_family_settings() returns void language plpgsql security definer set search_path='' as $$
begin raise exception 'Please update the app to manage individual elder settings'; end $$;
