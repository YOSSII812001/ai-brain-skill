# ナレッジベースのコンパイル: $ARGUMENTS

wiki全体の整合性を維持し、知識を統合する。

## 入力

$ARGUMENTS: all / concepts / sources / 特定ページ名（省略時はall）

## 手順

1. `~/.claude/skills/ai-brain/SKILL.md` を Read
2. vault root の `CLAUDE.md` を Read
3. 以下をRead:
   - `~/.claude/skills/ai-brain/references/compile-workflow.md`
   - `~/.claude/skills/ai-brain/references/quality-standards.md`
   - `~/.claude/skills/ai-brain/references/page-threshold.md`
4. ワークフローに従い実行
5. wiki/index.md を再構築
6. wiki/log.md に操作記録

対象vault: <YOUR_VAULT_NAME>
