# 既存コンテンツ共存戦略

既存ファイルは移動・リネームしない。

- raw/ → 新規素材専用
- wiki/ → AI生成専用
- 既存ファイルはingestで段階的に処理可能

**取込例**:
```
/wiki-ingest path="Claude/Claude Code.md"
/wiki-ingest path="LLM/"
```

原本は元の場所に残る。wikiから[[wikilink]]で参照可能。