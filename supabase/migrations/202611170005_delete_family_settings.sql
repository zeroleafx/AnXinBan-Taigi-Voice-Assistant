-- Keep an empty snapshot so revision numbers never restart after deletion.
create or replace function public.delete_family_settings()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  delete from public.family_settings where owner_id = auth.uid();
  delete from public.family_invitations where owner_id = auth.uid();
  update public.family_snapshots
    set entries = '[]'::jsonb, revision = revision + 1, updated_at = now()
    where owner_id = auth.uid() and entries <> '[]'::jsonb;
end $$;
revoke all on function public.delete_family_settings() from public, anon;
grant execute on function public.delete_family_settings() to authenticated;
