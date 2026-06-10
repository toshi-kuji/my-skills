# Agent instructions for this repository

This repository is a fork of https://github.com/anthropics/skills. It stays synced with upstream, with custom skills added on top.

## The one rule: never modify upstream files

All changes to this repository must be **new files** under `skills/tk/` (plus this `AGENTS.md`). Never edit any file that exists in the upstream repository — including `README.md`, `THIRD_PARTY_NOTICES.md`, `spec/`, `template/`, and every skill outside `skills/tk/`. Any such edit creates permanent merge conflicts on every upstream sync.

If an upstream skill needs a fix:
- copy it into `skills/tk/<skill-name>/` and modify the copy, or
- suggest a pull request to the upstream repository instead.

## Syncing with upstream

Sync regularly. Prefer the CLI, which fails clearly instead of offering destructive options:

```bash
gh repo sync toshi-kuji/my-skills --source anthropics/skills
```

If using GitHub's "Sync fork" button instead: **never click "Discard commits"** — that deletes all custom work under `skills/tk/`. As long as changes here are additions-only, the merge is always clean.

## Custom skills

Custom skills live in `skills/tk/<skill-name>/`. See `skills/tk/README.md` for conventions and `gh skill` usage.
