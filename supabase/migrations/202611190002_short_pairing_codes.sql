alter table public.family_invitations add column short_code text unique check(short_code ~ '^[0-9]{6}$');
create table public.pairing_attempt_windows (
 bucket text primary key, starts_at timestamptz not null, attempts integer not null
);
alter table public.pairing_attempt_windows enable row level security;
revoke all on public.pairing_attempt_windows from public,anon,authenticated;

create function public.create_short_family_invitation() returns text language plpgsql security definer set search_path='' as $$
declare bytes bytea; number integer; candidate text;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'Family login required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 for attempt in 1..30 loop
  loop
   bytes:=extensions.gen_random_bytes(3);
   number:=get_byte(bytes,0)*65536+get_byte(bytes,1)*256+get_byte(bytes,2);
   exit when number<16000000;
  end loop;
  candidate:=lpad((number%1000000)::text,6,'0');
  begin
   insert into public.family_invitations(owner_id,short_code) values(auth.uid(),candidate)
   on conflict(owner_id) do update set token=gen_random_uuid(),short_code=excluded.short_code,expires_at=now()+interval '10 minutes';
   return candidate;
  exception when unique_violation then null;
  end;
 end loop;
 raise exception 'Please try again';
end $$;

create function public.accept_short_family_invitation(code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare owner uuid; token_id uuid; key text; count_attempts integer;
begin
 if auth.uid() is null then return jsonb_build_object('error','login_required'); end if;
 -- Persist failed attempts by returning errors rather than raising/rolling back.
 perform pg_advisory_xact_lock(hashtextextended('short-pairing-attempts',0));
 foreach key in array array['user:'||auth.uid()::text,'global'] loop
  insert into public.pairing_attempt_windows(bucket,starts_at,attempts) values(key,now(),1)
  on conflict(bucket) do update set
   starts_at=case when pairing_attempt_windows.starts_at<now()-interval '10 minutes' then now() else pairing_attempt_windows.starts_at end,
   attempts=case when pairing_attempt_windows.starts_at<now()-interval '10 minutes' then 1 else pairing_attempt_windows.attempts+1 end
  returning attempts into count_attempts;
  if count_attempts > (case when key='global' then 100 else 5 end) then
   return jsonb_build_object('error','rate_limited');
  end if;
 end loop;
 if code is null or code !~ '^[0-9]{6}$' then return jsonb_build_object('error','invalid_code'); end if;
 select i.owner_id,i.token into owner,token_id from public.family_invitations i
 where i.short_code=code and i.expires_at>now() and i.owner_id<>auth.uid();
 if owner is null then return jsonb_build_object('error','invalid_code'); end if;
 perform pg_advisory_xact_lock(hashtextextended(owner::text,0));
 if not exists(select 1 from public.family_invitations i where i.token=token_id and i.short_code=code and i.expires_at>now()) then
  return jsonb_build_object('error','invalid_code');
 end if;
 if exists(select 1 from public.family_device_links where elder_id=auth.uid()) then return jsonb_build_object('error','already_paired'); end if;
 begin
  insert into public.family_device_links(owner_id,elder_id) values(owner,auth.uid());
 exception when unique_violation then return jsonb_build_object('error','already_paired');
 end;
 delete from public.family_invitations where token=token_id;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.create_short_family_invitation(),public.accept_short_family_invitation(text) from public,anon;
grant execute on function public.create_short_family_invitation(),public.accept_short_family_invitation(text) to authenticated;
