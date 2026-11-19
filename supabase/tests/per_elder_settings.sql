-- Run after 202611190001_per_elder_settings.sql. All test data is rolled back.
begin;
do $$
declare
 owner uuid:=gen_random_uuid(); elder_a uuid:=gen_random_uuid(); elder_b uuid:=gen_random_uuid(); stranger uuid:=gen_random_uuid();
 link_a uuid; link_b uuid; result bigint;
 items jsonb:='[{"kind":"place","label":"家","aliases":"厝","value":"測試地址"}]';
begin
 insert into auth.users(id) values(owner),(elder_a),(elder_b),(stranger);
 insert into public.family_device_links(owner_id,elder_id) values(owner,elder_a) returning id into link_a;
 insert into public.family_device_links(owner_id,elder_id) values(owner,elder_b) returning id into link_b;
 perform set_config('request.jwt.claim.sub',owner::text,true);
 result:=public.publish_elder_settings(link_a,items,0);
 assert result=1;
 assert (select entries='[]'::jsonb and revision=0 from public.elder_snapshots where link_id=link_b),'B was changed by A publication';
 assert public.publish_elder_settings(link_a,items,1)=1,'Unchanged publish incremented revision';
 perform set_config('request.jwt.claim.sub',stranger::text,true);
 begin
   perform public.publish_elder_settings(link_a,items,1);
   raise exception 'Unauthorized publication accepted';
 exception when others then
   if sqlerrm <> 'Not paired' then raise; end if;
 end;
 perform set_config('request.jwt.claim.sub',elder_a::text,true);
 perform set_config('role','authenticated',true);
 assert (select count(*)=1 from public.elder_snapshots),'Elder can see another snapshot';
 perform public.ack_elder_settings(link_b,0);
 perform public.ack_elder_settings(link_a,1);
 perform set_config('role','postgres',true);
 assert (select applied_revision=1 from public.family_device_links where id=link_a);
 assert (select applied_at is null from public.family_device_links where id=link_b),'Elder acknowledged another device';
 delete from public.family_device_links where id=link_a;
 assert not exists(select 1 from public.elder_snapshots where link_id=link_a),'Unlinked data survived';
 assert exists(select 1 from public.elder_snapshots where link_id=link_b),'Other elder was removed';
end $$;
rollback;
