# wiki-init手順

1. vault rootにCLAUDE.md作成
2. inbox/フォルダ作成（バッチ投入バッファ）
3. raw/サブフォルダ: articles/ papers/ repos/ datasets/ assets/
4. wiki/サブフォルダ: concepts/ entities/ sources/ syntheses/ outputs/ attachments/
5. wiki/index.md作成（空テンプレート）
6. wiki/log.md作成（初期エントリ）
7. 既存フォルダはそのまま維持
8. 初回lint実行

フォルダはmkdir -p、ファイルはobsidian-cli。