-- Pairing with a six-digit code now needs the family's approval, and attempts
-- are limited per device and per network address.
--
-- Before: a correct code linked the elder at once, so guessing had to be held
-- back by one window of 100 attempts shared by everyone. Anonymous accounts
-- cost nothing, so a script could use that window up every ten minutes and
-- keep every elder from pairing. Now a correct code only asks the family, who
-- compares a two-digit number shown on the elder's phone before allowing it.
-- A guessed code gains nothing, so the shared window is gone.

create table public.pairing_requests (
 id uuid primary key default gen_random_uuid(),
 -- The invitation it answers. Not a foreign key: a new code replaces the
 -- token, and a request for the old one must then stop being approvable.
 invitation_token uuid not null,
 owner_id uuid not null references auth.users(id) on delete cascade,
 elder_id uuid not null references auth.users(id) on delete cascade,
 confirm_code text not null check(confirm_code ~ '^[0-9]{2}$'),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '5 minutes'
);
-- One request waits on a code at a time; the family deals with it first.
create unique index one_pending_request_per_invitation
 on public.pairing_requests(invitation_token) where status='pending';
create index pairing_requests_owner_idx on public.pairing_requests(owner_id) where status='pending';
create index pairing_requests_elder_idx on public.pairing_requests(elder_id);
alter table public.pairing_requests enable row level security;
-- Reached only through the functions below.
revoke all on public.pairing_requests from public,anon,authenticated;

-- The shared window is no longer used.
delete from public.pairing_attempt_windows where bucket='global';

-- The caller's network address as the API gateway passed it on, or null.
-- cf-connecting-ip is set by the edge and cannot be supplied by the client;
-- the others are fallbacks. The family's approval, not this limit, is what
-- stops a guessed code, so a spoofed header only weakens a second line.
create function public.pairing_client_ip() returns text language sql stable set search_path='' as $$
 select nullif(trim(coalesce(
  (nullif(current_setting('request.headers',true),'')::json)->>'cf-connecting-ip',
  (nullif(current_setting('request.headers',true),'')::json)->>'x-real-ip',
  split_part((nullif(current_setting('request.headers',true),'')::json)->>'x-forwarded-for',',',1)
 )),'')
$$;

-- Counts one attempt for this account and this address; true when either is
-- over its limit for the current ten minutes. No address means no address
-- limit, never a bucket that everyone shares.
create function public.pairing_rate_limited() returns boolean language plpgsql security definer set search_path='' as $$
declare ip text:=public.pairing_client_ip(); key text; count_attempts integer; limited boolean:=false;
begin
 perform pg_advisory_xact_lock(hashtextextended('short-pairing-attempts',0));
 foreach key in array array_remove(array['user:'||auth.uid()::text, case when ip is null then null else 'ip:'||ip end], null) loop
  insert into public.pairing_attempt_windows(bucket,starts_at,attempts) values(key,now(),1)
  on conflict(bucket) do update set
   starts_at=case when pairing_attempt_windows.starts_at<now()-interval '10 minutes' then now() else pairing_attempt_windows.starts_at end,
   attempts=case when pairing_attempt_windows.starts_at<now()-interval '10 minutes' then 1 else pairing_attempt_windows.attempts+1 end
  returning attempts into count_attempts;
  if count_attempts > (case when key like 'ip:%' then 20 else 5 end) then limited:=true; end if;
 end loop;
 -- Old windows are of no use; keep the table small.
 delete from public.pairing_attempt_windows where starts_at<now()-interval '1 day';
 return limited;
end $$;

-- The elder enters a code. A correct one creates a request the family must
-- approve; the reply carries the number to show on the elder's phone.
-- Errors are returned, not raised, so counted attempts are kept.
create function public.request_family_pairing(code text) returns jsonb language plpgsql security definer set search_path='' as $$
declare owner uuid; token_id uuid; request_id uuid; confirm text;
begin
 if auth.uid() is null then return jsonb_build_object('error','login_required'); end if;
 if public.pairing_rate_limited() then return jsonb_build_object('error','rate_limited'); end if;
 if code is null or code !~ '^[0-9]{6}$' then return jsonb_build_object('error','invalid_code'); end if;
 if exists(select 1 from public.family_device_links where elder_id=auth.uid()) then
  return jsonb_build_object('error','already_paired');
 end if;
 select i.owner_id,i.token into owner,token_id from public.family_invitations i
 where i.short_code=code and i.expires_at>now() and i.owner_id<>auth.uid();
 if owner is null then return jsonb_build_object('error','invalid_code'); end if;
 perform pg_advisory_xact_lock(hashtextextended(owner::text,0));
 -- Trying again replaces this phone's earlier request; stale ones go.
 delete from public.pairing_requests where elder_id=auth.uid() and status='pending';
 delete from public.pairing_requests where status='pending' and expires_at<=now();
 delete from public.pairing_requests where status<>'pending' and created_at<now()-interval '1 day';
 if exists(select 1 from public.pairing_requests where invitation_token=token_id and status='pending') then
  return jsonb_build_object('error','busy');
 end if;
 confirm:=lpad((get_byte(extensions.gen_random_bytes(1),0)%100)::text,2,'0');
 insert into public.pairing_requests(invitation_token,owner_id,elder_id,confirm_code)
 values(token_id,owner,auth.uid(),confirm) returning id into request_id;
 return jsonb_build_object('pending',true,'request_id',request_id,'confirm_code',confirm);
end $$;

-- What became of the elder's own request: pending, approved, rejected or
-- expired (also when the family made a new code meanwhile).
create function public.pairing_request_status(request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.pairing_requests;
begin
 select * into r from public.pairing_requests p where p.id=request_id and p.elder_id=auth.uid();
 if r.id is null then return jsonb_build_object('status','expired'); end if;
 if r.status<>'pending' then return jsonb_build_object('status',r.status); end if;
 if r.expires_at<=now() or not exists(
  select 1 from public.family_invitations i where i.token=r.invitation_token and i.expires_at>now()
 ) then return jsonb_build_object('status','expired'); end if;
 return jsonb_build_object('status','pending');
end $$;

-- Requests waiting for this family, newest first.
create function public.pending_pairing_requests() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
  return jsonb_build_object('error','family_login_required');
 end if;
 return jsonb_build_object('requests',coalesce((
  select jsonb_agg(jsonb_build_object('id',p.id,'confirm_code',p.confirm_code,'created_at',p.created_at) order by p.created_at desc)
  from public.pairing_requests p
  join public.family_invitations i on i.token=p.invitation_token and i.expires_at>now()
  where p.owner_id=auth.uid() and p.status='pending' and p.expires_at>now()
 ),'[]'::jsonb));
end $$;

-- The family checked the number and allows the link; the code is used up.
create function public.approve_pairing_request(request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.pairing_requests;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
  return jsonb_build_object('error','family_login_required');
 end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into r from public.pairing_requests p
 where p.id=request_id and p.owner_id=auth.uid() and p.status='pending' for update;
 if r.id is null then return jsonb_build_object('error','not_found'); end if;
 if r.expires_at<=now() or not exists(
  select 1 from public.family_invitations i where i.token=r.invitation_token and i.expires_at>now()
 ) then return jsonb_build_object('error','expired'); end if;
 if exists(select 1 from public.family_device_links where elder_id=r.elder_id) then
  update public.pairing_requests set status='rejected' where id=r.id;
  return jsonb_build_object('error','already_paired');
 end if;
 begin
  insert into public.family_device_links(owner_id,elder_id) values(r.owner_id,r.elder_id);
 exception when unique_violation then
  update public.pairing_requests set status='rejected' where id=r.id;
  return jsonb_build_object('error','already_paired');
 end;
 delete from public.family_invitations where token=r.invitation_token;
 update public.pairing_requests set status='approved' where id=r.id;
 return jsonb_build_object('ok',true);
end $$;

-- The number did not match, or the family did not expect a request: refuse
-- it and retire the code, so a guesser cannot try again with it.
create function public.reject_pairing_request(request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.pairing_requests;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then
  return jsonb_build_object('error','family_login_required');
 end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 select * into r from public.pairing_requests p
 where p.id=request_id and p.owner_id=auth.uid() and p.status='pending' for update;
 if r.id is null then return jsonb_build_object('error','not_found'); end if;
 update public.pairing_requests set status='rejected' where id=r.id;
 delete from public.family_invitations where token=r.invitation_token;
 return jsonb_build_object('ok',true);
end $$;

-- The old path linked on a correct code alone. Keep the name so older apps
-- get a clear answer instead of a missing function, but never link.
create or replace function public.accept_short_family_invitation(code text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 return jsonb_build_object('error','update_required');
end $$;

revoke all on function
 public.pairing_client_ip(),
 public.pairing_rate_limited(),
 public.request_family_pairing(text),
 public.pairing_request_status(uuid),
 public.pending_pairing_requests(),
 public.approve_pairing_request(uuid),
 public.reject_pairing_request(uuid)
from public,anon,authenticated;
grant execute on function
 public.request_family_pairing(text),
 public.pairing_request_status(uuid),
 public.pending_pairing_requests(),
 public.approve_pairing_request(uuid),
 public.reject_pairing_request(uuid)
to authenticated;
