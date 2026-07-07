# Environment configuration

The vault root `CLAUDE.md` is the source of truth for environment values.

Required values:

- `VAULT_NAME`: Obsidian vault name passed to obsidian-cli.
- `VAULT_PATH`: absolute path to the Obsidian vault.
- `OBSIDIAN_CLI_PATH`: absolute path to the Obsidian executable or CLI shim.
- `AI_BRAIN_SKILL_PATH`: installed skill path.

The public skill must not hard-code a user-specific Obsidian path. During setup, replace placeholders in the vault schema and command files, then read those values at runtime.
