# NEXUS Private E2EE V1

Status: implementation candidate.

NEXUS Private is separate from the monitored Beta Workspace.

## Surfaces

- **Comitiva Beta**: one E2EE group for Owner + accounts with role beta_tester.
- **Privati**: one E2EE Owner↔beta room per beta tester.

## Cryptographic protocol

Protocol label: **NEXUS-E2EE-v1**.

Browser-native Web Crypto primitives:

- Key agreement: ECDH P-256.
- KDF: HKDF-SHA-256.
- Message content: AES-256-GCM.
- Sender authentication: ECDSA P-256 with SHA-256.
- One fresh random AES content key per message.
- One fresh ephemeral ECDH key pair per message.
- The content key is wrapped separately for every active device in the room.
- AES-GCM Additional Authenticated Data binds room id, client message id, sender device id and membership version.

Neon receives only:
- public device keys and fingerprints;
- encrypted message payload;
- ephemeral public key;
- signature;
- per-device wrapped content keys;
- delivery metadata.

Neon never receives plaintext or device private keys.

## Security status shown to users

The room Security panel displays:
- protocol name;
- key agreement/KDF/cipher/signature algorithms;
- this-device fingerprint;
- participating device fingerprints;
- membership version;
- local cryptographic self-test;
- peer verification status after a message from another device has successfully decrypted and verified.

Do not label this implementation as Signal Protocol.

NEXUS-E2EE-v1 provides end-to-end confidentiality and sender signature verification. It does **not** currently implement a Signal Double Ratchet or MLS-style post-compromise security. A later audited ratcheting/MLS layer can replace the envelope protocol without changing the product surfaces.

## Privacy split

**NEXUS Private**
- server and NEXUS AI do not have plaintext access;
- AI cannot auto-read these conversations;
- only a user-explicitly selected message can be copied into Beta Live or an AI workflow.

**Beta Workspace**
- explicitly monitored by Owner + NEXUS AI for QA;
- automated observation/triage is allowed;
- never display the E2EE badge there.

## Device lifecycle

- Device private keys live in IndexedDB as non-exportable CryptoKey objects.
- Public JWKs and fingerprint are registered with Neon.
- Clearing browser storage creates a new device identity.
- Revoked devices cannot fetch new key envelopes or send.
- A user removed from a room receives no key envelope for future messages.
- Historical ciphertext already delivered to a previously authorized device cannot be retroactively revoked.

## Acceptance

Required before green E2EE status:
1. local cryptographic self-test passes;
2. server schema contains no plaintext message column;
3. sender encrypts and signs before RPC;
4. recipient unwraps and decrypts locally;
5. signature validates against the sender device public key;
6. wrong device cannot fetch a wrapped content key;
7. non-member cannot fetch a room;
8. revoked device cannot send/fetch;
9. group and Owner↔beta rooms remain isolated;
10. live site shows protocol and fingerprints without exposing secrets.
