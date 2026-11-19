begin;
do $$
declare o uuid:=gen_random_uuid(); e uuid:=gen_random_uuid(); other uuid:=gen_random_uuid(); code text; old_code text; result jsonb;
begin
 perform pg_advisory_xact_lock(hashtextextended('short-pairing-attempts',0));
 -- Reset the global test window only within this rolled-back transaction.
 delete from public.pairing_attempt_windows where bucket='global';
 insert into auth.users(id) values(o),(e),(other);
 perform set_config('request.jwt.claim.sub',o::text,true);
 code:=public.create_short_family_invitation();
 assert code ~ '^[0-9]{6}$','Not six digits';
 old_code:=code;
 code:=public.create_short_family_invitation();
 assert (select count(*)=1 from public.family_invitations where owner_id=o),'Multiple active invitations';
 perform set_config('request.jwt.claim.sub',e::text,true);
 if old_code<>code then
  assert public.accept_short_family_invitation(old_code)->>'error'='invalid_code','Replaced code accepted';
 end if;
 result:=public.accept_short_family_invitation(code);
 assert result->>'ok'='true','Valid code rejected';
 assert exists(select 1 from public.elder_snapshots s join public.family_device_links l on l.id=s.link_id where l.elder_id=e),'Missing independent snapshot';
 perform set_config('request.jwt.claim.sub',other::text,true);
 assert public.accept_short_family_invitation(code)->>'error'='invalid_code','Used code accepted';
 perform set_config('request.jwt.claim.sub',o::text,true);
 code:=public.create_short_family_invitation();
 update public.family_invitations set expires_at=now()-interval '1 minute' where owner_id=o;
 perform set_config('request.jwt.claim.sub',other::text,true);
 assert public.accept_short_family_invitation(code)->>'error'='invalid_code','Expired code accepted';
 for i in 1..3 loop
  assert public.accept_short_family_invitation('invalid')->>'error'='invalid_code';
 end loop;
 assert public.accept_short_family_invitation('invalid')->>'error'='rate_limited','Attempt limit missing';
 assert (select attempts=6 from public.pairing_attempt_windows where bucket='user:'||other::text),'Failed attempts were rolled back';
end $$;
rollback;
select 'PASS: six digits, rotation, one use, expiry, attempt limit; test data rolled back' as verification;
