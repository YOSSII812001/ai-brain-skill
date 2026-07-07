# AI-assisted setup

This guide is written for an AI coding assistant. A human only needs to provide the repository path and the Obsidian vault path.

## Inputs

Required:

- Repository path: the cloned `ai-brain-skill` repository.
- Vault path: the Obsidian vault root.

Optional but recommended:

- Vault name: the name obsidian-cli uses for the vault.
- Obsidian CLI path: the executable or CLI shim path. If omitted, the setup script uses `C:\Program Files\Obsidian\Obsidian.exe` when it exists.
- Target: `claude` or `codex`.

## Dry run first

Run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-ai-brain.ps1 `
  -VaultPath "C:\path\to\your\Obsidian Vault" `
  -VaultName "Obsidian Vault" `
  -ObsidianCliPath "C:\Program Files\Obsidian\Obsidian.exe"
```

The default mode is dry-run. The script prints every planned copy, replacement, and validation step.

## Apply setup

Add `-Apply` only after the dry-run output looks right:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-ai-brain.ps1 `
  -VaultPath "C:\path\to\your\Obsidian Vault" `
  -VaultName "Obsidian Vault" `
  -ObsidianCliPath "C:\Program Files\Obsidian\Obsidian.exe" `
  -Apply
```

The script copies:

- `skill/SKILL.md` to the installed skill directory.
- `skill/references/` to the installed skill directory.
- `commands/wiki-*.md` to the target command directory.
- `vault/CLAUDE.md` to the vault root.
- scheduled compile/lint scripts to the target scripts directory.

`-Apply` overwrites those target files, including the vault root `CLAUDE.md`.
Keep a backup first if the vault already has local instructions.

It replaces placeholders in copied files:

- `<YOUR_VAULT_NAME>`
- `<VAULT_NAME>`
- `<VAULT_PATH>`
- `<OBSIDIAN_CLI_PATH>`
- `<AI_BRAIN_SKILL_PATH>`

## Scheduled tasks

To add Windows Task Scheduler entries, pass `-InstallScheduledTasks -Apply`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-ai-brain.ps1 `
  -VaultPath "C:\path\to\your\Obsidian Vault" `
  -VaultName "Obsidian Vault" `
  -ObsidianCliPath "C:\Program Files\Obsidian\Obsidian.exe" `
  -InstallScheduledTasks `
  -Apply
```

Task registration is never done in dry-run mode.

## Validation

Run this before opening a pull request:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-repo.ps1
```

The validator checks reference parity, README file counts, command count, forbidden stale strings, PowerShell syntax, the GitHub Actions workflow, and internal Markdown links.

## Sync checks

Check installed commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-command-sync.ps1 -Target claude
```

Check root/distribution references:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-reference-parity.ps1
```
