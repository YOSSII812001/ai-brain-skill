# ナレッジベースへの質問: $ARGUMENTS

ナレッジベースを横断検索し、引用付きの合成回答を生成する。

## 入力

$ARGUMENTS: 質問テキスト

## 手順

1. `~/.claude/skills/ai-brain/SKILL.md` を Read
2. vault root の `CLAUDE.md` を Read
3. `~/.claude/skills/ai-brain/references/query-workflow.md` を Read
4. wiki/index.md を Read して全体構造を把握
5. ワークフローに従い実行
6. 回答を wiki/outputs/ に保存
7. wiki/index.md と wiki/log.md を更新
8. ユーザーに回答を提示

対象vault: <YOUR_VAULT_NAME>
