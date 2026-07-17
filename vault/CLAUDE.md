# AI外部脳 — スキーマ

## 言語
wikiページの本文・要約・フロントマターのtitle/summaryは全て日本語で記述する。

## 構造
- `inbox/` — バッチ投入バッファ。ユーザーが事前配置、処理後に空になる
- `main/` — ユーザーの既存コンテンツ。AIは読むが変更しない
- `raw/` — 新規ソース素材。AIは読むが変更しない
  - articles/, papers/, repos/, datasets/, assets/
- `wiki/` — AI管理のナレッジ層
  - index.md, log.md
  - `_meta/sleep-report.md` — 自動整理の最終結果と次回予定
  - concepts/, entities/, sources/, syntheses/, outputs/, attachments/

## 命名
- 全ファイル名: kebab-case（小文字ハイフン区切り）
- ソース要約: {著者}-{年}-{短縮タイトル}.md
- 出力: {日付}-{質問要約}.md

## フロントマター（wiki/全ページ必須）
title（日本語）, date_created, date_modified, summary（日本語）, tags, type, status
- type: concept | entity | source | synthesis | output | index | log
- status: stub | draft | complete | stale

## 操作サイクル
1. **Ingest**: raw素材 → wiki/sources/要約 + 概念リンク
2. **Compile**: 新情報統合、スタブ昇格、index再構築
3. **Query**: wiki横断検索 → 引用付き回答 → outputs/保存
4. **Lint**: 壊れたリンク、フロントマター欠損、陳腐化、命名違反を修正
5. **Sleep**: 4時間ごとの記憶整理と毎日17:00の健康診断を、同じ安全経路で実行

## ページルール
- 2+ソース → 完全記事（500-1500語）
- 1ソース → スタブ
- 要約: 200-500語、合成（コピー禁止）
- 未解決[[wikilink]]禁止 → スタブを即作成
- 矛盾は⚠️付きで両ソース引用

## 環境値
- `VAULT_NAME`: `<VAULT_NAME>`
- `VAULT_PATH`: `<VAULT_PATH>`
- `OBSIDIAN_CLI_PATH`: `<OBSIDIAN_CLI_PATH>`
- `AI_BRAIN_SKILL_PATH`: `<AI_BRAIN_SKILL_PATH>`
- `AI_BRAIN_RUNTIME_ROOT`: `<AI_BRAIN_RUNTIME_ROOT>`
- `AI_BRAIN_SCRIPT_PATH`: `<AI_BRAIN_SCRIPT_PATH>`

## ツール
Obsidian CLIで全vault操作:
```
OB="<OBSIDIAN_CLI_PATH>"
V="vault=<VAULT_NAME>"
```

## ログ
全操作をwiki/log.mdに記録

## 睡眠モード
- 利用者向けの状態は`wiki/_meta/sleep-report.md`で確認する
- `sleep-report.md`はcompile/lintの変更検出から除外する
- 自動処理が変更できるのは`wiki/`配下だけ。`main/`と`raw/`は読み取り専用
- 状態確認や今すぐ実行は、このvaultの`AI_BRAIN_RUNTIME_ROOT`を使う。他vaultのruntimeを使わない
