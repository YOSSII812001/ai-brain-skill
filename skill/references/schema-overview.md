# 4フォルダ構成

1. `inbox/` — バッチ投入バッファ。ユーザーが事前配置、処理後に空になる
2. `main/` — ユーザーの既存コンテンツ。AIは読むが変更しない
3. `raw/` — 新規ソース素材。AIは読むが変更しない
   - articles/ papers/ repos/ datasets/ assets/
4. `wiki/` — AI管理の知識層。自動生成・維持
   - index.md log.md concepts/ entities/ sources/ syntheses/ outputs/ attachments/

vault rootには上記4フォルダ + CLAUDE.md（スキーマ、80行以下）のみ。