create or replace function public.publish_elder_settings(link_id uuid,items jsonb,expected_revision bigint)
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
   or e->>'kind' not in ('contact','place','reminder')
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

