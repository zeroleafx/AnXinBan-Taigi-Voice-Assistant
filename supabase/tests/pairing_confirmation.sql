-- A correct code only asks the family; the family decides.
begin;
do $$
declare o uuid:=gen_random_uuid(); e uuid:=gen_random_uuid(); attacker uuid:=gen_random_uuid(); late uuid:=gen_random_uuid();
 code text; req jsonb; result jsonb;
begin
 insert into auth.users(id) values(o),(e),(attacker),(late);

 -- A correct code waits for the family; the number to compare is two digits.
 perform set_config('request.jwt.claim.sub',o::text,true);
 code:=public.create_short_family_invitation();
 perform set_config('request.jwt.claim.sub',e::text,true);
 req:=public.request_family_pairing(code);
 assert req->>'pending'='true','Correct code did not ask the family';
 assert req->>'confirm_code' ~ '^[0-9]{2}$','Confirmation number is not two digits';
 assert public.pairing_request_status((req->>'request_id')::uuid)->>'status'='pending','Request not pending';
 assert not exists(select 1 from public.family_device_links where elder_id=e),'Linked without approval';

 -- While it waits, nobody else can use the same code.
 perform set_config('request.jwt.claim.sub',attacker::text,true);
 assert public.request_family_pairing(code)->>'error'='busy','Second request on a waiting code';
 -- Nor read someone else's request.
 assert public.pairing_request_status((req->>'request_id')::uuid)->>'status'='expired','Status shown to another phone';

 -- The elder cannot approve its own request.
 perform set_config('request.jwt.claim.sub',e::text,true);
 assert public.approve_pairing_request((req->>'request_id')::uuid)->>'error'='not_found','Elder approved itself';

 -- The family sees it with the same number.
 perform set_config('request.jwt.claim.sub',o::text,true);
 result:=public.pending_pairing_requests();
 assert jsonb_array_length(result->'requests')=1,'Family does not see the request';
 assert result->'requests'->0->>'confirm_code'=req->>'confirm_code','Family sees another number';
 -- Anonymous (elder) accounts cannot manage requests.
 perform set_config('request.jwt.claims',json_build_object('sub',o,'is_anonymous',true)::text,true);
 assert public.pending_pairing_requests()->>'error'='family_login_required','Anonymous account listed requests';
 assert public.approve_pairing_request((req->>'request_id')::uuid)->>'error'='family_login_required','Anonymous account approved';
 perform set_config('request.jwt.claims','',true);

 -- Rejecting refuses the request and retires the code.
 assert public.reject_pairing_request((req->>'request_id')::uuid)->>'ok'='true','Reject failed';
 assert not exists(select 1 from public.family_device_links where elder_id=e),'Rejected request linked';
 perform set_config('request.jwt.claim.sub',e::text,true);
 assert public.pairing_request_status((req->>'request_id')::uuid)->>'status'='rejected','Elder not told of rejection';
 assert public.request_family_pairing(code)->>'error'='invalid_code','Rejected code still works';

 -- A new code, approved: linked, code used up, elder told.
 perform set_config('request.jwt.claim.sub',o::text,true);
 code:=public.create_short_family_invitation();
 perform set_config('request.jwt.claim.sub',e::text,true);
 req:=public.request_family_pairing(code);
 perform set_config('request.jwt.claim.sub',o::text,true);
 assert public.approve_pairing_request((req->>'request_id')::uuid)->>'ok'='true','Approve failed';
 assert exists(select 1 from public.family_device_links where owner_id=o and elder_id=e),'Approval did not link';
 assert not exists(select 1 from public.family_invitations where owner_id=o),'Code not used up';
 assert public.approve_pairing_request((req->>'request_id')::uuid)->>'error'='not_found','Approved twice';
 perform set_config('request.jwt.claim.sub',e::text,true);
 assert public.pairing_request_status((req->>'request_id')::uuid)->>'status'='approved','Elder not told of approval';

 -- A request for a code the family has since replaced cannot be approved.
 perform set_config('request.jwt.claim.sub',o::text,true);
 code:=public.create_short_family_invitation();
 perform set_config('request.jwt.claim.sub',late::text,true);
 req:=public.request_family_pairing(code);
 assert req->>'pending'='true','Second elder could not ask';
 perform set_config('request.jwt.claim.sub',o::text,true);
 perform public.create_short_family_invitation();
 assert public.approve_pairing_request((req->>'request_id')::uuid)->>'error'='expired','Approved a replaced code';
 assert jsonb_array_length(public.pending_pairing_requests()->'requests')=0,'Replaced code still listed';

 -- The old path never links.
 perform set_config('request.jwt.claim.sub',late::text,true);
 assert public.accept_short_family_invitation('123456')->>'error'='update_required','Old path still answers';
 assert not exists(select 1 from public.family_device_links where elder_id=late),'Old path linked';
end $$;
rollback;

-- Limits are per account and per address; nobody can use them up for others.
begin;
do $$
declare o uuid:=gen_random_uuid(); victim uuid:=gen_random_uuid(); u uuid; code text; req jsonb;
begin
 insert into auth.users(id) values(o),(victim);
 -- A script makes 150 guesses from fresh accounts on one address.
 perform set_config('request.headers','{"cf-connecting-ip":"203.0.113.7"}',true);
 for i in 1..150 loop
  u:=gen_random_uuid();
  insert into auth.users(id) values(u);
  perform set_config('request.jwt.claim.sub',u::text,true);
  perform public.request_family_pairing('000000');
 end loop;
 assert (select attempts=150 from public.pairing_attempt_windows where bucket='ip:203.0.113.7'),'Address not counted';
 -- That address is limited, whichever account uses it...
 u:=gen_random_uuid();
 insert into auth.users(id) values(u);
 perform set_config('request.jwt.claim.sub',u::text,true);
 assert public.request_family_pairing('000000')->>'error'='rate_limited','Address limit missing';
 -- ...but an elder on another network still pairs.
 perform set_config('request.jwt.claim.sub',o::text,true);
 code:=public.create_short_family_invitation();
 perform set_config('request.headers','{"cf-connecting-ip":"198.51.100.20"}',true);
 perform set_config('request.jwt.claim.sub',victim::text,true);
 req:=public.request_family_pairing(code);
 assert req->>'pending'='true','Others were locked out';
 assert not exists(select 1 from public.pairing_attempt_windows where bucket='global'),'Shared window still used';
end $$;
rollback;

-- Without an address header, only the account limit applies.
begin;
do $$
declare u uuid;
begin
 perform set_config('request.headers','',true);
 for i in 1..30 loop
  u:=gen_random_uuid();
  insert into auth.users(id) values(u);
  perform set_config('request.jwt.claim.sub',u::text,true);
  assert public.request_family_pairing('000000')->>'error'='invalid_code','Accounts without an address shared a limit';
 end loop;
end $$;
rollback;
select 'PASS: family approval, two-digit number, busy code, reject retires code, replaced code, old path closed, per-address limit, no shared lockout' as verification;
