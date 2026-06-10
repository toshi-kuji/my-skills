# Custom skills (skills/tk)

This directory holds custom skills added on top of the upstream https://github.com/anthropics/skills fork. Everything custom in this repository lives here (plus the root `AGENTS.md`), so that upstream files are never modified — see `AGENTS.md` at the repo root for the isolation and sync rules.

## Adding a skill

Place each skill in its own directory: `skills/tk/<skill-name>/SKILL.md` (e.g., `skills/tk/structured-pdf`). For the SKILL.md format, follow the upstream `template/` directory and existing skills here as references.

## Using these skills in other projects

Use `gh skill` from GitHub CLI:

```bash
gh skill search pdf
gh skill preview toshi-kuji/my-skills skills/tk/structured-pdf
gh skill install toshi-kuji/my-skills skills/tk/structured-pdf --scope project
gh skill install toshi-kuji/my-skills skills/tk/structured-pdf --scope user
gh skill update structured-pdf
gh skill publish
```

Notes:

- `gh skill search` finds skills across public GitHub repositories by scanning `SKILL.md` name and description text.
- Skills do not need to live at the repository root; layouts like `skills/tk/<skill>/SKILL.md` are supported. When the source repository is large, prefer the exact path form (`skills/tk/structured-pdf`) over only the skill name.
- `gh skill preview` lets you inspect a skill before installing it.
- `gh skill update` checks installed skills for updates.
- `gh skill publish` validates and publishes a local skill repository.

Prefer `--scope project` (installs into the current repository) by default to avoid global skill pollution. Use `--scope user` only for skills you intentionally want available across multiple projects — it installs into the user-scope skill directory for supported agent hosts, making the skill available across projects in those hosts.
