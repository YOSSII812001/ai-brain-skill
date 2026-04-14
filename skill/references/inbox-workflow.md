# Inbox Batchサイクル

**入力**: inbox/内の全ファイル

1. inbox/の存在・ファイル一覧を確認（0件→終了）
2. 処理対象をユーザーに提示
3. 各ファイルに対しingest-workflow.mdのステップ1-5を実行:
   - raw/へコピー保存→sources/要約→概念抽出→wikilink接続
   - 個別失敗時: エラー記録し次ファイルへ続行
4. 全ファイル処理後にwiki/index.mdを一括再構築
5. wiki/log.mdに一括記録（ingest-inbox, N files）
6. 成功ファイルのみinbox/から削除
7. 完了サマリ報告（成功/失敗件数、生成ページ一覧）

※ index.md/log.mdはファイルごとでなく最後に1回更新（I/O削減）
