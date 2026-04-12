# Lintサイクル

1. 未解決wikilink → スタブ作成
2. 孤立ページ → リンク追加or統合
3. フロントマター欠損 → YAML補完
4. 陳腐化(>6ヶ月) → status: stale
5. 矛盾検出 → ⚠️フラグ
6. デッドエンド → wikilink追加
7. 命名違反 → リネーム提案

結果をwiki/log.mdに記録。
obsidian-cli orphans/unresolved活用。