# AI External Brain Skill for Claude Code

Karpathy's "AI External Brain" system implemented as a Claude Code skill with Obsidian integration.

Build a personal knowledge base that **gets smarter the more you use it** -- powered by Claude Code + Obsidian.

## Architecture

```
Obsidian Vault
├── main/          <- Your existing content (AI read-only)
├── raw/           <- New source materials (AI read-only)
│   ├── articles/  papers/  repos/  datasets/  assets/
├── wiki/          <- AI-maintained knowledge layer
│   ├── index.md  log.md
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

- [Claude Code](https://claude.ai/claude-code) installed
- [Obsidian](https://obsidian.md) installed with CLI support (v1.12.4+)

### Quick Install

1. **Clone this repository.**

2. **Give your AI assistant the vault path and run a dry run:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-ai-brain.ps1 `
  -VaultPath "C:\path\to\your\Obsidian Vault" `
  -VaultName "Obsidian Vault" `
  -ObsidianCliPath "C:\Program Files\Obsidian\Obsidian.exe"
```

The setup script is dry-run by default. Add `-Apply` only after the printed plan looks right.
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
│   └── references/                 # 22 micro-reference files
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
│   └── wiki-lint.md                # /wiki-lint command
├── scripts/
│   ├── setup-ai-brain.ps1          # Dry-run-first installer
│   ├── validate-repo.ps1           # Local and CI validation
│   ├── check-command-sync.ps1      # Installed command drift check
│   ├── check-reference-parity.ps1  # root vs distribution reference check
│   ├── install-scheduled-tasks.ps1 # Task Scheduler registration helper
│   ├── wiki-compile-scheduled.ps1  # Scheduled /wiki-compile runner
│   └── wiki-lint-scheduled.ps1     # Scheduled /wiki-lint runner
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

## Automated Compile & Lint (Windows Task Scheduler)

The knowledge base can be automatically maintained using Windows Task Scheduler + Claude Code CLI. This runs locally on your PC — no cloud infrastructure required.

### How It Works

```
PC running → Task Scheduler fires
  → PowerShell script (hidden window)
    → claude -p "/wiki-compile" (CLI headless mode)
      → SKILL.md diff-compile workflow executes
        → Results logged to ~/.claude/logs/
```

### Default Schedule

| Task | Schedule | What it does |
|------|----------|-------------|
| **Wiki Compile** | Every 3 hours | Detect new sources, promote stubs to articles, strengthen wikilinks, rebuild index |
| **Wiki Lint** | Daily at 17:00 | Fix broken links, fill missing frontmatter, flag stale pages (>6 months), detect orphans |

Both tasks use **diff mode** by default — only processing changes since the last run. Full scans happen only on first run or when explicitly requested.

### Setup

1. **Dry-run task registration:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-scheduled-tasks.ps1 `
  -VaultPath "C:\path\to\your\Obsidian Vault" `
  -SkillPath "$HOME\.claude\skills\ai-brain"
```

2. **Apply after the dry-run output looks right:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-scheduled-tasks.ps1 `
  -VaultPath "C:\path\to\your\Obsidian Vault" `
  -SkillPath "$HOME\.claude\skills\ai-brain" `
  -Apply
```

3. **Manage tasks:**
```powershell
# Check status
Get-ScheduledTask -TaskPath '\Claude Code\'

# Run now
Start-ScheduledTask -TaskPath '\Claude Code\' -TaskName 'Claude Wiki Compile'

# Pause / Resume
Disable-ScheduledTask -TaskPath '\Claude Code\' -TaskName 'Claude Wiki Compile'
Enable-ScheduledTask -TaskPath '\Claude Code\' -TaskName 'Claude Wiki Compile'
```

### Interval Decision Logic (Self-Paced)

When using `/loop /wiki-compile` or `/loop /wiki-lint` interactively, the skill uses adaptive intervals:

| Situation | Delay | Reason |
|-----------|-------|--------|
| Compile executed (files changed) | 120s | Check for cascading changes |
| Sources updated but no promotion | 180s | Watch for threshold crossing |
| No changes detected | 1200s | Idle check every 20 min |
| Lint fixes applied | 120s | Verify fix side-effects |
| Changes found, all clean | 270s | Stay in cache window |
| All clean, periodic only | 1800s | Idle check every 30 min |

> **Note on cache TTL:** Intervals avoid the 300s boundary. Under 270s stays in prompt cache (fast, cheap). Over 1200s accepts the cache miss but amortizes it with a longer wait.

### Logs

Logs are written to `~/.claude/logs/` with daily rotation:
```
~/.claude/logs/wiki-compile-2026-04-13.log
~/.claude/logs/wiki-lint-2026-04-13.log
```

### PowerShell Encoding

The bundled scheduler scripts use ASCII-safe text, so they run without a BOM requirement. If you localize the scripts with Japanese text, save them as UTF-8 with BOM:
```powershell
# Add BOM to an existing script
$bytes = [System.IO.File]::ReadAllBytes($path)
$bom = [byte[]](0xEF, 0xBB, 0xBF)
[System.IO.File]::WriteAllBytes($path, $bom + $bytes)
```

## Validation

Run the local validator before opening a pull request:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-repo.ps1
```

The validator checks reference parity, README file counts, command count, stale forbidden strings, PowerShell syntax, the workflow file, and internal Markdown links.

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
