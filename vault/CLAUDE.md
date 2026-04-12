# AI External Brain — Schema

## Structure
- `raw/` — Source materials. AI reads, never modifies.
  - articles/, papers/, repos/, datasets/, assets/
- `wiki/` — AI-maintained knowledge layer.
  - index.md, log.md
  - concepts/, entities/, sources/, syntheses/, outputs/, attachments/
- Existing folders — User content. Treat as read-only raw material when ingesting.

## Naming
- All filenames: kebab-case (lowercase, hyphen-separated)
- Sources: {author}-{year}-{short-title}.md
- Outputs: {date}-{summary}.md

## Frontmatter (required on all wiki/ pages)
title, date_created, date_modified, summary, tags, type, status
- type: concept | entity | source | synthesis | output | index | log
- status: stub | draft | complete | stale

## Operations
1. **Ingest**: raw material -> wiki/sources/ summary + concept links
2. **Compile**: Integrate new info, upgrade stubs, rebuild index
3. **Query**: Search wiki, synthesize cited answer, save to outputs/
4. **Lint**: Fix broken links, missing frontmatter, stale pages, naming violations

## Page Rules
- 2+ sources -> full article (500-1500 words)
- 1 source -> stub page
- Summaries: 200-500 words, synthesized (no copy-paste)
- No dangling [[wikilinks]] — create stub if needed
- Contradictions: flag with ⚠️, cite both sources

## Tool
Use Obsidian CLI for all vault operations:
```
OB="/path/to/Obsidian"       # <- Update to your Obsidian CLI path
V="vault=your-vault-name"   # <- Update to your vault name
```

## Log
Record every operation in wiki/log.md
