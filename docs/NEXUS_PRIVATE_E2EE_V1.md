# NEXUS Private — MLS E2EE V1

Status: release candidate.

## Scope

NEXUS Private is the human-to-human secure messenger for the Owner and trusted beta testers.

- **Comitiva Beta**: shared Owner + beta group.
- **Privati**: Owner ↔ one beta tester.
- Separate from the monitored Beta Workspace.
- NEXUS AI does not receive NEXUS Private plaintext.

## Protocol actually implemented

- Messaging Layer Security **MLS 1.0 / RFC 9420**.
- Ciphersuite: `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519`.
- Client implementation bundled with the site: **ts-mls 1.6.4**.
- No runtime crypto CDN dependency.
- MLS application plaintext is encrypted on the client before the Neon relay receives it.
- MLS group state and private KeyPackage material are stored only in encrypted local IndexedDB storage.
- Neon stores public device identity keys, KeyPackages, Welcome messages, MLS ciphertext and delivery metadata.
- The messages table has no plaintext column.

The ts-mls project states that its implementation has not undergone a formal security audit. NEXUS therefore identifies the protocol and implementation explicitly and does not market this as Signal Protocol.

## Visible security panel

The room displays:
- protocol and ciphersuite;
- implementation version;
- runtime MLS self-test state;
- current MLS epoch;
- this-device fingerprint;
- enrolled peer-device fingerprints;
- manual out-of-band fingerprint verification;
- whether a real peer MLS message/commit has been authenticated.

The UI may show **E2EE MLS VERIFICATA** only when:
1. runtime self-test passes;
2. the local device has a valid MLS room state;
3. at least one peer MLS message/commit was processed successfully;
4. all displayed peer fingerprints were manually verified.

## Device/bootstrap flow

1. An authorized Owner/beta device creates a stable MLS signing identity locally.
2. The public signing key + fingerprint are registered with Neon.
3. The device publishes several one-time MLS KeyPackages.
4. The Owner creates a group/DM locally and binds the Owner device to it.
5. For a beta device the Owner atomically consumes one KeyPackage, creates an MLS Add Commit + Welcome locally, and sends only those MLS wire objects to Neon.
6. The beta device fetches its Welcome, joins locally, and marks the Welcome consumed.
7. Normal messages use MLS private application messages.
8. Existing members process later Add Commits to advance group epoch.

## Safety properties enforced by server

- RLS enabled on all secure tables.
- Browser uses SECURITY DEFINER RPCs only.
- A device must be cryptographically enrolled in a room to send/fetch room ciphertext.
- KeyPackages are one-time and consumed atomically.
- Welcome retrieval is limited to the owning device.
- Owner→beta membership finalization records the enrolled device and encrypted Commit/Welcome.
- Client message IDs are idempotent to make retry/recovery safe.
- Revoked devices are removed from relay access.

## Privacy split

**NEXUS Private**
- E2EE MLS.
- Server/AI do not receive plaintext.
- Human can explicitly copy selected content into a QA/AI workflow if desired.

**Beta Workspace**
- monitored QA surface;
- Owner and NEXUS AI can inspect it;
- automated observation → Beta Live triage is allowed;
- it must never display the NEXUS Private E2EE badge.

## Verified engineering gates

- Node MLS Owner→Beta→Owner roundtrip: PASS.
- Wire plaintext-presence check: PASS (plaintext absent).
- Bundled browser-target module roundtrip: PASS.
- Runtime self-test exported by bundle: PASS.
- Neon temporary-branch migration: 40 SQL statements PASS in one transaction.
- Secure schema: 7 tables, 19 RPC/helper functions, RLS enabled.
- Plaintext message column: absent.

A real authenticated Owner/Beta production peer exchange remains the final live acceptance after deployment.
