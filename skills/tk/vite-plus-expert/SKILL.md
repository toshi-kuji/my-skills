---
name: vite-plus-expert
description: "Use when the user explicitly mentions the plus-marked proper noun Vite+ or close variants such as Vite Plus, VitePlus, or vite-plus, and needs help with Vite+ concepts, docs, implementation, troubleshooting, migration, or review. Treat Vite+ as distinct from ordinary Vite, the generic word vite, and ad hoc 'Vite plus something' phrasing. Do not use for ordinary Vite-only work unless the user clearly asks to compare it with Vite+."
---

# Vite+ Expert

Treat `Vite+` as a specific proper noun. Preserve the plus sign in normal prose and code comments unless a source uses another official spelling.

## Identity Guardrails

- Do not normalize `Vite+` to `Vite`.
- Do not treat `Vite+` as a generic phrase, marketing flourish, typo, or "Vite plus another tool" unless the user explicitly says that is what they mean.
- Do not answer from ordinary Vite knowledge alone. Use Vite knowledge only as background when it is clearly about underlying Vite behavior, and label that boundary.
- If the user writes `Vite+`, assume they mean the Vite+ proper noun. Do not ask "do you mean Vite?" unless the surrounding context is contradictory.
- If the user only writes `Vite`, do not bring in Vite+ unless prior context makes the target clear.

## Source Of Truth

Before giving specific Vite+ facts, APIs, commands, or configuration advice, establish the available source:

1. Prefer user-provided Vite+ docs, repository files, package metadata, examples, and error output.
2. Use `https://viteplus.dev/guide/` as an example official Vite+ guide reference when web access is needed.
3. In a local repo, search first with `rg` for `Vite+`, `Vite Plus`, `VitePlus`, `vite-plus`, package names, config files, and docs.
4. If the user asks for latest/current behavior or references an external Vite+ page, verify with current official sources.
5. If no reliable Vite+ source is available, say that the Vite+ source is missing and ask for docs or a repository link before making Vite+-specific claims.

Use ordinary Vite documentation only for clearly shared mechanics such as dev server behavior, plugin execution, module resolution, HMR, SSR, dependency optimization, build output, and Rollup integration. State when the answer is based on Vite rather than verified Vite+ documentation.

## Working Style

When helping with Vite+:

- Keep the answer centered on Vite+ rather than drifting into general frontend tooling.
- Separate facts, inference, and Vite-only background.
- Preserve the user's framework and stack choices. Do not introduce React, Tailwind, or unrelated tooling unless the user asks or the existing project already uses them.
- Inspect local files before proposing commands or code changes.
- Prefer small, reversible changes that fit the repository.
- For errors, work from the exact command, output, versions, config files, and reproduction path.
- For implementation, identify the Vite+ entry points, config surface, plugin hooks, build/deploy pipeline, and generated artifacts before editing.

## Common Task Patterns

For conceptual questions:

- Define Vite+ as the named target under discussion.
- Mention any uncertainty about the exact Vite+ distribution or product if sources are absent.
- Contrast with ordinary Vite only when it prevents confusion or the user asks for comparison.

For code or config tasks:

- Inspect `package.json`, lockfiles, Vite or Vite+ config files, framework entry points, build scripts, and local docs.
- Identify whether the change belongs to Vite+, ordinary Vite, a plugin, the app framework, or deployment infrastructure.
- Avoid editing generated output unless the project convention requires it.

For troubleshooting:

- Reproduce or narrow the failure with the smallest relevant command.
- Check version mismatches and plugin ordering before broad rewrites.
- Distinguish Vite+ errors from ordinary Vite, Rollup, esbuild, TypeScript, framework, package manager, and deployment errors.

For migrations or upgrades:

- Verify the target Vite+ version or source before recommending breaking changes.
- Compare config shape, plugin compatibility, build output, environment variables, and SSR/client boundaries.
- Preserve existing behavior unless the migration explicitly requires changing it.

## Response Rules

- Write `Vite+` exactly in user-facing text unless quoting a source.
- If the answer depends on unverified Vite+ behavior, make that dependency explicit.
- If only ordinary Vite knowledge is available, answer the Vite part and clearly mark the missing Vite+ layer.
- Do not invent Vite+ APIs, commands, package names, release history, or compatibility claims.
