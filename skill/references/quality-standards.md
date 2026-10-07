# 品質基準

| 種別 | 語数 | 要件 |
|------|------|------|
| ソース要約 | 200-500語 | 合成。核心の主張・手法・結論 |
| 概念記事 | 500-1500語 | リード文。関連概念wikilink。30-50語のsummary |
| 統合分析 | 制限なし | 最低3ソース統合。トリガー条件は synthesis-trigger-algorithm.md 参照 |

## 共通ルール

- 全主張に[[source-page]]トレース
- **ソースに明示的に裏付けられた接続のみ記述**（根拠なき概念間接続は禁止）
- 矛盾には⚠️+両ソース引用。信頼度順: official > primary > secondary > opinion
- 6ヶ月未更新→status: stale
- **既存ページの更新はappendのみ。全書き換え禁止**（既存内容を保持した上で新情報を追記）

## complete判定基準

conceptページが以下の全てを満たせばstatus: complete:
1. 語数500語以上
2. [[source]]引用が2件以上
3. 関連概念wikilinkが1件以上
4. summaryが30-50語で記述済み
5. confidence フィールドが設定済み