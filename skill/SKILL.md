---
name: AI External Brain (Knowledge Base)
description: |
  Karpathy式AI外部脳。Obsidian vault内のraw/wiki/CLAUDE.md 3層構造で
  個人ナレッジベースを管理。Ingest/Compile/Query/Lintの4サイクル運用。
triggers:
  - "ai-brain"
  - "knowledge-base"
  - "wiki-ingest"
  - "wiki-compile"
  - "wiki-query"
  - "wiki-lint"
  - "wiki-init"
  - "ナレッジベース"
  - "外部脳"
  - "知識管理"
use_when:
  - 新しいソース素材をナレッジベースに取り込む
  - wiki層のページを構築・更新する
  - ナレッジベースを横断検索して引用付き回答を得る
  - ナレッジベースのヘルスチェック・自動修正を行う
  - AI外部脳のフォルダ構造を初期化する
---

# AI External Brain — Karpathy式ナレッジベース管理

## 概要

Obsidian vault上にKarpathy提唱のAI外部脳システムを構築・運用するスキル。
3層構造（raw / wiki / CLAUDE.md）と4操作サイクル（Ingest / Compile / Query / Lint）で
使うほど賢くなるパーソナルナレッジベースを実現する。

## 環境情報

- **Vault名**: <YOUR_VAULT_NAME>
- **Vaultパス**: `<YOUR_VAULT_PATH>`
- **Obsidian CLI**: `<YOUR_OBSIDIAN_CLI_PATH>`
- **Vault CLAUDE.md**: vault root に配置済み

## セッション初期化

**毎セッションの冒頭で必ず実行**:

1. vault rootの `CLAUDE.md` を Read して構造・ルールを把握
2. `wiki/index.md` を Read してナレッジベースの現状を把握
3. `wiki/log.md` の先頭10行を Read して直近の操作を確認

## アーキテクチャ（3層構造）

詳細は `references/schema-overview.md` を Read ツールで読み込むこと。

| 層 | パス | 役割 |
|----|------|------|
| Layer 1 | `raw/` | ソース素材。AIは読み取り専用 |
| Layer 2 | `wiki/` | AI管理のナレッジ層。自動生成・維持 |
| Layer 3 | `CLAUDE.md` | スキーマ定義（80行以下） |

既存フォルダ（Claude/ LLM/ 仕事/ 等）はそのまま維持。移動しない。

## 操作サイクル

### Ingest（取込）

新しいソース素材を処理してwikiに統合する。

実行前に以下をReadツールで読み込むこと:
- `references/ingest-workflow.md` — 手順
- `references/naming-conventions.md` — 命名規則
- `references/frontmatter-template.md` — フロントマター
- `references/page-threshold.md` — ページ作成基準

**入力**: URL / ファイルパス / テキスト
**出力**: raw/にソース保存 + wiki/sources/に要約 + 概念スタブ/記事

### Compile（構築）

wiki全体の整合性を維持し知識を統合する。

実行前に以下をReadツールで読み込むこと:
- `references/compile-workflow.md` — 手順
- `references/quality-standards.md` — 品質基準
- `references/page-threshold.md` — 昇格基準

**入力**: all / concepts / sources / 特定ページ名
**出力**: 更新されたwikiページ + 再構築されたindex.md

### Query（質問）

ナレッジベースを横断検索して引用付きの合成回答を生成する。

実行前に以下をReadツールで読み込むこと:
- `references/query-workflow.md` — 手順

**入力**: 質問テキスト
**出力**: 引用付き回答 + wiki/outputs/に保存

### Lint（健康診断）

ナレッジベースの品質問題を検出し修正する。

実行前に以下をReadツールで読み込むこと:
- `references/lint-workflow.md` — チェック項目
- `references/quality-standards.md` — 品質基準

**入力**: all / links / frontmatter / stale / naming
**出力**: 問題レポート + 自動修正

## 初期化（Init）

初回セットアップ時のみ実行。

`references/init-workflow.md` を Read ツールで読み込んで手順に従うこと。

## テンプレート

ページ作成時に該当テンプレートをReadツールで読み込むこと:
- `references/concept-template.md` — 概念ページ
- `references/source-template.md` — ソース要約
- `references/index-template.md` — index.md
- `references/log-template.md` — log.md

## 既存コンテンツとの共存

`references/migration-strategy.md` を Read ツールで読み込むこと。

要点: 既存324ファイルは移動しない。`/wiki-ingest path="..."` で個別に取込可能。

## obsidian-cliとの連携

vault操作はobsidian-cliスキルを輸送層として使用する。
必要に応じて obsidian-cli の SKILL.md を Read して参照。

**安全ルール**: 書き込み先は `wiki/` または `raw/` 配下のみ。既存フォルダへの書き込み禁止。
**機密情報**: raw/に個人情報・認証情報を含むファイルを投入しないこと。要約経由で拡散するリスクあり。

主要コマンド:
```bash
OB=<YOUR_OBSIDIAN_CLI_PATH>
V="vault=<YOUR_VAULT_NAME>"

# 読み書き
$OB read path="wiki/index.md" $V
$OB create path="wiki/concepts/example.md" content="..." $V
$OB append file="wiki/log" content="..." $V

# 検索
$OB search query="キーワード" path="wiki/" $V
$OB links file="wiki/concepts/example" $V
$OB backlinks file="wiki/concepts/example" $V
$OB orphans $V
```

## 操作完了チェックリスト

毎操作後に以下を確認:
- [ ] フロントマター付与済みか
- [ ] wiki/index.md を更新したか
- [ ] wiki/log.md に操作記録を追記したか
- [ ] 未解決wikilinkがないか
- [ ] 命名規則（kebab-case）に従っているか

## スラッシュコマンド

| コマンド | 用途 |
|---------|------|
| `/wiki-init` | フォルダ構造のスキャフォールド |
| `/wiki-ingest` | ソース素材の取込・要約生成 |
| `/wiki-compile` | wiki整合性維持・知識統合 |
| `/wiki-query` | 横断検索＋引用付き回答 |
| `/wiki-lint` | ヘルスチェック＋自動修正 |

## 関連スキル

- **obsidian-cli** — vault読み書きの基盤（輸送層）
- **skill-improve** — スキル品質管理

## 改訂履歴

| 日付 | 変更内容 | 変更理由 |
|------|---------|---------|
| 2026-04-12 | 初版作成 | Karpathy式AI外部脳の実装 |
