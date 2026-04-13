# Ingestサイクル

**入力**: URL / ファイルパス / テキスト

1. raw/適切サブフォルダに保存
2. wiki/sources/に要約作成(author-year-title.md)
3. キーコンセプト・エンティティ抽出
4. 各コンセプト:
   - 既存あり→新情報追記
   - 2+ソース→完全記事
   - 初出→スタブ
5. wikilink接続（双方向）
6. wiki/index.md更新
7. wiki/log.mdに記録