# AI External Brain Skill for Claude Code and Codex

Karpathy's "AI External Brain" system implemented as an Obsidian skill for Claude Code and Codex.

Build a personal knowledge base that **gets smarter the more you use it** -- without having to remember maintenance commands.

## What Is Better Now

This release makes the skill easier to install, safer to run, and harder to accidentally drift out of sync.

| Area | Before | Now | Why it matters |
|------|--------|-----|----------------|
| Setup | Users had to copy files and fill paths by hand | `scripts/setup-ai-brain.ps1` prints a dry-run plan, replaces placeholders, and copies the right files only when `-Apply` is passed | You can review every change before anything touches your local Claude, Codex, or vault files |
| Obsidian paths | A user-specific Obsidian path could leak into the public skill | Environment values live in the vault `CLAUDE.md` and setup replaces placeholders | The public skill works on other machines without editing six separate places |
| Command updates | Installed `/wiki-*` commands could silently become stale | `scripts/check-command-sync.ps1` compares installed commands with the repository version | You can detect old local commands before they confuse the workflow |
| Reference files | Root references and packaged skill references could drift apart | `scripts/check-reference-parity.ps1` verifies both copies match | Fixes made for real use are not lost in the next distribution |
| Scheduled runs | Users had to remember compile and lint commands | Sleep Mode compiles every 4 hours and lints daily at 17:00 by default | The external brain maintains itself in the background |
| Background execution | A PowerShell window could flash when a task started | One hidden S4U task, a hidden bootstrap, and a Job Object control the full child process tree | After the interactive setup, scheduled and "run now" paths do not open or close a terminal window |
| Recovery | A failed run could leave partial changes or an unexplained stop | Staging, journals, rollback, a daily report, and `wiki-sleep doctor` provide recovery | The vault stays usable and tells the user one next action |
| Validation | Broken links, stale strings, script syntax, and file-count drift were manual checks | `scripts/validate-repo.ps1` and GitHub Actions run the same lightweight checks | Pull requests get a repeatable safety net |
| Self-improvement | Lint findings stopped at vault cleanup | Repeated structural findings can now become skill improvement drafts | The skill can improve its own instructions instead of only patching one note |

## Architecture

```
Obsidian Vault
├── main/          <- Your existing content (AI read-only)
├── raw/           <- New source materials (AI read-only)
│   ├── articles/  papers/  repos/  datasets/  assets/
├── wiki/          <- AI-maintained knowledge layer
│   ├── index.md  log.md
│   ├── _meta/sleep-report.md
│   ├── concepts/  entities/  sources/
│   ├── syntheses/  outputs/  attachments/
├── CLAUDE.md      <- Schema definition (< 80 lines)
└── (existing folders remain untouched)
```

### 3-Layer Structure

| Layer | Path | Role |
|-------|------|------|
| Layer 1 | `main/` | Your existing content. AI reads but never modifies |
| Layer 2 | `raw/` | New source materials. AI reads but never modifies |
| Layer 3 | `wiki/` | AI-maintained knowledge. Auto-generated and maintained |
| Schema | `CLAUDE.md` | Schema file defining structure, naming, operations |

### 4 Operation Cycles

| Cycle | Command | Description |
|-------|---------|-------------|
| **Ingest** | `/wiki-ingest` | Process new source materials into wiki |
| **Compile** | `/wiki-compile` | Build/update wiki pages, maintain index |
| **Query** | `/wiki-query` | Cross-reference wiki, synthesize cited answers |
| **Lint** | `/wiki-lint` | Health check: fix broken links, stale content |

Plus `/wiki-init` for initial scaffolding.

## Installation

### Prerequisites

- [Claude Code](https://claude.ai/claude-code) or [Codex](https://github.com/openai/codex) installed and signed in
- [Obsidian](https://obsidian.md) installed with CLI support (v1.12.4+)

### Quick Install

1. **Clone this repository.**

2. **Give your AI assistant the vault path and run a dry run:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-ai-brain.ps1 `
  -VaultPath "C:\path\to\your\Obsidian Vault" `
  -VaultName "Obsidian Vault" `
  -ObsidianCliPath "C:\Program Files\Obsidian\Obsidian.exe" `
  -SleepModeChoice Accept
```

The AI skill first explains compile as "organizing memories during sleep" and lint as a "daily health check," then asks whether the default 4-hour / 17:00 schedule is suitable. After the user answers, the AI passes an explicit `Accept`, `Custom`, or `Disable` choice to the non-interactive setup script. The script is dry-run by default; add `-Apply` only after the plan and any initial bulk estimate are approved.
See [SETUP.md](SETUP.md) for the AI-assisted setup contract.

3. **Initialize the vault:**
```
/wiki-init
```

This scaffolds `raw/` and `wiki/` folders in your vault.

## File Structure

```
ai-brain-skill/
├── SETUP.md                         # AI-assisted setup contract
├── .github/
│   └── workflows/
│       └── validate.yml             # Lightweight repository validation
├── skill/
│   ├── SKILL.md                    # Main skill file
│   └── references/                 # 23 micro-reference files
│       ├── schema-overview.md      # 3-layer structure definition
│       ├── environment-config.md   # Environment source-of-truth rules
│       ├── raw-layer-rules.md      # raw/ directory rules
│       ├── wiki-layer-structure.md # wiki/ subdirectory listing
│       ├── naming-conventions.md   # Kebab-case, author-year format
│       ├── frontmatter-template.md # YAML frontmatter template
│       ├── page-threshold.md       # When to create full vs stub pages
│       ├── quality-standards.md    # Word counts, citation rules
│       ├── ingest-workflow.md      # Ingest cycle steps
│       ├── inbox-rules.md          # inbox/ safety and cleanup rules
│       ├── inbox-workflow.md       # Batch inbox ingest workflow
│       ├── compile-workflow.md     # Compile cycle steps
│       ├── query-workflow.md       # Query cycle steps
│       ├── lint-workflow.md        # Lint cycle steps
│       ├── loop-operation.md       # /loop self-paced operation
│       ├── sleep-mode.md           # Background schedule, safety, and recovery
│       ├── self-improvement-workflow.md # Skill improvement draft flow
│       ├── init-workflow.md        # Init/scaffold steps
│       ├── index-template.md       # wiki/index.md template
│       ├── log-template.md         # wiki/log.md template
│       ├── concept-template.md     # Concept article template
│       ├── source-template.md      # Source summary template
│       └── migration-strategy.md   # Coexistence with existing files
├── commands/
│   ├── wiki-init.md                # /wiki-init scaffold command
│   ├── wiki-ingest.md              # /wiki-ingest <source> command
│   ├── wiki-ingest-inbox.md        # /wiki-ingest-inbox batch command
│   ├── wiki-compile.md             # /wiki-compile command
│   ├── wiki-query.md               # /wiki-query <question> command
│   ├── wiki-lint.md                # /wiki-lint command
│   └── wiki-sleep.md               # Sleep Mode status and controls
├── scripts/
│   ├── setup-ai-brain.ps1          # Dry-run-first installer
│   ├── ai-brain-sleep-bootstrap.ps1 # Stable hidden task entry point
│   ├── invoke-ai-brain-sleep.ps1   # Compile/lint orchestrator
│   ├── manage-ai-brain-sleep.ps1   # Status, repair, and controls
│   ├── lib/                         # Runtime, process, task, and transaction helpers
│   ├── validate-repo.ps1           # Local and CI validation
│   ├── check-command-sync.ps1      # Installed command drift check
│   ├── check-reference-parity.ps1  # root vs distribution reference check
│   └── install-scheduled-tasks.ps1 # Task Scheduler registration helper
├── tests/
│   └── run-tests.ps1               # PowerShell 5.1 and pwsh regression tests
└── vault/
    └── CLAUDE.md                   # Vault schema file template
```

## Usage

### Ingest a new source
```
/wiki-ingest https://example.com/interesting-article
/wiki-ingest path="existing-note.md"
```

### Query your knowledge base
```
/wiki-query What are the key differences between RAG and fine-tuning?
```

### Compile (rebuild index, upgrade stubs)
```
/wiki-compile all
/wiki-compile concepts
```

### Health check
```
/wiki-lint all
/wiki-lint links
/wiki-lint stale
```

## Sleep Mode: maintenance without maintenance

Sleep Mode is the normal operating mode on Windows. It treats compile like the brain organizing memories during sleep and lint like a daily health check.

| Operation | Default schedule | What it does |
|-----------|------------------|--------------|
| **Compile** | Every 4 hours | Connect new knowledge, promote useful stubs, and rebuild the index |
| **Lint** | Daily at 17:00 local time | Check links, frontmatter, naming, stale pages, and orphans |

One Task Scheduler task carries both triggers. It uses S4U, `-WindowStyle Hidden`, a hidden task setting, `CreateNoWindow`, and a Windows Job Object. Windows may show one administrator confirmation during the interactive initial setup. After registration, the release gate verifies that scheduled and "run now" paths do not show a terminal. The task does not wake a sleeping PC.

The runtime first detects whether source content changed. If nothing changed, compile finishes without calling the AI agent. Lint still runs once per day. Only `wiki/` is writable; `main/` and `raw/` remain read-only. Changes are staged and validated, then applied with a per-file journal and rollback verification.

Users do not need to remember how the system works. Open `wiki/_meta/sleep-report.md` to see the latest result, the next compile and lint, any automatic recovery, and—only when needed—one action to take.

Use the skill command for controls instead of editing Task Scheduler directly:

```text
/wiki-sleep status
/wiki-sleep run-now compile
/wiki-sleep run-now lint
/wiki-sleep disable
/wiki-sleep enable
/wiki-sleep doctor
```

Sleep Mode is registered by the applied setup unless the user declines it. Headless installation must pass an explicit choice such as `-SleepModeChoice Accept`, `Custom`, or `Disable`. Advanced details, migration behavior, large first-run approval, recovery, and uninstall are documented in [references/sleep-mode.md](references/sleep-mode.md).

Runtime metadata and safe JSONL logs live under `%LOCALAPPDATA%\ai-brain\<vault-id>\`. Raw agent output and vault content are not written to those logs.

## Validation

Run the local validator before opening a pull request:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-repo.ps1
```

The validator checks reference parity, README file counts, command count, stale forbidden strings, PowerShell syntax, the workflow file, internal Markdown links, and the mirrored skill hash. CI also runs `tests/run-tests.ps1` in Windows PowerShell 5.1 and PowerShell 7.

To check installed command drift:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-command-sync.ps1 -Target claude
```

## Design Principles

- **All references are dynamically loaded** -- no static `@import`, minimizing context window usage
- **Reference files stay small and focused** -- micro-files loaded only when needed
- **Existing vault content is preserved** -- coexistence mode, no migration required
- **obsidian-cli as transport layer** -- the skill delegates all vault I/O to obsidian-cli
- **YAML frontmatter on all wiki pages** -- enables structured queries and lint checks

## Credits

Based on the "LLM Wiki" / AI External Brain concept by [Andrej Karpathy](https://x.com/karpathy) ([original gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)), detailed guide by [@hooeem](https://x.com/hooeem/status/2041196025906418094), and Japanese coverage by [@ClaudeCode_love](https://x.com/ClaudeCode_love/status/2042886840177557533).

## License

MIT
