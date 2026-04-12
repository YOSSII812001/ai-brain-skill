# 3フォルダ構成

既存ファイルは全てmain/に格納済み。

- main/ → ユーザー既存コンテンツ（AI読取専用）
- raw/ → 新規素材専用
- wiki/ → AI生成専用

**取込例**:
```
/wiki-ingest path="main/Claude/Claude Code.md"
/wiki-ingest path="main/LLM/"
```

原本はmain/に残る。wikiから[[wikilink]]で参照可能。