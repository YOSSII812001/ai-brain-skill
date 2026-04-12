# log.mdテンプレート

```markdown
---
title: "Operation Log"
date_created: YYYY-MM-DD
date_modified: YYYY-MM-DD
type: log
---
# 操作ログ

| 日時 | 操作 | 対象 | 詳細 |
|------|------|------|------|
| YYYY-MM-DD HH:MM | ingest | page-name | 内容要約 |
```

新しいエントリは先頭行に追加（最新が上）。
操作種別: ingest / compile / query / lint