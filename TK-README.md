# TK-README

This repository is a clone of https://github.com/anthropics/skills.

Custom skills added here should use the `tk-` prefix in the skill folder name to keep them distinct from the upstream Anthropic skills.

Keep this repository synced with the upstream repository by using GitHub's "Sync fork" flow regularly. Outside of custom `tk-` skills and any repo-specific notes, keep the rest of the repository aligned with the latest state of https://github.com/anthropics/skills.

When you want to use one of these skills in another project, use `gh skill` from GitHub CLI.

General patterns:

```bash
gh skill search <query>
gh skill preview <repository> <skill>
gh skill install <repository> <skill> --scope project
gh skill install <repository> <skill> --scope user
gh skill update
gh skill publish
```

Useful conventions:

- `gh skill search` finds skills across public GitHub repositories by scanning `SKILL.md` name and description text.
- Skills do not need to live at the repository root. Common layouts like `skills/<skill>/SKILL.md` are supported.
- `gh skill preview` lets you inspect a skill before installing it.
- `gh skill install` installs a skill from a repository into either the current project or your user scope.
- `gh skill update` checks installed skills for updates.
- `gh skill publish` validates and publishes a local skill repository.

Concrete examples:

```bash
gh skill search pdf
gh skill preview toshi-kuji/my-skills tk-structured-pdf
gh skill install toshi-kuji/my-skills skills/tk-structured-pdf --scope project
gh skill install toshi-kuji/my-skills skills/tk-structured-pdf --scope user
gh skill update tk-structured-pdf
```

`--scope project` installs into the current repository. `--scope user` installs into the user-scope skill directory for supported agent hosts, so it is available across projects in those hosts. When the source repository is large, prefer the exact path form such as `skills/tk-structured-pdf` instead of only the skill name.

Prefer `--scope project` by default to avoid global skill pollution. Use `--scope user` only for skills you intentionally want available across multiple projects.

Examples:

- `skills/tk-structured-pdf`
- `skills/tk-your-next-skill`
