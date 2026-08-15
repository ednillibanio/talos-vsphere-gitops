# Claude Code Instructions

Read and follow `AGENTS.md` first.

This repository is Argo CD desired state. A controller applies what is merged
here to a live cluster with no further review, so treat every change as a
production change.

Two rules are worth repeating because ignoring them is silent:

1. The offline validators under `scripts/` are mandatory before a pull request —
   there is no CI to catch what you skip.
2. A values file holds owned overrides only. Never re-vendor a chart's defaults.

For cross-repository work, read `docs/planning/talos-projects-roadmap.md` in the
workspace root and the matching record under `docs/planning/execution/`.

Do not push, open a pull request, merge, rotate credentials, rewrite history, or
run destructive infrastructure commands without explicit owner authorization.
