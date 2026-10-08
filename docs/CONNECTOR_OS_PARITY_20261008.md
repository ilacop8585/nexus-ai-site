# NEXUS Connector OS — Parity Blueprint
Date: 2026-10-08
Status: architecture / implementation branch
Production impact: NONE

## Why this is P0

A closed catalog of hard-coded integrations cannot compete with Manus, ChatGPT, Claude or Abacus.

Current NEXUS state:
- plugins.json contains 60 catalog entries.
- 57 are backend_required.
- 3 are marked active.
- only Neon and one generic MCP slot are currently connectable from the UI.
- the web client still contains a fallback message: "This connector type is not supported yet."

This is not acceptable as the final integration model.

## Competitive pattern verified

### Manus
- built-in connectors;
- BYOK connectors;
- MCP connectors;
- custom API connector when no official connector exists;
- custom MCP connector;
- per-user defaults;
- per-Project defaults;
- explicit connector IDs per task;
- OAuth / permission and cost control.

### ChatGPT
- plugin directory;
- apps + Skills;
- custom MCP apps;
- custom MCP server;
- local MCP apps on Desktop;
- read/write tools;
- workspace permissions and approval boundaries.

### Claude
- built-in connectors;
- remote custom MCP connector;
- users can build a remote MCP server for any tool;
- OAuth or API credential authentication;
- local MCP remains available on Claude Desktop.

### Abacus
- first-party user connectors;
- organization connectors;
- Generic OAuth2 connector for APIs without a dedicated integration;
- user-level and organization-level MCP servers;
- RBAC / permission-aware connector models.

## NEXUS target: Connect Anything

The user must never be blocked only because NEXUS did not pre-build a logo-specific connector.

Supported connector families:

1. builtin
2. oauth2_builtin
3. oauth2_generic
4. api_key / BYOK
5. mcp_remote
6. mcp_local
7. openapi
8. webhook
9. browser_bridge
10. internal_service

Fallback order for a service with no official integration:

official connector
> remote MCP
> Generic OAuth2 + OpenAPI/API definition
> API key + OpenAPI/API definition
> webhook
> Browser/Computer bridge.

## Core data model

### connector definitions
Reusable service templates and capabilities.

### connector instances
One user can connect:
- multiple Gmail accounts;
- multiple GitHub organizations;
- multiple MCP servers;
- multiple API endpoints;
- the same service under different credentials.

A single "plugin_id = mcp" row is not sufficient.

### credentials
No plaintext secrets in browser or ordinary database rows.
The database stores only a vault reference and non-secret metadata.

### tools
Every connected instance exposes zero or more discovered tools.

For MCP:
initialize -> tools/list -> normalized tool records.

For OpenAPI:
OpenAPI operations -> normalized tools.

For generic OAuth/API:
tool definitions may come from OpenAPI, curated templates or explicit user definitions.

### grants
Connector instances can be allowed for:
- user default
- Project
- Agent
- explicit task.

Resolution:
explicit task
> Agent grant
> Project grant
> user default.

### health
Each instance tracks:
- connected
- degraded
- expired
- revoked
- error
- last successful probe
- last error code
- reconnect requirement.

### permissions
Every tool has risk metadata:
- read
- write
- delete
- financial
- publish
- external_message
- production_change.

High-risk actions must integrate with the future general confirmation engine.

## UI target

Tools & Connectors becomes four clear surfaces:

### Installed
Only actually usable connected capabilities.

### Directory
Official/built-in connectors that are really connectable.

### Add custom
Always present:
- Remote MCP
- Generic OAuth2
- API key
- OpenAPI
- Webhook
- Local bridge (desktop)

Only modes whose backend is verified may be enabled.

### Preview / roadmap
Non-operational integrations are visually separated from usable ones.
No disabled "Connect" button that implies the integration works.

## Security requirements

- SSRF protection for arbitrary URLs.
- HTTPS remote endpoints by default.
- block loopback/private ranges from cloud connector workers.
- separate local bridge for LAN/local MCP.
- OAuth state + PKCE.
- encrypted credential vault.
- per-user credential isolation.
- tool schema validation.
- maximum response sizes.
- timeout and rate limits.
- audit log for every connector action.
- prompt-injection boundary for tool output.
- explicit approval for destructive/high-impact actions.
- revoke and delete credential path.
- no secrets in logs.

## Shipping gates

Do not market "Connect Anything" until:
1. multiple MCP instances per user PASS;
2. generic OAuth2 connection PASS;
3. OpenAPI import/discovery PASS;
4. API-key connector PASS;
5. credentials remain outside browser/plain DB PASS;
6. Project/Agent grants PASS;
7. reconnect/revoke PASS;
8. connector action audit PASS;
9. unsupported service can be connected without a NEXUS code deployment PASS.

## Immediate production UX rule

Until those gates pass:
- show real available connectors first;
- keep planned connector catalog clearly marked as preview;
- promote the working Custom MCP route;
- never count planned integrations as connected/available.
