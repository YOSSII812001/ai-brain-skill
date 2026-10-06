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

## 睡眠モードの検証器と互換な書き方

睡眠モード（compile / lint）は、変更するページのfrontmatterを厳格に検査します。
1ページでも不合格だと、実行全体が止まります。ページを作る・直すときは、次の書き方にします。

```yaml
---
title: "ページタイトル"
date_modified: YYYY-MM-DD
type: concept
status: draft
tags:
  - tag1
  - tag2
sources: ["[[source-page]]"]
---
```

- 配列は、`  - 項目`（半角スペースでインデント）か、1行の`[a, b]`で書く。行頭からの`- 項目`は不合格。
- 値は1行で書く。`summary`を複数行に折り返さない。
- 同じキーを2回書かない。
- 本文で`[[...]]`の記号そのものを説明するときは、全角の`［［`にする（空・絶対パス・`..`を含むと不合格）。
- 詳しい切り分けは`sleep-mode.md`の「止まったときの切り分け」を参照する。
