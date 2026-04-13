# Lintサイクル

## 差分lint（/loop時のデフォルト）

1. wiki/log.mdから最終lintタイムスタンプを取得
2. `find wiki/ -name "*.md" -newer` で変更ファイルを特定
3. 変更ファイルのみ対象に以下を実行:
   - 未解決wikilink → スタブ作成
   - フロントマター欠損 → YAML補完
   - デッドエンド → wikilink追加
   - 命名違反 → リネーム提案
4. 変更なし時も定期チェック（下記）は実行

## 定期ヘルスチェック（変更なし時）

5. 孤立ページ → リンク追加or統合（obsidian-cli orphans）
6. 陳腐化(>6ヶ月) → status: stale
7. 矛盾検出 → ⚠️フラグ

## フルlint（`/wiki-lint all`）

上記1-7を全ファイル対象に実行。

結果をwiki/log.mdに記録。
obsidian-cli orphans/unresolved活用。
