---
name: mac-app-removal
description: Use when Codex needs to safely uninstall a macOS app and related local data, especially apps with large support files, downloaded local models, caches, weights, or model artifacts. Guides discovery, size review, confirmation, moving candidates into a named Trash folder, and reporting without permanent deletion.
---

# Mac App Removal

## Core Rules

Treat removal as a staged move to Trash, not deletion.

- Never permanently delete files by default.
- Never empty the Trash.
- Never use `rm -rf` unless the user explicitly asks for permanent deletion after reviewing the Trash contents.
- Prefer moving every confirmed item into one clearly named folder under `~/.Trash`, such as `~/.Trash/<AppName>-removal-YYYY-MM-DD/`.
- Stop after moving files to Trash. Tell the user to inspect that Trash folder and empty Trash themselves if satisfied.
- Do not use `sudo` unless the user explicitly approves it for a specific path.
- If macOS privacy permissions make a path inaccessible, report that path and do not try to bypass the restriction.
- Do not use Python or `npx` unless there is a specific reason.

## Workflow

### 1. Identify the app

Locate the target `.app` from the user-specified path or `/Applications`.

- If more than one plausible app matches, list the exact paths and ask the user which one to remove.
- If the target path is not an app bundle, explain that ambiguity and ask before treating it as app data.
- Quote paths in every command.

Check whether the app may still be running before moving anything:

```sh
pgrep -fl "App Name|bundle.identifier"
```

If there is a plausible running process, ask the user to quit the app. Do not kill it unless the user explicitly asks.

### 2. Read bundle metadata

Read `Contents/Info.plist` from the app bundle. Prefer `plutil`; use `/usr/libexec/PlistBuddy` if needed.

Collect:

- `CFBundleIdentifier`
- `CFBundleDisplayName` or `CFBundleName`
- `CFBundleShortVersionString` or `CFBundleVersion`

Example:

```sh
plutil -extract CFBundleIdentifier raw -o - "/Applications/App Name.app/Contents/Info.plist"
plutil -extract CFBundleDisplayName raw -o - "/Applications/App Name.app/Contents/Info.plist"
plutil -extract CFBundleShortVersionString raw -o - "/Applications/App Name.app/Contents/Info.plist"
```

If a field is missing, continue with the fields available. Prefer bundle identifier matches over fuzzy app-name matches.

### 3. Search common macOS locations

Search with the bundle identifier first, then display name and app bundle name. Limit fuzzy name matches to paths that clearly belong to the target app or its vendor.

Check these locations when they exist:

```text
~/Library/Application Support
~/Library/Caches
~/Library/Preferences
~/Library/HTTPStorages
~/Library/Containers
~/Library/Group Containers
~/Library/Saved Application State
~/Library/LaunchAgents
/Library/LaunchAgents
/Library/LaunchDaemons
```

Use simple shell tools such as `find`, `mdfind`, `ls`, `plutil`, and `du`. Keep errors visible or captured so inaccessible paths can be reported.

Candidate patterns commonly include:

- Exact bundle identifier paths, such as `com.vendor.App`.
- Preference files such as `~/Library/Preferences/<bundle-id>.plist`.
- Saved state paths such as `~/Library/Saved Application State/<bundle-id>.savedState`.
- App or vendor folders under `Application Support`, `Caches`, `Containers`, and `Group Containers`.
- Launch agent or daemon plists whose `Label`, `Program`, or `ProgramArguments` reference the app path, bundle identifier, or vendor.

Do not include files belonging to other apps merely because they mention the same model name, engine name, or generic app word.

### 4. Size and inspect candidates before moving

Run `du -sh` on every candidate path before asking for confirmation:

```sh
du -sh "/path/to/candidate"
```

Highlight unusually large candidates. For app-related data directories, inspect for local model and weight artifacts:

```sh
find "/path/to/app-data" \( -iname "*.tflite" -o -iname "*.mlmodel" -o -iname "*.gguf" -o -iname "*.bin" -o -iname "*model*" -o -iname "*weights*" \) -print
```

Call out large model directories, local model caches, and weight files separately in the candidate list. Include sizes when practical with `du -sh`.

### 5. Ask for confirmation

Before moving anything, present a concise list containing:

- Path.
- Size from `du -sh`.
- Match reason, such as bundle identifier, display name, app path reference, or launch agent label.
- Any notable large model/cache files found under that path.

Ask the user to confirm the exact candidates to move. If unrelated or ambiguous matches are present, separate them under an "ambiguous, not selected" note and ask instead of guessing.

### 6. Move confirmed items to a named Trash folder

Create a single Trash staging folder:

```sh
trash_dir="$HOME/.Trash/AppName-removal-$(date +%F)"
mkdir -p "$trash_dir"
```

Use safe, collision-resistant destination names. A practical pattern is an increment, a short hash of the original path, and the original basename:

```sh
hash=$(printf "%s" "$src" | shasum -a 256 | awk '{print substr($1,1,12)}')
dest="$trash_dir/001-$hash-$(basename "$src")"
mv -n "$src" "$dest"
```

Use `mv -n` so an existing destination is not overwritten. If a collision occurs, choose a new numbered prefix and retry. Keep a source-to-destination record for the final report.

For `/Library/LaunchAgents`, `/Library/LaunchDaemons`, or `/Applications`, the move may need elevated permission. If a move fails due to permissions, report the path and ask whether the user wants to approve `sudo` for that specific path. Do not retry with `sudo` on a broad set of paths.

### 7. Verify and report

After each move, verify the original path no longer exists:

```sh
test ! -e "$src"
```

If verification fails, report that path as not moved.

Final response must include:

- The app name, bundle identifier, and version used for matching.
- What was moved, with original path and Trash destination.
- Approximate total size moved, based on the pre-move `du -sh` values.
- Any paths skipped because they were ambiguous, inaccessible, still running, or required unapproved `sudo`.
- The Trash folder path.
- A clear stopping note: the user should inspect the Trash folder and empty Trash themselves only if satisfied.
