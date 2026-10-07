# Queryサイクル

**入力**: 質問テキスト

## ページ選択（トークン効率化）

1. 質問分析→関連キーワード抽出
2. wiki/index.mdを読み、関連カテゴリを特定
3. obsidian-cliで `wiki/` 内検索（キーワード＋backlinks）
4. 候補ページのfrontmatter（tags, summary）のみ先読み→関連度スコアリング
5. 上位15件のみ全文読み込み（トークン予算: 最大50,000トークン目安）
6. **outputs/も検索対象に含める** — 過去のquery回答が次の回答を豊かにする

## 回答合成

7. 複数ソースから回答合成
8. 全主張に[[source]]引用付与（ソースなき接続は禁止）
9. 矛盾は⚠️付き両論併記（信頼度: official > primary > secondary > opinion）

## 保存と還流

10. wiki/outputs/{date}-{summary}.mdに保存
11. index.md・log.md更新
12. ユーザーに回答提示
13. **Filing（知見還流）**: 回答内の新たな洞察を関連concepts/entitiesに差分追記
    - 各outputから、既存ページにマージ可能な**事実・比較・新知見**を抽出
    - 該当conceptの「実用知見」セクション等に追記（既存内容は保持、appendのみ）
    - outputのfrontmatterに `filed: true, filed_date: YYYY-MM-DD` を付与
    - 新概念が見つかった場合はスタブ作成（page-threshold準拠）