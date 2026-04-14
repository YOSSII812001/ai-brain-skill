# inbox/の一括取込: $ARGUMENTS

inbox/フォルダ内の全ファイルをまとめてingestし、処理完了後にinbox/を空にする。

## 入力

$ARGUMENTS: なし（inbox/全体を自動処理）

## 手順

1. `~/.claude/skills/ai-brain/SKILL.md` をRead
2. vault rootの `CLAUDE.md` をRead
3. 以下をRead:
   - `~/.claude/skills/ai-brain/references/inbox-workflow.md`
   - `~/.claude/skills/ai-brain/references/inbox-rules.md`
   - `~/.claude/skills/ai-brain/references/ingest-workflow.md`
   - `~/.claude/skills/ai-brain/references/naming-conventions.md`
   - `~/.claude/skills/ai-brain/references/frontmatter-template.md`
   - `~/.claude/skills/ai-brain/references/page-threshold.md`
4. inbox-workflow.mdに従いバッチingestを実行
5. wiki/index.mdを一括更新、wiki/log.mdに一括記録
6. 成功ファイルのみinbox/から削除

対象vault: <YOUR_VAULT_NAME>
