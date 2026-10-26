# Orch

> **Work in progress. Not ready for use yet.** Orch is early and
> incomplete. Only Setup and Question intake exist today. No
> orchestration runs yet, and anything may change between versions
> (the plugin is at 0.0.x).

Building an agentic plugin for Codex, following the [Agent Plugins
specification][agent-plugins], that codifies developer work patterns
into structured, reusable workflows.

## What Works Today

- **Setup:** prepares the project's `wr/` WorkRequest storage and its
  Git exclusion, when authorized.
- **Question:** collects the Developer's exact Question and displays
  it. It does not investigate or answer it.

## What Does Not Exist Yet

- Investigation, answering, or any other orchestration step.
- Support beyond the platform below.

## Supported Platform

Codex CLI on macOS with Apple Silicon. Other platforms are not
supported yet. On them, the bundled Ruby launcher stops with a
"configuration not found" message.

## Repository Layout

- `orch/`: the plugin (skills, hook, bundled Ruby launcher, tests).
- `.agents/plugins/marketplace.json`: the local Codex marketplace entry.
- `AGENTS.md`: rules for working in this repository.

[agent-plugins]: https://agent-plugins.org/specification
