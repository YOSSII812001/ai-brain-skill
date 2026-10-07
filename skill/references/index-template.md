# index.mdテンプレート

```markdown
---
title: "ナレッジベース目次"
date_created: YYYY-MM-DD
date_modified: YYYY-MM-DD
type: index
---
# ナレッジベース目次

## 概念
- [[concept-name]] — 30-50語の要約 | tags: tag1, tag2 | sources: N ★

## エンティティ
- [[entity-name]] — 30-50語の要約 | tags: tag1, tag2 | sources: N

## ソース
- [[author-year-title]] — 1行要約

## 統合分析
- [[synthesis-name]] — 1行要約 | sources: N

## 出力
- [[YYYY-MM-DD-summary]] — 1行要約
```

ステータスマーク: ★=完全記事, (stub)=スタブ, (draft)=作成中

## スケーリングルール

- 1カテゴリが30エントリを超えたら、カテゴリ別indexに分割
- 分割時: `wiki/concepts/_index.md`, `wiki/entities/_index.md` 等を作成
- ルートindex.mdはカテゴリ一覧＋概要のみ（50行以内）に圧縮
- 各カテゴリindexに詳細エントリ（tags, source count, summary）を記載

自動生成。compileサイクルで更新。手動編集不可。