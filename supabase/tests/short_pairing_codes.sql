begin;
do $$
declare o uuid:=gen_random_uuid(); e uuid:=gen_random_uuid(); other uuid:=gen_random_uuid(); code text; old_code text; result jsonb;
begin
 insert into auth.users(id) values(o),(e),(other);
 perform set_config('request.jwt.claim.sub',o::text,true);
 code:=public.create_short_family_invitation();
 assert code ~ '^[0-9]{6}$','Not six digits';
 old_code:=code;
 code:=public.create_short_family_invitation();
 assert (select count(*)=1 from public.family_invitations where owner_id=o),'Multiple active invitations';
 perform set_config('request.jwt.claim.sub',e::text,true);
 if old_code<>code then
  assert public.request_family_pairing(old_code)->>'error'='invalid_code','Replaced code accepted';
 end if;
 result:=public.request_family_pairing(code);
 assert result->>'pending'='true','Valid code rejected';
 assert not exists(select 1 from public.family_device_links where elder_id=e),'Linked before the family approved';
 perform set_config('request.jwt.claim.sub',o::text,true);
 assert public.approve_pairing_request((result->>'request_id')::uuid)->>'ok'='true','Approval failed';
 assert exists(select 1 from public.elder_snapshots s join public.family_device_links l on l.id=s.link_id where l.elder_id=e),'Missing independent snapshot';
 perform set_config('request.jwt.claim.sub',other::text,true);
 assert public.request_family_pairing(code)->>'error'='invalid_code','Used code accepted';
 perform set_config('request.jwt.claim.sub',o::text,true);
 code:=public.create_short_family_invitation();
 update public.family_invitations set expires_at=now()-interval '1 minute' where owner_id=o;
 perform set_config('request.jwt.claim.sub',other::text,true);
 assert public.request_family_pairing(code)->>'error'='invalid_code','Expired code accepted';
 for i in 1..3 loop
  assert public.request_family_pairing('invalid')->>'error'='invalid_code';
 end loop;
 assert public.request_family_pairing('invalid')->>'error'='rate_limited','Attempt limit missing';
 assert (select attempts=6 from public.pairing_attempt_windows where bucket='user:'||other::text),'Failed attempts were rolled back';
end $$;
rollback;
select 'PASS: six digits, rotation, family approval, one use, expiry, attempt limit; test data rolled back' as verification;
