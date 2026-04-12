# 3層構造

1. `raw/` — ソース素材。AIは読むが変更しない
   - articles/ papers/ repos/ datasets/ assets/
2. `wiki/` — AI管理の知識層。自動生成・維持
   - index.md log.md concepts/ entities/ sources/ syntheses/ outputs/ attachments/
3. `CLAUDE.md` — vault rootのスキーマ定義（80行以下）

既存フォルダ（Claude/ LLM/ 仕事/等）はそのまま維持。
raw/は新規素材専用。wiki/がAI生成ナレッジの唯一の格納先。