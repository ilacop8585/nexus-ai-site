# NEXUS Word — Manus Parity Blueprint
Date: 2026-10-08
Status: RESEARCH / ARCHITECTURE ONLY
Production impact: NONE

## Goal

Reproduce the *functional architecture* that makes Manus powerful, without copying proprietary code, private implementation details, branding, or exact visual design.

The target is not "make NEXUS look like Manus".
The target is: make NEXUS behave like a unified agent operating system.

Core principle:

User intent
→ persistent Agent
→ Task runtime
→ Project context
→ Skills
→ Connectors / Data Sources
→ Browser / Computer
→ Files / Artifacts
→ Human confirmations
→ Webhooks / Notifications
→ Versioned outputs / deployment
→ continuity across devices.

---

## 1. What Manus actually is

Manus is not one chatbot.

Its product surface combines:

1. Chat mode
2. Agent mode
3. Persistent agents
4. Projects
5. Tasks and subtasks
6. Skills
7. Connectors
8. Data integrations
9. Cloud Browser
10. My Browser / browser clients
11. My Computer / persistent cloud computer / local computer access
12. Files
13. Artifact Library
14. Website / WebApp builder
15. Website checkpoints and publishing
16. Structured output
17. Webhooks
18. OAuth Open Apps
19. API keys
20. Team workspace
21. Roles / Team Admin / Owner
22. SSO / security settings
23. Usage / credits analytics
24. Desktop app / voice / local files
25. Slack / LINE channels
26. Scheduled work
27. Human takeover / action confirmation
28. Cross-task references / memory-like retrieval.

The product advantage is the orchestration layer connecting all of these.

---

## 2. Manus concepts → NEXUS concepts

### Chat / Agent mode

Manus:
- Chat for low-cost conversational work.
- Agent mode for autonomous multi-step execution.
- Profiles: lite / standard / max.

NEXUS target:
- CHAT = included conversational path.
- AGENT = queued autonomous task.
- LOCAL = cheap/local model first.
- HYBRID = local + paid/cloud escalation.
- MAX = strongest available paid models / multi-agent review.

Do not expose provider/model complexity by default. Expose an optional Advanced routing panel.

### Projects

Manus:
- project name
- persistent instruction
- project-default connectors
- project-specific skill library
- tasks inherit project context.

NEXUS target tables:
- nexus_projects
- nexus_project_members
- nexus_project_instructions
- nexus_project_connectors
- nexus_project_skills
- nexus_project_files
- nexus_project_tasks

Every task must optionally belong to one project.

Project context precedence:
task explicit override
> project defaults
> user defaults
> platform defaults.

### Agents

Manus:
- persistent named agents
- nickname / description
- one persistent main task
- agent subtasks.

NEXUS target:
- nexus_agents
- nexus_agent_members
- nexus_agent_profiles
- nexus_agent_main_threads
- nexus_agent_subtasks

Examples:
- NEXUS CEO Assistant
- QA Agent
- Revenue Hunter
- SEO Agent
- Cybersecurity Agent
- Travel Agent
- Creative Studio Agent.

Each Agent should have:
- identity
- mission
- allowed tools
- allowed connectors
- allowed projects
- routing policy
- cost ceiling
- approval policy
- memory scope
- schedule / trigger policy.

### Tasks

Manus:
- async execution
- running / waiting / stopped / error
- follow-up messages
- background jobs may continue after main agent stops
- hidden automated tasks
- task references
- human confirmations
- structured outputs.

NEXUS target task states:
- queued
- planning
- running
- waiting_input
- waiting_confirmation
- background_running
- completed
- failed
- cancelled

Add:
- parent_task_id
- root_task_id
- project_id
- agent_id
- created_by_app_id
- visibility
- interactive_mode
- hidden_from_task_list
- structured_output_schema
- structured_output_result
- cost_budget
- routing_profile
- approval_policy.

### Plan / live execution view

Manus surfaces:
- plan_update
- new_plan_step
- tool_used
- status_update
- waiting descriptions.

NEXUS target:
- nexus_task_events append-only stream
- event types:
  - task_created
  - plan_created
  - plan_step_added
  - plan_step_started
  - plan_step_done
  - plan_step_failed
  - tool_started
  - tool_completed
  - tool_failed
  - waiting_for_user
  - waiting_for_confirmation
  - subtask_created
  - artifact_created
  - task_completed
  - task_failed.

UI:
live timeline / execution console, not just a status badge.

### Human confirmations

Before risky actions:
- sending email
- deleting data
- spending money
- publishing
- changing production
- granting broad scopes
- sending social content.

NEXUS target:
- nexus_action_requests
- typed JSON schema for expected confirmation input
- confirm / reject / modify
- action expires
- audit trail.

Never invent a universal "yes/no"; action schema is tool-specific.

---

## 3. Skills — one of Manus's strongest ideas

Manus Skills are portable filesystem workflows with SKILL.md plus optional:
- scripts/
- references/
- templates/

Ownership scopes:
- official
- personal
- team
- project
- app/private.

NEXUS must implement the same *concept* with its own format.

Target:
- nexus_skills
- nexus_skill_versions
- nexus_skill_installations
- nexus_project_skills
- nexus_agent_skills

NEXUS skill package:
- NEXUS_SKILL.md
- metadata YAML
- optional scripts/
- references/
- templates/
- tests/
- permissions.json

Installation sources:
- built-in
- upload .nskill
- zip
- GitHub URL
- Team Library
- Project Library.

Security:
- static scanner before install
- executable-script warning
- requested capabilities shown to user
- sandbox execution
- version pinning
- signature/hash
- disable / uninstall / rollback.

Selection behavior:
- enabled skills = available
- forced skills = must execute
- project skills = inherited by tasks
- agent skills = identity-level capabilities
- slash command discovery in composer.

This is far more important than adding hundreds of hard-coded buttons.

---

## 4. Connectors / Plugins

Manus's "plugin" architecture is actually four layers:

A. Connectors
- OAuth/API/MCP connections to user-owned services.

B. Skills
- workflow logic.

C. Data Integrations
- platform-managed premium data sources.

D. Open Apps
- external apps acting on behalf of a user through OAuth2/scopes.

NEXUS currently has:
- plugins.json
- nexus_user_plugins
- OAuth connector bridge concepts
- MCP / OAuth / API / webhook planned paths.

NEXUS target unification:

### Connector Registry
- nexus_connectors
- nexus_connector_versions
- nexus_user_connector_accounts
- nexus_connector_credentials (server encrypted only)
- nexus_connector_grants
- nexus_connector_health

Connector states:
- available
- disconnected
- connecting
- connected
- degraded
- expired
- revoked
- unsupported.

Connector types:
- OAuth2
- API key
- PAT
- MCP
- OpenAPI
- internal service
- local bridge.

### Default resolution
Explicit task connectors
> project default connectors
> agent defaults
> user defaults.

### Connector settings
Per connector:
- account/workspace
- enabled by default
- project scope
- permissions
- last successful call
- token expiry
- reconnect
- disconnect
- data retention policy
- estimated cost / rate limit.

### Custom connectors
Users/Owner should be able to add:
- remote MCP URL
- local MCP bridge
- OpenAPI spec
- generic REST API definition
- webhook receiver.

Never store secrets in browser localStorage.

---

## 5. Data Integrations

Manus also provides platform-managed third-party data sources that require no user API key.

NEXUS equivalent:
- nexus_data_sources
- nexus_data_source_quotas
- nexus_data_cache

Examples:
- web search
- SEC/company data
- YouTube trends
- TikTok trends
- maps
- SEO/search data
- public financial/economic feeds.

Router chooses data sources automatically from task intent.

Difference from Connector:
- Connector = acts on user's account/data.
- Data Source = platform-provided information service.

---

## 6. Browser / Computer architecture

### Cloud Browser
Capabilities:
- browser inside agent task
- persistent login state if user permits
- manual takeover
- manage/disable stored login state.

NEXUS target:
- Browser Operator worker
- browser session ID
- isolated profile per user/project
- login-state vault
- explicit consent before saving credentials/session
- takeover mode
- screenshots / network / DOM logs
- audit events.

Settings:
Browser:
- enable browser agent
- allow login-state persistence
- saved sites
- revoke individual site session
- clear all browser sessions
- default browser region
- download policy
- approval policy.

### My Browser
Manus supports online local browser clients selected by the user.

NEXUS target:
- nexus_browser_clients
- browser client heartbeat
- user selects one client
- task enters waiting_for_browser
- approval/selection event
- bridge via Desktop Commander / future browser extension.

### My Computer
Manus supports:
- local files/tools through CLI
- authorized folders
- persistent cloud computer
- Web Terminal
- SSH
- CPU/RAM/storage metrics
- plan/location/storage settings.

NEXUS already has a major advantage:
- Desktop Commander
- PC/Mac nodes
- local Qwen
- worker
- NAS/server
- Tailscale.

NEXUS target:
- nexus_computer_clients
- nexus_computer_mounts
- nexus_computer_capabilities
- nexus_computer_metrics
- nexus_computer_sessions
- nexus_computer_grants.

Settings:
My Computer:
- registered computers
- online/offline
- capabilities
- authorized folders
- allow CLI
- allow GUI
- allow browser
- allow file write
- allow package install
- allow restart (default OFF)
- resource caps
- GPU permission
- task concurrency
- wake-on-LAN
- logs
- revoke client.

No task should silently gain access to all local disks.

---

## 7. Files and Artifact Library

Manus separates input Files from generated Artifacts.

NEXUS should formalize the same split.

Input files:
- uploads attached to task/project
- temporary or persistent Library items.

Artifacts:
- generated documents
- spreadsheets
- slides
- images
- audio/video
- websites
- source archives
- APK/EXE/DEB
- reports.

Target:
- nexus_files
- nexus_file_versions
- nexus_artifacts
- nexus_artifact_versions
- nexus_artifact_favorites
- nexus_artifact_links

Every artifact tracks:
- creation task
- latest editing task
- type
- version
- storage object
- checksum
- preview
- visibility
- favorite
- provenance.

---

## 8. Website / App Builder

Manus treats generated websites as first-class versioned artifacts.

Capabilities to reproduce:
- website entity
- checkpoints
- publish state
- live URLs
- public/team/private visibility
- publish latest checkpoint
- update metadata without deployment
- custom domain
- analytics
- leads
- Stripe
- file storage
- notifications.

NEXUS Foundry should evolve into:
- nexus_sites
- nexus_site_versions
- nexus_deployments
- nexus_domains
- nexus_site_analytics
- nexus_site_events.

Important:
Git commit/checkpoint != live deployment.

Owner UI must clearly show:
- latest build
- published build
- deployment status
- rollback/checkpoint
- visibility.

---

## 9. Webhooks and event bus

Manus uses signed webhooks for lifecycle changes.

NEXUS already has event concepts in Beta Live.
Generalize them.

Target:
- nexus_events global append-only bus
- nexus_webhooks
- nexus_webhook_deliveries
- nexus_webhook_attempts

Event examples:
- task.created
- task.waiting
- task.completed
- task.failed
- artifact.created
- connector.connected
- connector.expired
- project.changed
- agent.subtask_created
- website.published
- beta.ticket_created
- beta.retest_requested.

Security:
- signed webhooks
- timestamp window
- replay protection
- retry with exponential backoff
- dead-letter queue
- per-webhook event filters.

---

## 10. Developer settings / Open Apps

Manus has:
- API keys
- OAuth2 Open Apps
- scopes
- PKCE
- per-app secrets
- connector grants
- task visibility boundaries
- webhooks.

NEXUS target:
Developer Settings:
- API keys
- OAuth Apps
- redirect URIs
- scopes
- secrets rotation
- webhook URL
- connector grants
- app-owned skills
- usage
- revoke.

Suggested scopes:
- task:create
- task:read
- task:manage
- project:create
- project:read
- artifact:read
- file:upload
- connector:use
- browser:use
- website:publish
- agent:interact
- admin:* (trusted internal only).

Do not create a single universal API token with unlimited authority.

---

## 11. Settings Hub — functional parity target

NEXUS settings should become a top-level product surface.

### Account
- profile
- language
- timezone
- theme
- notifications
- default model/routing profile
- data/privacy preferences.

### Agent
- Chat / Agent default
- local-first / balanced / max
- interactive mode
- autonomy level
- confirmation policy
- max task duration
- max cost / daily budget
- default skills
- default connectors.

### Projects
- default project
- instructions
- connectors
- skills
- collaborators
- visibility.

### Skills
- Official
- Personal
- Team
- Project
- Installed
- Enabled by default
- Import file
- Import GitHub
- version/update/rollback.

### My Plugins / Connectors
- connected services
- Add Connector
- OAuth status
- MCP
- custom API
- account switch
- permissions
- disconnect.

### Browser
- enable
- saved login state
- remembered sites
- clear site state
- browser clients
- takeover permissions.

### My Computer
- PC/Mac nodes
- authorized folders
- command permissions
- GUI permissions
- GPU/CPU/RAM limits
- concurrency
- logs
- revoke.

### Library
- file retention
- artifact defaults
- version history
- favorites
- sharing.

### Notifications
- in-app
- email
- push
- Slack/LINE/Telegram later
- event subscriptions
- quiet hours
- severity filters.

### Automation / Schedules
- recurring tasks
- event-driven tasks
- condition watchers
- schedules list
- enable/disable
- last run / next run
- failure policy.

### Team / Organization
- invite
- members
- roles
- groups
- project permissions
- Team Skills
- Team Connectors
- usage.

### Security
- sessions
- MFA
- SSO
- verified domains
- device list
- API keys
- OAuth Apps
- audit log
- E2EE NEXUS Private.

### Developer
- API keys
- Open Apps
- scopes
- webhooks
- MCP servers
- OpenAPI
- usage logs
- request logs
- rate limits.

### Billing / Usage
- credits
- compute spend
- model spend
- per-user usage
- per-agent usage
- per-project usage
- per-connector usage
- history.

---

## 12. Cross-task references / continuity

Manus allows a new task to reference older tasks on demand instead of injecting every prior conversation into context.

NEXUS target:
- nexus_task_references
- maximum reference set
- lazy retrieval
- search / outline / read ranges
- access check at read time.

This should become the implementation foundation behind NEXUS SYNC:
new task → references canonical prior tasks/checkpoints → fetch only needed context.

Do not stuff all historical content into every model prompt.

---

## 13. Structured output

NEXUS agent tasks should optionally carry a JSON Schema.

Use cases:
- beta classification
- SEO audit
- lead extraction
- product catalog
- test result
- deployment report
- monitoring status
- invoice parsing.

Pipeline:
agent executes normally
→ extraction/validation stage
→ schema-valid result
→ event + stored structured output.

---

## 14. Scheduling / automations

Manus exposes scheduled work through product channels such as Slack.

NEXUS target:
- nexus_automations
- schedule
- condition
- task template
- project
- agent
- connector set
- enabled
- last_run
- next_run
- failure_count
- notification policy.

Examples:
- daily market report
- morning email summary
- website uptime
- SEO change watch
- Beta ticket monitor
- revenue opportunities.

---

## 15. Desktop / voice / multi-device

Manus Studio combines:
- desktop workspace
- voice commands
- local files
- computer use
- agents continuing across devices.

NEXUS target:
Android / Windows / macOS native apps share:
- same account
- same agent identities
- same project list
- same task list
- same artifacts
- same notifications
- device-specific computer/browser capability.

Do not build the native apps as WebView wrappers.

---

## 16. What NEXUS already has

LIVE / substantial:
- account/auth
- persistent conversations
- job queue
- local worker
- local Qwen path
- files/library foundation
- credits
- plugin catalog
- per-user plugin state
- connector/OAuth groundwork
- Foundry worker capability
- Beta Workspace
- Beta observer
- Beta Live
- Owner notifications
- NEXUS Private MLS E2EE
- Admin Center
- Social Publisher scaffold
- agent/capability manifests.

PARTIAL:
- OAuth external connectors
- Foundry full lifecycle
- native app distribution
- automated patch→test→deploy loop
- attachment opening in Beta Admin.

PLANNED / major gap:
- Project system
- portable Skills
- persistent custom Agent registry
- unified Task event stream
- general confirmation engine
- Browser Operator
- My Browser clients
- governed My Computer UI
- generic Webhooks
- Artifact versioning
- Website checkpoints / deployments
- Developer Open Apps / scopes
- general schedules/automations
- full Settings Hub.

---

## 17. Build order

Do not attempt all UI first.

### Wave 1 — Agent OS kernel
1. nexus_projects
2. nexus_agents
3. nexus_task_events
4. nexus_action_requests
5. nexus_task_references
6. structured_output fields
7. project/agent/task APIs.

### Wave 2 — Skills + Connectors
1. Skill Registry
2. package/install/update/rollback
3. project skill library
4. agent skill policy
5. connector registry normalization
6. user/project/agent connector defaults
7. permission/scopes UI.

### Wave 3 — Settings Hub
Build complete Settings route around real backend capabilities:
- account
- agents
- projects
- skills
- plugins/connectors
- browser
- computer
- notifications
- security
- developer
- usage.

Never render a fake toggle.

### Wave 4 — Computer / Browser
- browser clients
- local computer clients
- authorized roots
- per-action approval
- persistent sessions
- takeover
- metrics.

### Wave 5 — Artifact / Foundry
- artifacts
- versions
- websites
- checkpoints
- publish/rollback
- domains
- analytics.

### Wave 6 — Developer platform
- API
- OAuth apps
- scopes
- signed webhooks
- app-owned skills
- connector grants
- rate limiting.

### Wave 7 — Schedules + multi-channel
- schedules
- Slack
- LINE/Telegram where appropriate
- push
- email
- native apps.

---

## 18. Product rule

Functional parity does NOT mean visual cloning.

NEXUS must:
- use original UI/branding;
- implement its own code;
- expose only verified capabilities;
- preserve local-first routing and cost controls;
- leverage NEXUS's unique advantage: user's own PCs/Mac/NAS/local models;
- keep Beta/QA integrated directly into the product;
- maintain Owner change control for production-risk actions.

---

## 19. The NEXUS advantage over Manus

If executed correctly, NEXUS can differ in useful ways:

1. local-first compute, not cloud-only;
2. user-owned hardware fleet;
3. explicit multi-model orchestration;
4. persistent AI-company / department structure;
5. integrated Beta feedback → QA → fix pipeline;
6. private MLS human channel;
7. stronger Owner operational dashboard;
8. lower marginal compute cost using local models;
9. deeper PC/Mac/NAS integration;
10. transparent routing and cost governance.

The goal is not a Manus clone.
The goal is a NEXUS Agent Operating System that reaches functional parity in the strongest Manus patterns and then extends beyond them.
