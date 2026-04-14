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
6. **【必須】成功ファイルのinbox削除 + 検証**:
   - Bashの`rm`コマンドで成功ファイルを個別に削除
   - Globツールでinbox/内を確認し、残留ファイルが失敗分のみであることを検証
   - 全成功なら「inbox/: 0 files remaining」を確認してからサマリ報告

## 完了ゲートチェック（全項目YESでなければ未完了）

- [ ] wiki/sources/ に全ソース要約が存在するか
- [ ] wiki/concepts/ に抽出した概念ページが存在するか
- [ ] wiki/index.md に新規エントリが追加されたか
- [ ] wiki/log.md に操作記録が追記されたか
- [ ] **inbox/から成功ファイルが削除されたか（Globで0件確認）**

対象vault: Obsidian Vault
