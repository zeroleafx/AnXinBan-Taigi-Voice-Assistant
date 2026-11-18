create or replace function public.publish_family_settings(items jsonb, expected_revision bigint) returns bigint language plpgsql security definer set search_path='' as $$
declare current_entries jsonb; current_revision bigint; new_revision bigint;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if jsonb_typeof(items)<>'array' or jsonb_array_length(items)>200 or octet_length(items::text)>200000 then raise exception 'Invalid settings'; end if;
 if exists(select 1 from jsonb_array_elements(items) e where jsonb_typeof(e)<>'object' or not(e ?& array['kind','label','aliases','value']) or e->>'kind' not in ('contact','place') or length(e->>'label') not between 1 and 100 or length(e->>'value') not between 1 and 1000 or jsonb_typeof(e->'aliases')<>'string') then raise exception 'Invalid entry'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 if not exists(select 1 from public.family_device_links where owner_id=auth.uid()) then raise exception 'Pair an elder before publishing'; end if;
 select entries into current_entries from public.family_snapshots where owner_id=auth.uid();
 select revision into current_revision from public.family_snapshots where owner_id=auth.uid();
 if current_entries = items then return current_revision; end if;
 if coalesce(current_revision,0)<>expected_revision then raise exception 'Settings changed; reload first'; end if;
 insert into public.family_snapshots(owner_id,entries) values(auth.uid(),items) on conflict(owner_id) do update set entries=excluded.entries,revision=family_snapshots.revision+1,updated_at=now() returning revision into new_revision;
 return new_revision;
end $$;
