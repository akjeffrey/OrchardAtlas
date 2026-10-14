# Security and sharing model

## Threats and protections
Exact plant/foraging coordinates, photos and notes must remain private. An attacker
may use a modified client to query other properties, forge authors, mutate events,
or upload arbitrary files. Firebase Authentication identifies users; Firestore and
Storage rules enforce authorization independently of UI.

V1 uses email/password auth with private owner-created properties. Users can only
read/query their owned properties or a known property with a future membership.
Events are append-only and authors are bound to request.auth.uid. Deny all
unmatched paths. Member writes and invitations remain disabled in V1 until their
lifecycle and tests exist; roles are a domain contract for future sharing.

Future roles: owner manages membership/property; editor creates/updates plants and
appends events; viewer reads. Invitations must be trusted-server mediated, expiring,
revocable and bound to a recipient. Public discovery must use separate redacted
records, never make the primary collection public. Storage reads require property
access; uploads will enforce image content type, size, path ownership and metadata.
V1 Storage denies writes while photo capture is deferred.

## Device privacy and offline revocation
Firestore's persistent cache may contain previously authorized data while offline.
Server revocation cannot erase an offline device immediately. Sign-out must cancel
all streams and clear Firestore persistence before another account uses the app;
restart the client after termination. If clearing fails, retain a blocking error
and do not permit another account sign-in. Users should protect the OS account,
device storage encryption and screen lock. No claim of encrypted app-level cache.

## Configuration and release
API keys/config files are developer supplied and ignored even though some Firebase
client identifiers are public. Restrict Maps keys by Android package/signing SHA
and iOS bundle ID; separate debug and production projects. No service account or
signing secret belongs in the application. Enable email/password auth, deploy rules
before use, and verify rules with emulators. Consider App Check, email verification,
rate limiting and abuse monitoring before public release. Do not log passwords,
Firebase tokens, exact coordinates or photo download tokens. No analytics in V1.
