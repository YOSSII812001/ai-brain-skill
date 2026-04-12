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
| **Compile** | `/wiki-compile** | Build/update wiki pages, maintain index |
| **Query** | `/wiki-query` | Cross-reference wiki, synthesize cited answers |
| **Lint** | `/wiki-lint` | Health check: fix broken links, stale content |

Plus `/wiki-init` for initial scaffolding.

## Installation

### Prerequisites

- [Claude Code](https://claude.ai/claude-code) installed
- [Obsidian](https://obsidian.md) installed with CLI support (v1.12.4+)

### Quick Install

1. **Copy skill files:**
```bash
# Copy SKILL.md and references/
cp -r skill/SKILL.md ~/.claude/skills/ai-brain/SKILL.md
cp -r skill/references/ ~/.claude/skills/ai-brain/references/

# Copy slash commands
cp commands/wiki-*.md ~/.claude/commands/

# Copy vault schema (adjust path to your vault)
cp vault/CLAUDE.md /path/to/your/obsidian/vault/CLAUDE.md
```

2. **Configure paths** -- Edit these files to match your environment:
   - `skill/SKILL.md`: Update vault path and Obsidian CLI binary path
   - `vault/CLAUDE.md`: Update Obsidian CLI path
   - `commands/wiki-*.md`: Update SKILL.md path if needed

3. **Initialize:**
```
/wiki-init
```

This scaffolds `raw/` and `wiki/` folders in your vault.

## File Structure

```
ai-brain-skill/
├── skill/
│   ├── SKILL.md                    # Main skill file
│   └── references/                 # 17 micro-reference files (< 500 chars each)
│       ├── schema-overview.md      # 3-layer structure definition
│       ├── raw-layer-rules.md      # raw/ directory rules
│       ├── wiki-layer-structure.md # wiki/ subdirectory listing
│       ├── naming-conventions.md   # Kebab-case, author-year format
│       ├── frontmatter-template.md # YAML frontmatter template
│       ├── page-threshold.md       # When to create full vs stub pages
│       ├── quality-standards.md    # Word counts, citation rules
│       ├── ingest-workflow.md      # Ingest cycle steps
│       ├── compile-workflow.md     # Compile cycle steps
│       ├── query-workflow.md       # Query cycle steps
│       ├── lint-workflow.md        # Lint cycle steps
│       ├── init-workflow.md        # Init/scaffold steps
│       ├── index-template.md       # wiki/index.md template
│       ├── log-template.md         # wiki/log.md template
│       ├── concept-template.md     # Concept article template
│       ├── source-template.md      # Source summary template
│       └── migration-strategy.md   # Coexistence with existing files
├── commands/
│   ├── wiki-init.md                # /wiki-init scaffold command
│   ├── wiki-ingest.md              # /wiki-ingest <source> command
│   ├── wiki-compile.md             # /wiki-compile command
│   ├── wiki-query.md               # /wiki-query <question> command
│   └── wiki-lint.md                # /wiki-lint command
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

## Design Principles

- **All references are dynamically loaded** -- no static `@import`, minimizing context window usage
- **Each reference file < 500 characters** -- micro-files loaded only when needed
- **Existing vault content is preserved** -- coexistence mode, no migration required
- **obsidian-cli as transport layer** -- the skill delegates all vault I/O to obsidian-cli
- **YAML frontmatter on all wiki pages** -- enables structured queries and lint checks

## Credits

Based on the "AI External Brain" concept by [Andrej Karpathy](https://x.com/karpaborern), detailed guide by [@hooeem](https://x.com/hooeem/status/2041196025906418094), and Japanese coverage by [@ClaudeCode_love](https://x.com/ClaudeCode_love/status/2042886840177557533).

## License

MIT
