# ソース素材の取込: $ARGUMENTS

新しいソース素材をナレッジベースに取り込み、要約・概念ページを生成する。

## 入力

$ARGUMENTS: URL / ファイルパス / テキスト / path="既存vaultファイル"

## 手順

1. `~/.claude/skills/ai-brain/SKILL.md` を Read
2. vault root の `CLAUDE.md` を Read
3. 以下をRead:
   - `~/.claude/skills/ai-brain/references/ingest-workflow.md`
   - `~/.claude/skills/ai-brain/references/naming-conventions.md`
   - `~/.claude/skills/ai-brain/references/frontmatter-template.md`
   - `~/.claude/skills/ai-brain/references/page-threshold.md`
4. ワークフローに従い実行
5. wiki/index.md と wiki/log.md を更新

対象vault: <YOUR_VAULT_NAME>
