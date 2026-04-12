# 3フォルダ構成

1. `main/` — ユーザーの既存コンテンツ。AIは読むが変更しない
2. `raw/` — 新規ソース素材。AIは読むが変更しない
   - articles/ papers/ repos/ datasets/ assets/
3. `wiki/` — AI管理の知識層。自動生成・維持
   - index.md log.md concepts/ entities/ sources/ syntheses/ outputs/ attachments/

vault rootには上記3フォルダ + CLAUDE.md（スキーマ、80行以下）のみ。