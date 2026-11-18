alter table public.family_snapshots
  add column settings_cleared_at timestamptz;

-- Serialize pairing/unpairing with publishing for the same family.
create function public.lock_family_link_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if TG_OP = 'DELETE' then
    perform pg_advisory_xact_lock(hashtextextended(old.owner_id::text, 0));
    return old;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(new.owner_id::text, 0));
  return new;
end $$;

create trigger lock_family_link_change
before insert or delete on public.family_device_links
for each row execute function public.lock_family_link_change();

create function public.clear_last_elder_settings() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists(select 1 from public.family_device_links where owner_id = old.owner_id) then
    return old;
  end if;
  delete from public.family_settings where owner_id = old.owner_id;
  delete from public.family_invitations where owner_id = old.owner_id;
  -- Account deletion cascades must not recreate a snapshot for a missing user.
  if exists(select 1 from auth.users where id = old.owner_id) then
    insert into public.family_snapshots(owner_id, entries, settings_cleared_at)
    values(old.owner_id, '[]'::jsonb, clock_timestamp())
    on conflict(owner_id) do update set
      entries = '[]'::jsonb,
      revision = family_snapshots.revision + 1,
      updated_at = now(),
      settings_cleared_at = clock_timestamp();
  end if;
  return old;
end $$;

create trigger clear_last_elder_settings
after delete on public.family_device_links
for each row execute function public.clear_last_elder_settings();

revoke all on function public.lock_family_link_change(), public.clear_last_elder_settings()
from public, anon, authenticated;
