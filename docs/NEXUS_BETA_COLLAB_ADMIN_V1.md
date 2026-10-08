# NEXUS Beta Collaboration & Admin Workspace V1

Status: DRAFT / isolated branch. Not deployed.

## Goal

Make beta testing collaborative instead of requiring the Owner to relay WhatsApp messages into development chats.

Two privacy surfaces:

1. NEXUS Private
- shared Comitiva Beta room;
- Owner↔beta direct messages;
- target: standards-based end-to-end encryption;
- Owner reads because Owner is a cryptographic participant;
- NEXUS AI does not automatically read E2EE message bodies;
- a Sicurezza drawer shows verified protocol/status without exposing secret key material.

2. Beta Workspace
- QA conversations with NEXUS AI;
- Owner/Admin can inspect beta conversations from Admin Center;
- NEXUS AI may process them for QA automation;
- tester UI must clearly say: Workspace Beta monitorato da NEXUS AI e Owner per finalità QA;
- this surface must NOT be described as private E2EE.

## Security UI for NEXUS Private

Every secure room should expose a user-visible Sicurezza panel showing only verified facts:
- E2EE state: non configurata / configurazione in corso / verificata;
- protocol: MLS (RFC 9420) only after the client MLS engine is actually active;
- group epoch;
- local device fingerprint;
- participant/device fingerprints;
- device verification status;
- last membership/key rotation event;
- warning when a new or unverified device joins.

Never display private keys, raw secrets, recovery material or bearer tokens.
Do not show a green lock or E2EE verified merely because tables store ciphertext.

## CEO intervention in Beta Workspace

Admin Center lists conversations owned by accounts whose current role is beta_tester.
Owner can inspect messages and linked attachment metadata and can add a message into the beta conversation.

The CEO message is not impersonation:
- database writer is the real Owner user id;
- metadata actor_type=ceo;
- metadata visible_label=CEO;
- UI renders a distinct CEO bubble;
- AI context receives it as a CEO instruction inside the same thread.

## Automatic beta-improvement loop

Beta writes or uploads in Beta Workspace
→ observation captured
→ NEXUS AI classifies it
→ ordinary question: no QA action
→ bug/suggestion/UX/performance signal: create or link a Beta Live candidate
→ Beta Live AI triage
→ diagnosis/proposed change
→ controlled implementation
→ tests
→ Owner/change-control gate for production-risk changes
→ deploy
→ beta retest
→ resolved or reopen.

No direct one-sentence-to-blind-production-edit flow.

## Attachments

Admin may see attachment metadata for beta conversations.
Opening/downloading the actual object must go through an authenticated Owner-only file-service path; raw storage objects must not be public.

## Audit

Distinguish BETA, CEO, NEXUS AI, SYSTEM and WORKER in both data and UI.

## Current implementation boundary

This branch adds schema/RPC/UI scaffolding only.
The existing production Beta Live AI triage is reused.

Before production:
- add/verify beta-observer worker route;
- add authenticated Owner attachment-view/download endpoint;
- validate RPC authorization on a temporary Neon branch;
- verify CEO bubble rendering and beta-side visibility;
- verify ordinary users cannot access Admin functions;
- verify secure E2EE claims separately from monitored Beta Workspace claims.