---

# Cyaichi Vision Specification

**Version 3.1**
**Date:** March 2026

## 1. Executive vision

**Cyaichi** is an AI-native orchestration platform for **information collection, processing, retention, and collaboration**, delivered through a **single visual “Studio”** where humans and AI co-create reliable systems.

It exists to close three gaps in today’s AI tooling—**fragmentation, opacity, and forgetfulness**—by unifying workflows, observability, and durable knowledge capture in one place.

**Product promise:** *Build once. Observe everything. Remember forever.*

---

## 2. Problem statement

AI workflows today are usually split across separate tools: chat, agents, pipelines, and notebooks. Teams and individuals repeatedly lose time to:

* rebuilding flows from scratch
* re-explaining context
* debugging “black box” executions
* losing decisions and rationale after a session ends

Cyaichi focuses on making AI work **repeatable, inspectable, and cumulative**.

---

## 3. Design principles

1. **Observable by default**
   Every run is inspectable: inputs, outputs, intermediate transformations, decisions, costs, and failures.

2. **Memory is explicit and governed**
   Notes and records are first-class, permissioned, and reusable by AI with provenance and scope.

3. **Hybrid, not confused**
   Cyaichi supports both durable/agentic workflows and high-throughput pipelines, but it does **not** pretend they have identical semantics.

4. **Human-in-the-loop is normal**
   Approvals, checkpoints, and review are built into the workflow model (especially for side effects).

5. **Evolve safely**
   Users can move between debug, durable, and production operation without rebuilding from scratch (“seamless evolution”).

---

## 3.5 Conceptual model

Cyaichi is built on four simple, universal abstractions that appear everywhere in the Studio:

* **Graph** — a versioned, visual definition of nodes, edges, and subgraphs.
* **Artifact** — the unit of data that flows through the system (payload + metadata + provenance).
* **Run** — a specific execution of a graph, complete with traces, lineage, and outcomes.
* **MemoryItem** — any note, record, decision, or summary that is explicitly stored and governed for future reuse by humans or AI.

---

## 3.6 Workspaces and sharing

Cyaichi supports both solo and team usage through **Workspaces** (the unit of collaboration and policy).

A Workspace is the container for:

* Graphs (and their versions)
* Runs, traces, and lineage history
* Artifacts and derived outputs
* Notes, records, and MemoryItems
* Members, roles, and permissions

Workspaces enable clear boundaries for what is shared, what is private, and what AI is allowed to access and reuse.

---

## 4. Core product pillars

### 4.1 Cyaichi Studio (visual workflows + observability)

A unified canvas where users and AI build, run, and debug graphs.

**Studio capabilities**

* Visual graph authoring (nodes + connections + reusable subgraphs)
* Live execution status on the graph
* Execution timeline / trace view
* **Artifact lineage / provenance view** (trace a specific artifact end-to-end through transformations and routing)
* **Node Inspector** showing:

  * inputs/outputs (sampled when necessary)
  * prompts/templates used
  * memory reads/writes
  * latency and cost
  * custom metadata

**Debugging capabilities**

* Pause, step-through, interrupt at checkpoints
* Time-travel replay and branch-and-compare
* “Debug mode” for high-volume pipelines via sampling + deep tracing
* Exportable traces/telemetry to external tooling (standards-friendly)

---

### 4.2 Shared memory layer (notes + records + reusable context)

Cyaichi includes a built-in collaborative knowledge system (Notebook/Records) that becomes **AI-usable memory**, while remaining human-readable and auditable.

**Memory features**

* Collaborative notes (rich text/markdown + attachments + history)
* Contextual linking: notes/records can reference flows, nodes, runs, artifacts, and projects
* Automatic indexing of notes, run artifacts, and traces into the memory/search layer
* Permissioned sharing by scope (personal / team / org / public-read)

**Important clarification (vision-level):**
“Unified memory” is a *logical* layer (one identity/provenance model) even if it is implemented using multiple storage/indexing techniques later. This keeps the product simple without forcing a single physical database for everything.

---

### 4.3 Hybrid workflow engine (durable + throughput)

Cyaichi supports two complementary execution modes, selectable by users or recommended by AI:

1. **Durable / agent-graph mode**
   For long-running, stateful workflows: loops, reflection, multi-step tool use, human-in-the-loop, approvals, retries, waiting, and case-style work.

2. **High-volume dataflow mode**
   For event-heavy pipelines: ingestion, enrichment, routing, and transformation at scale.

3. **Hybrid mode**
   Durable workflows can orchestrate high-volume sub-jobs, and high-volume pipelines can escalate selected items to durable reasoning.

**Conversion philosophy (vision-level):**
Cyaichi aims for “one-click conversion” where safe and meaningful—e.g., “optimize for scale” or “wrap for reasoning”—while remaining honest that not all graphs can be perfectly transformed across semantics.

---

## 5. AI Flow Builder and meta-layer

Cyaichi includes a natural-language interface where users can describe goals (“Collect competitor mentions, analyze sentiment, route urgent items to the team, and keep a running summary note”) and the system proposes complete workflows.

**Meta-capabilities**

* AI can inspect existing flows, diagnose failures, suggest improvements, and assist with mode selection or safe conversion.
* It draws on the entire shared memory (notes + past traces + artifacts + run history) to build smarter, context-aware workflows over time.
* The AI can explain its own suggestions directly on the canvas, highlight relevant past notes, and let users accept, tweak, or reject changes in one click.
* Supports multiple model providers (avoid lock-in).

---

## 6. Workflow paradigms supported

Cyaichi is designed to represent multiple workflow paradigms within one product experience, including:

* DAG-style pipelines
* reactive dataflow
* stateful agent graphs (with cycles)
* multi-agent topologies
* event-driven durable execution
* knowledge-centric retrieval and reasoning
* low-code visual flows plus AI-generated components

**Note:** Cyaichi treats these as “first-class” in the UI and graph model, while conversion across paradigms is “best-effort when eligible,” not a universal promise.

---

## 7. Governance, trust, and safety

Inspired by SIEM/SOAR expectations, Cyaichi includes “enterprise-grade” governance as a core trait, not an add-on.

**Key requirements**

* Strong access control (RBAC), immutable-ish audit trails, encryption, and data residency options
* Permissioned memory scopes (personal/team/org/public-read)
* Clear provenance: “what data was used, who wrote it, what run produced it”
* Cost transparency and per-flow budgeting

### 7.1 Trust contract (user-facing promise)

Cyaichi is built so users can answer “why did it do that?” with confidence:

* **AI suggestions are grounded**: when AI proposes a flow or a change, it points to the relevant notes, runs, artifacts, and outcomes that informed it.
* **Memory is attributable**: MemoryItems retain provenance (who/what created it, when, and what it was based on).
* **Reuse is auditable**: when AI uses memory during execution, that retrieval is visible and inspectable in the run.

### 7.2 Policy gates (safe-by-design)

Cyaichi supports policy controls that keep humans in charge of high-risk actions:

* Side-effect actions (e.g., external writes, notifications, escalations) can require permissions and optional approvals.
* Memory writes (creating or updating MemoryItems) can be governed by scope, role, and review/verification rules.
* Sensitive data is handled consistently in the Studio (e.g., redaction rules apply to inspectors and search results).

---

## 8. Extensibility and openness

Cyaichi is intended to be a platform ecosystem:

* plugin architecture for tools/APIs/connectors
* exportable observability data
* interoperability-friendly approach to integrating external systems (without forcing a single vendor stack)

---

## 9. Target users

* **Solo knowledge worker**: personal AI operating system for research and daily tasks
* **Small team / startup**: shared memory + collaborative studio for ops workflows
* **Enterprise security/ops**: governance + observability + high-volume processing
* **AI power user / developer**: complex multi-agent systems with deep debugging

### 9.1 Example user journeys

**Journey A: Solo daily information triage**
A user collects inputs (feeds, emails, docs), runs an enrichment flow, and produces a daily summary note. The run is inspectable; key outputs are saved as MemoryItems for future reuse.

**Journey B: Team “living brief”**
A team monitors a domain (competitors, customers, incidents). Cyaichi routes important items to a shared Workspace, updates a running brief, and links decisions back to artifacts and runs.

**Journey C: Case-style operations**
A durable flow opens a “case,” gathers evidence, escalates uncertain items to deeper reasoning, requests approvals for actions, and records outcomes as structured records with full provenance.

---

## 10. Differentiation

Cyaichi differentiates by combining:

* one canvas for building and operating workflows
* hybrid execution across durable reasoning and throughput pipelines
* notes-as-memory that agents actually use (closed-loop learning)
* SIEM/SOAR-grade governance + observability as defaults

---

## 11. Success metrics (product-level)

* A user can go from “goal statement” to a working production flow quickly (minutes, not days).
* Teams reuse captured notes/records in future runs (knowledge actually compounds).
* Debugging is fast and confidence-building (sub-second inspection on sampled high-volume runs).
* “Zero context loss” between solo and team usage.

---

## 12. Phased roadmap (high-level vision)

**Phase 1** — Studio canvas, durable/agent-graph execution, core observability, shared memory + Notebook.
**Phase 2** — High-volume dataflow mode, hybrid interoperation, advanced debugging (sampling + time-travel).
**Phase 3** — Full AI Flow Builder with memory-aware suggestions, rich governance policies, and seamless team collaboration.
**Phase 4** — Expanded connectors, knowledge-graph enhancements, and specialized solution packs (including security/ops templates).

---

## 13. Non-goals and open questions

### 13.1 Non-goals (for now)

* Not a full SIEM/SOAR product on day one (but designed to support those demands).
* Not a promise of universal workflow conversion across paradigms; conversion is best-effort for eligible graphs.
* Not a replacement for every existing data platform; integrations and connectors are a core strategy.
* Not a “black box agent” experience; observability and governance are always first-class.

### 13.2 Open questions (intentionally deferred)

1. What are the minimal primitives for “memory governance” (scope, provenance, review states, retention)?
2. What “replay guarantee” should the product promise for AI nodes (capture vs re-run vs hybrid)?
3. What are the first high-volume use cases that define required throughput characteristics?
4. What collaboration model is ideal for graph editing and shared notes (versioning/branching vs realtime co-edit)?
5. What’s the minimum set of connectors that makes the platform immediately useful?

---
