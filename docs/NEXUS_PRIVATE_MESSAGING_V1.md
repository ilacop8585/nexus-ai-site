# NEXUS Private — secure beta messaging

Status: DESIGN/SCHEMA CANDIDATE — not production-deployed.

## Product scope

NEXUS Private adds two communication surfaces for the trusted beta group:

1. **Beta Room** — one shared room for Owner + invited beta testers.
2. **Private Line** — one private 1:1 room between Owner and each beta tester.

The private messenger is separate from Beta Live tickets. Beta Live remains the structured QA workflow; NEXUS Private is human conversation.

## Security contract

NEXUS must not call this feature “Signal-like security”, “end-to-end encrypted”, or show a lock badge until the client cryptographic handshake has been implemented and verified end-to-end.

Required invariants:

- plaintext messages are encrypted on the sender device before leaving the browser/app;
- Neon stores ciphertext and delivery metadata only;
- message private keys never enter Neon, Cloudflare, GitHub, logs, analytics or NEXUS AI prompts;
- server-side workers cannot decrypt conversations;
- AI cannot read private chats unless a human explicitly exports/shares a selected message into an AI workflow;
- membership is authenticated against NEXUS accounts;
- removing a member rotates the group epoch/key material;
- a compromised delivery/database layer must not reveal message bodies;
- push notifications must not contain plaintext;
- attachments, when added, must be encrypted client-side before upload.

The server will still see unavoidable delivery metadata such as room identifier, participating account identifiers, timestamps and ciphertext size. E2EE does not make that metadata invisible.

## Cryptographic direction

Do not invent a custom cryptographic protocol.

For the group room, use **Messaging Layer Security (MLS), RFC 9420**, through an existing maintained implementation. MLS is designed for asynchronous group messaging and provides forward secrecy and post-compromise security.

For the 1:1 rooms we can use the same MLS engine with two members so that NEXUS maintains one security model instead of mixing two independent protocols. A later native client could also evaluate Signal Protocol/libsignal, but that library has a different integration/licensing profile.

Initial implementation target: a maintained MLS implementation compiled to WebAssembly/JS, with keys held in device-local secure storage where the platform allows it. Multi-device support must use one cryptographic identity/device record per physical/browser device.

## UX

Sidebar entry: **NEXUS Private**.

Inside:
- **Comitiva Beta**: shared room Owner + invited betas.
- **Privati**: Owner sees one thread per beta; each beta sees only the Owner DM.
- unread counters;
- typing/read state only if it can be implemented without leaking message content;
- device verification screen with safety fingerprint/QR;
- clear state when a new/unverified device joins;
- no invisible AI participant.

Suggested room labels:
- “Comitiva Beta”
- “Privato con Ilario” / “Privato con <beta name>”

## Data model

Server-side relay tables:
- `nexus_secure_devices`: public device identity only; never private keys.
- `nexus_secure_key_packages`: MLS public KeyPackages.
- `nexus_secure_rooms`: group or owner↔beta DM metadata.
- `nexus_secure_room_members`: authenticated membership.
- `nexus_secure_welcomes`: encrypted MLS Welcome envelopes.
- `nexus_secure_messages`: ciphertext envelopes.

The accompanying migration intentionally stores no plaintext message column.

## Authorization model

- Owner creates the shared group and explicit membership.
- Only accounts already authorized by the NEXUS beta/staff access model can be invited.
- DM creation is limited to Owner ↔ beta_tester.
- A beta cannot enumerate other users' private rooms.
- A member can fetch ciphertext only for rooms they currently belong to.
- Revoked devices cannot publish new messages.
- Membership changes are audited as metadata events, but message bodies remain opaque.

## Relationship with Beta Live

A private message is **not** automatically a bug ticket.

If a tester discusses a bug in chat, the UI may offer “Crea ticket Beta Live da questo messaggio”. That action must ask the tester what text to copy because the server cannot decrypt the secure chat. Only the explicitly selected plaintext is submitted to Beta Live.

This preserves the separation:

NEXUS Private = human private conversation.
Beta Live = structured QA, diagnostics, status, fixes and retest.

## Delivery phases

### Phase A — relay/schema
- additive schema/RPC;
- room membership;
- device/key-package registration;
- ciphertext-only send/fetch;
- no production UI badge claiming E2EE.

### Phase B — client crypto
- MLS engine integration;
- device identity generation;
- local private-key persistence;
- key package lifecycle;
- Welcome/epoch handling;
- encrypt/decrypt before/after RPC.

### Phase C — verification
Acceptance must include:
- database inspection proves no plaintext;
- second account receives/decrypts;
- non-member cannot fetch envelopes;
- revoked device cannot send;
- member removal rotates epoch;
- browser refresh restores only local encrypted state;
- server/worker logs contain no key/plaintext;
- owner↔beta DM isolation;
- common room with all invited betas;
- Android + desktop browser interoperability.

Only after these pass may the UI display **E2EE verified**.

## Non-goals for V1

- voice/video calls;
- disappearing messages;
- anonymous membership;
- server-side full-text search;
- AI auto-reading private chat;
- remote recovery of private keys without an explicitly designed encrypted recovery mechanism.

## Current repository baseline

This work starts from `fb314c2` (“feat: embed Beta AI triage and Social Publisher”) so it does not overwrite the newer Social Publisher/Beta AI work that landed after the Drive checkpoint.


## Security status UI

Every NEXUS Private group/DM must expose a visible **Sicurezza** panel.

Show:
- E2EE state: not configured / negotiating / verified;
- protocol: MLS (RFC 9420) only when the actual client engine uses it;
- group epoch;
- this device fingerprint;
- participant/device fingerprints and verification state;
- last key/membership rotation;
- warning for newly added or unverified devices.

Do not expose private keys or raw secrets.

The green lock / “E2EE verificata” state is forbidden until an end-to-end test proves:
sender plaintext -> client encryption -> ciphertext-only relay/storage -> recipient client decryption.

For the monitored Beta Workspace, do not show this E2EE indicator. That surface must instead show that Owner and NEXUS AI may inspect it for QA.
