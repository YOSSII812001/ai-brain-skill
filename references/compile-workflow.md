# Compileサイクル

**目的**: wiki整合性維持・知識統合

## 差分compile（/loop時のデフォルト）

1. wiki/log.mdから最終compileタイムスタンプを取得
2. `find wiki/sources/ -name "*.md" -newer` で変更sourceを特定
3. concepts/ の stub で sources数 >= 2 を昇格候補として検出
4. 変更なし → スキップ（ScheduleWakeupのみ）
5. 変更あり → 以下のフルフローの該当ステップのみ実行

## フルcompile（初回 or `/wiki-compile all`）

1. wiki/sources/の新規・更新ページを走査
2. スタブで2+ソース到達→完全記事に昇格
3. 既存概念ページに新情報統合
4. wikilink更新
5. wiki/index.md再構築
6. syntheses/で統合分析テーマ特定→作成
7. frontmatterのdate_modified更新
8. wiki/log.mdに記録

obsidian-cli backlinks/orphans活用。
