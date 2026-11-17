# Family settings local prototype

Start the app, choose family settings, and create a six-digit PIN. Add contacts
with comma-separated aliases and named addresses. Saved edits are a pending
copy. "模擬同步到長輩端" explicitly copies them to the applied local snapshot.
Lock family settings and enter elder mode to use that snapshot with speech.
Returning to the elder home creates a fresh controller and reloads the snapshot.
Duplicate contact aliases present a choice; duplicate place aliases are rejected.

There is no network request, account, real device pairing, or cross-device sync.
Both simulated endpoints are on the same phone. Existing SOS contacts are separate
from the new family contacts. PIN is a salted hash in local preferences, with a
five-attempt/one-minute lockout; it is prototype UI protection, not a production
credential vault or backend authorization boundary. There is no PIN recovery yet.
The role selector is shown on launch; no remembered default role is implemented.

Before production: implement Supabase authentication and per-family authorization,
verified expiring device pairing, secure credential/PIN storage and recovery,
versioned synchronization with conflict resolution, and device acknowledgment.
