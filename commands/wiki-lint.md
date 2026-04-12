# ナレッジベースのヘルスチェック: $ARGUMENTS

wiki層の品質問題を検出し修正する。

## 入力

$ARGUMENTS: all / links / frontmatter / stale / naming（省略時はall）

## 手順

1. `~/.claude/skills/ai-brain/SKILL.md` を Read
2. vault root の `CLAUDE.md` を Read
3. 以下をRead:
   - `~/.claude/skills/ai-brain/references/lint-workflow.md`
   - `~/.claude/skills/ai-brain/references/quality-standards.md`
4. ワークフローに従い実行
5. 結果をwiki/log.mdに記録
6. 修正内容をユーザーに報告

対象vault: <YOUR_VAULT_NAME>
