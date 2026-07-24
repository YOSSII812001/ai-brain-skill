# フロントマターテンプレート

```yaml
---
title: "ページタイトル"
date_created: YYYY-MM-DD
date_modified: YYYY-MM-DD
summary: "30-50語の要約"
tags: [tag1, tag2]
type: concept | entity | source | synthesis | output | index | log
status: stub | draft | complete | stale
sources: ["[[source-page]]"]
confidence: established | emerging | speculative
---
```

## outputタイプ追加フィールド

```yaml
filed: false          # compile/query時にconcepts/entitiesへ統合済みならtrue
filed_date: null      # 統合実行日
```

## sourceタイプ追加フィールド

```yaml
url: "原典URL"
author: "著者名"
year: YYYY
reliability: official | primary | secondary | opinion
```

## フィールド定義

- type: concept=概念, entity=人物等, source=要約, synthesis=統合, output=回答
- status: stub=単一言及, draft=2+ソース到達, complete=品質基準達成, stale=6ヶ月超未更新
- confidence: established=確立された知識, emerging=新興・進行中, speculative=推測的
- reliability: official=公式ドキュメント, primary=一次ソース, secondary=二次ソース, opinion=意見・ブログ
- filed: outputの知見がconcepts/entitiesに還流済みかどうか

## statusライフサイクル

```
stub → draft（2+ソース到達、compile時に自動昇格）
     → complete（品質基準達成: 語数・wikilink・引用の全要件クリア）
     → stale（6ヶ月超未更新、lint時に自動フラグ）
     → draft（staleから新情報追加で復帰）
```