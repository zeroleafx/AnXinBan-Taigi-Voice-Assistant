# Cross-phone family settings

Supabase project: ewiszwajtzaamswjoosb. Publishable key is client configuration;
all access is enforced through authenticated RLS and validated SQL RPCs.
Google provider and com.anxinban.app://login-callback/ must be configured.

## Two-phone test

1. On the family phone, sign in with Google, enter family settings with PIN.
2. Add/edit contacts and aliases or named addresses, then publish settings.
3. Generate a one-use invitation (expires after ten minutes). Share it only with
   the intended elder. Generating another invitation invalidates the old one.
4. On the elder phone, use a different Google account, enter the invitation,
   and explicitly confirm linking and receiving settings.
5. Open elder mode. While foregrounded, settings refresh every 30 seconds and
   on returning to the foreground. Offline operation uses the last saved copy.
6. Refresh the family status page to see the elder's applied revision.
7. Unlink using the family device list; this prevents future cloud reads. It
   does not remotely erase a previously downloaded offline copy.

Current limitations: elders also need Google login for pairing. There is no
push notification/background sync. A single elder account links to one family.
Multiple family editors use revision checks: refresh before republishing after
conflict (refresh retrieves revision; reenter family settings loads remote data).
Local family PIN remains the prototype salted hash with attempt lockout, not
hardware-backed PIN verification; no PIN recovery yet. Auth tokens use secure
storage. Web OAuth is not configured (mobile callback only).

No recordings or device address books are uploaded; only explicitly entered
family setting records are published. Existing SOS contact remains independent.

Migrations 001-003 are deployed. Security advisors flag the intentionally private
invitations table with no policies and authenticated SECURITY DEFINER RPCs.
RPCs check auth.uid(), own the access decisions, and fix search_path to empty.
No authenticated client can insert a device link or read invitation records.

## Individual elder settings (deployed 2026-11-19)

`supabase/migrations/202611190001_per_elder_settings.sql` was deployed on
2026-11-19 for the new family dashboard. Each pairing now owns an `elder_snapshots` row. Existing
shared snapshots are copied to each currently paired elder with their revision
preserved; new pairings start empty. Drafts are keyed by owner and pairing ID.
The family dashboard prunes drafts for deleted pairings after a successful refresh.

The migration disables the legacy shared publish/delete/ack RPCs so older clients
cannot accidentally publish shared data or falsely acknowledge an individual
snapshot. Update both family and elder apps together. The old shared snapshot is
retained for migration history until the existing last-unlink cleanup removes its
contents; the new client only reads individual snapshots.

Validation SQL is in `supabase/tests/per_elder_settings.sql`; it runs in a rollback
transaction and tests isolated publication, unchanged revisions, authorization,
RLS, acknowledgements and unlink cleanup. This script passed on the remote database on 2026-11-19; its test data
was rolled back. Local drafts from the former shared editor are not automatically
assigned to a particular elder; only previously published settings are migrated.
