# Product Architecture Benchmark — Manus / ChatGPT / Claude / Abacus
Date: 2026-10-08
Status: Research benchmark
Production impact: NONE

## Purpose

NEXUS must not copy only plugins or individual screens. The real competitive pattern is an integrated AI workspace / agent operating system.

Target benchmark:
Account / Workspace
→ Projects
→ Chat / Task / Agent mode
→ Context / Memory
→ Skills
→ Connectors / Tools
→ Browser / Computer
→ Files / Artifacts
→ Automations
→ Team / Sharing
→ Admin / Security
→ Developer Platform
→ Billing / Usage.

The goal is functional and information-architecture parity with leading products, using original NEXUS branding and code.

---

# 1. Shared product anatomy across the four platforms

The strongest platforms separate the following layers.

## A. Global shell
Persistent product navigation:
- recent conversations/tasks;
- projects;
- library/files/artifacts;
- connectors/plugins;
- scheduled/automated work;
- settings/account;
- team/admin where applicable.

## B. Work mode selector
The user chooses *how* AI should work:
- conversation/chat;
- agent/work/cowork;
- coding/developer;
- stronger/lighter effort profiles;
- custom agent/bot in some products.

This choice is explicit and affects execution semantics, not only the selected model.

## C. Context container
A Project or workspace owns:
- instructions;
- files/knowledge;
- memory boundary;
- collaborators;
- skills;
- connectors;
- sometimes model/tool defaults.

## D. Execution object
Long-running work is not treated as one synchronous chat response.

A Task can have:
- status;
- plan;
- progress events;
- subtasks/background work;
- connector/tool calls;
- user confirmation gates;
- output/artifacts;
- retry/error state.

## E. Capability layer
Capabilities are modular:
- skills;
- plugins/apps/connectors;
- browser;
- local computer;
- code execution;
- data sources;
- external services.

## F. Artifact layer
Generated output is not trapped inside chat.

Artifacts have:
- a type;
- source task;
- version or edit lineage;
- preview/download/publish surface;
- sharing/visibility;
- sometimes connected app access.

## G. Governance layer
Distinct controls exist for:
- personal settings;
- project settings;
- organization/workspace settings;
- permissions/roles;
- security;
- developer/API settings;
- usage/billing.

---

# 2. Manus — most explicit Agent OS model

## Primary entities

- Task
- Project
- Agent
- Skill
- Connector
- File
- Artifact
- Website
- Browser client
- Webhook
- Open App
- API credential
- Usage record

## Task runtime

Manus tasks are asynchronous execution objects.

A task may carry:
- message;
- Project ID;
- connector IDs;
- enabled Skills;
- forced Skills;
- task references;
- interactive mode;
- visibility;
- agent profile;
- structured output JSON schema.

Profiles:
- lite
- standard
- max

Important difference from normal chat:
the task can continue running, pause for input, request confirmation, and keep background jobs alive after the main agent run stops.

## Task event model

Events include:
- plan/progress;
- status updates;
- waiting for input;
- action confirmation;
- background work;
- completion/error.

The client should not infer completion just because one agent turn stopped.

## Projects

Projects:
- group related work;
- apply shared instructions automatically;
- provide default connectors;
- can carry skills/context.

Project is a real runtime namespace, not just a visual folder.

## Agents

Persistent named AI entities:
- nickname;
- description;
- persistent main task/thread.

A default instant-messaging agent also exists.

## Task references

A task can reference previous tasks without injecting their entire content.

The agent can inspect referenced work lazily:
- outline;
- search;
- read relevant sections/files.

This is an important pattern for NEXUS continuity.

## Skills

Skills are reusable workflow/instruction packages.

They can be:
- default-enabled;
- enabled per task;
- forced per task.

The skill system is independent from connectors.

## Connectors

Installed account connectors are resolved by ID.
Connectors can be inherited from Projects or explicitly supplied to Tasks.

## Browser

Manus distinguishes browser execution from task logic.
A task can pause asking for a connected local browser client.
The user selects an online browser client and confirms the action.

## Files vs Artifacts

Input files and generated artifacts are separate concepts.

Artifacts are generated outputs stored in a Library and classified as:
- website;
- mobile app;
- game;
- documents;
- slides;
- spreadsheets;
- images;
- videos;
- audio;
- others.

Artifacts keep provenance to the producing Task.

## Websites

Websites are first-class entities:
- site ID;
- checkpoints/versions;
- published version;
- live URLs;
- visibility;
- metadata;
- publish action.

A successful checkpoint is not automatically the live version.

## Webhooks

Task lifecycle events can be delivered to external systems through signed webhooks.

## Developer platform

Manus exposes:
- API keys;
- OAuth2 Open Apps;
- scopes;
- PKCE;
- task visibility boundaries;
- connector permissions;
- webhooks.

This makes Manus itself a platform other products can build on.

---

# 3. ChatGPT — integrated multi-surface workspace

## Main structural layers

ChatGPT currently combines:
- Chat
- Work
- Codex
- Projects
- Plugins
- Scheduled tasks
- Library/files
- Memory/personalization
- desktop local context
- cloud browser
- workspace/admin controls.

## Chat vs Work vs Codex

These are different execution surfaces.

### Chat
Conversation-oriented interaction.

### Work
Persistent task/workspace execution that can:
- research;
- analyze;
- use files/apps;
- operate a cloud browser;
- continue while the user leaves;
- pause for sign-in/input/confirmation;
- on desktop, work with authorized local files/apps.

### Codex
Developer/coding-oriented environment with different local/remote project semantics.

NEXUS should copy this *mode separation principle*.

## Projects

Projects combine:
- chats;
- files;
- instructions;
- shared context;
- memory policy.

A project can use:
- default memory;
- project-only memory.

Shared Projects isolate personal memory from project context.

This is stronger than a folder and must map to an actual context boundary.

## Plugins

A plugin is broader than one API connector.

A plugin may package:
- Skills;
- connected Apps;
- app templates;
- extensions/UI.

Directory scopes include:
- public;
- workspace;
- personal;
- installed.

Admins control:
- installation;
- publishing;
- included app access;
- role permissions.

## Cloud Browser

Work has a cloud computer/browser capable of:
- browsing;
- clicks;
- forms;
- signed-in supported sites;
- continuing after the client closes;
- pausing for approval or login.

## Desktop Browser

ChatGPT Desktop also has a browser surface with:
- shared visual context;
- tabs;
- download handling;
- richer authenticated state;
- explicit authorization.

## Memory

Memory is a product-level context service, not just prompt history.

Potential sources include:
- past chats;
- remembered information;
- custom instructions;
- Library files;
- connected apps.

Project memory provides a separate boundary.

## Scheduled

Scheduled tasks are a separate product surface:
- one-time;
- recurring;
- condition-monitoring;
- notification delivery.

## Writing/code surfaces

Reusable outputs are surfaced in editable blocks rather than buried in normal prose.
This reduces friction between generation and editing.

## Workspace governance

Separate admin surfaces manage:
- plugins;
- apps;
- roles;
- workspace access;
- permissions.

---

# 4. Claude — Project + Artifact + Connector centric model

## Projects

Claude Projects provide:
- Project knowledge base;
- uploaded documents/code/text;
- Project instructions;
- RAG expansion for large knowledge sets.

Important distinction:
chat content is not automatically shared across all project chats unless relevant content is explicitly placed into Project knowledge/context.

## Artifacts

Artifacts are a major independent surface.

They:
- separate generated work from chat;
- can be edited/used interactively;
- can be shared/published;
- can use connected applications;
- have organization governance controls.

Artifacts may request app/tool access and users approve the connected tools they may use.

This turns generated content into an active application surface.

## Connectors

Two major classes:

### Remote connectors
Cloud services usable across Claude surfaces.

### Desktop extensions / local MCP
Local machine resources:
- filesystem;
- localhost;
- desktop applications;
- internal corporate systems.

Desktop extensions are installable packages and can be centrally allowed/blocked by organization owners.

## Organization controls

Team/Enterprise owners control:
- feature availability;
- Artifact availability;
- Artifact sharing;
- connector usage;
- extension allowlists;
- custom extensions;
- roles/access.

## Product lesson

Claude's strength is not only the chat response quality.
The architecture clearly separates:
Project context
→ conversation
→ Artifact output
→ connector permissions
→ organization controls.

---

# 5. Abacus — broadest "AI operating suite" pattern

## Core surfaces

Abacus combines:
- Super Assistant
- Chat mode
- AI Agent / CoWork
- Projects
- Skills
- Connectors
- Custom Bots / Agent Templates
- Agent Swarms
- Desktop
- CLI
- VS Code
- model/provider controls
- scheduled tasks
- application building
- admin/permissions.

## Chat vs CoWork

Chat is conventional conversation/model use.

CoWork is autonomous multi-step work:
- local files;
- web/browser workflows;
- long-running tasks;
- scheduled tasks;
- sub-agent coordination;
- professional editable outputs.

## Skills

Skills use SKILL.md-style packages.

Scopes:
- project;
- global.

Sources:
- local directories;
- zip;
- GitHub;
- system skill library.

Skills can be:
- enabled/disabled;
- selected for a specific agent task;
- added to Projects.

## Projects

Projects are execution containers where advanced functions such as:
- Skills;
- Agent tasks;
- Swarms;
- shared project context
can be applied.

## Agent Swarms

Complex Project tasks can create:
- one master conversation;
- multiple subtask conversations/agents;
- parallel execution.

## Agent templates / custom bots

Agent architectures can be generated, reviewed, parameterized and shared with other users.

## Desktop settings hierarchy

Settings exist at:
- user/global level;
- workspace/project level;
- session override;
- environment;
- editor level.

This is an important architecture pattern: defaults cascade rather than being duplicated.

## Permissions

Abacus exposes explicit permission modes:
- allow;
- ask;
- deny.

Users can switch permission mode quickly.

## Providers

Provider/model configuration is independent from project/task structure:
- external subscriptions;
- API keys;
- local model servers;
- multiple model providers.

## Connectors

User connectors and organization connectors are different things.

User connector:
- acts as the current user;
- source permissions follow that user.

Organization connector:
- shared/admin-configured credentials;
- ingestion/shared service context.

Permission-aware connectors preserve external access controls.

## App operations

Built applications can have operational agents:
- test agent;
- SEO agent;
- self-healing agent.

This is very relevant to NEXUS Foundry.

---

# 6. Competitive information architecture

A strong unified NEXUS shell should not expose every internal subsystem as a peer button.

## Recommended left navigation

### Work
- New
- Recent
- Tasks

### Projects
- Project list
- shared Projects

### Library
- Files
- Artifacts
- Websites / Apps

### Automations
- Scheduled
- Watches
- Webhooks

### Platform
- Connectors
- Skills
- Agents

Then:
- Beta Workspace (role-gated)
- Admin (Owner/admin only)

Account/settings should live at the bottom/profile area, not as another work object.

## Top workspace bar

Current Project
Current mode:
- Chat
- Agent
- Work
- Code

Optional:
- effort/routing
- Agent identity
- context/cost indicator.

## Main center

Conversation / task transcript.

## Execution side panel

When work is agentic:
- plan;
- steps;
- tool calls;
- subtasks;
- pending approvals;
- errors;
- runtime status.

This should stay visible instead of mixing execution logs into the chat transcript.

## Right context panel

Contextual, not always visible:
- Project instructions;
- attached files;
- enabled Skills;
- connected tools;
- Agent;
- sharing/collaborators.

## Output surface

Generated Artifact can open beside/over the conversation:
- document;
- spreadsheet;
- slide;
- image;
- app/site;
- code preview.

---

# 7. NEXUS current structural weaknesses

## 1. Navigation is feature-shaped, not workflow-shaped

Current sidebar exposes peer buttons such as:
- Tools
- Settings
- Social Publisher
- Centro Beta
- NEXUS Private
- Admin Center.

These are different abstraction levels.

Admin, private messaging, product work, user settings and connectors should not all compete at the same hierarchy level.

## 2. Chat is still the dominant object

Tasks/jobs exist, but the UI still feels like:
chat + modal windows.

Competitive products increasingly use:
workspace + task + artifact.

## 3. Jobs lack a first-class execution surface

Need:
- plan;
- step timeline;
- background jobs;
- tool calls;
- user approvals;
- retry/error state.

## 4. Library is not yet an Artifact system

Need a distinction:
Input file != generated Artifact.

Artifact needs:
- provenance;
- type;
- version;
- source task;
- preview;
- sharing;
- favorite;
- publish state.

## 5. Project context is only V1

NEXUS now has Projects/Agents/Skills, but it still needs:
- Project file/knowledge base;
- Project memory boundary;
- Project collaborators;
- connector defaults;
- task list;
- Artifact list;
- permissions.

## 6. Settings is still too small

Need separate sections:
- Personal
- Models & Routing
- Memory
- Projects
- Agents
- Skills
- Connectors
- Browser
- Computers
- Notifications
- Automations
- Security
- Developer
- Billing/Usage.

## 7. Browser and computer capabilities are not productized

NEXUS has strong underlying PC/Mac infrastructure but lacks:
- device registry;
- per-device permissions;
- folders/scopes;
- browser client list;
- takeover/approval;
- health;
- revoke.

## 8. Team/organization model is incomplete

Need:
- members;
- roles;
- groups;
- shared Projects;
- team Skills;
- team Connectors;
- admin policies;
- audit;
- spend/usage.

## 9. Developer platform is incomplete

Need:
- API keys;
- OAuth apps;
- scopes;
- webhooks;
- rate limits;
- logs;
- developer-owned integrations.

## 10. Visual design is not using a real design system

Need:
- layout grid;
- navigation hierarchy;
- shared component library;
- spacing/typography scale;
- interaction states;
- responsive behavior;
- accessibility;
- consistent modal/panel strategy.

---

# 8. Target NEXUS product model

NEXUS should become:

NEXUS Workspace
├─ Projects
│  ├─ Chats
│  ├─ Tasks
│  ├─ Files / Knowledge
│  ├─ Artifacts
│  ├─ Agents
│  ├─ Skills
│  ├─ Connectors
│  └─ Collaborators
├─ Global Tasks
├─ Library
│  ├─ Inputs
│  └─ Artifacts
├─ Automations
├─ Agents
├─ Skills
├─ Connectors
├─ Devices
│  ├─ Browsers
│  └─ Computers
├─ Developer
└─ Settings

Owner/Admin layer:
NEXUS Admin
├─ Users
├─ Beta
├─ Notifications
├─ AI operations
├─ QA
├─ Deployments
├─ Usage / Cost
├─ Security / Audit
└─ Organization policy

Private human messaging should remain a distinct collaboration surface, not mixed with task execution or AI-readable Beta workspace.

---

# 9. Priority build order after the benchmark

P0 — Product shell redesign
- workflow-shaped navigation;
- mode selector;
- current Project;
- execution side panel;
- context panel;
- responsive desktop/mobile architecture.

P0 — Task runtime
- event stream;
- plan;
- subtasks;
- waiting/approval;
- background work;
- structured output.

P0 — Universal Connector OS
- multi-instance;
- MCP;
- Generic OAuth2;
- OpenAPI;
- BYOK;
- Project/Agent grants.

P1 — Project V2
- Project files/knowledge;
- memory isolation;
- collaborators;
- connector/skill defaults;
- task/artifact views.

P1 — Artifact OS
- artifacts as versioned first-class outputs.

P1 — Device OS
- Cloud browser/local browser/local computer governance.

P1 — Settings / Governance
- user/workspace/org/developer separation.

P2 — Team and developer ecosystem
- roles/groups;
- public/private plugin/skill directory;
- API/Open Apps;
- webhooks;
- usage/billing.

---

# 10. Product rule

Do not literally clone proprietary UI, assets, code or branding.

Replicate:
- information architecture;
- object model;
- workflow clarity;
- persistence;
- permission model;
- agent/task lifecycle;
- tool integration patterns;
- artifact model;
- administrative hierarchy.

NEXUS should look original while feeling as structurally complete as the benchmark products.
