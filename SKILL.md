---
name: ai-brain
description: |
  Karpathy式AI外部脳。Obsidian vault上でraw/wiki/CLAUDE.mdの3層構造により
  パーソナルナレッジベースを管理するスキル。Ingest/Compile/Query/Lintの4サイクル運用。
  「ナレッジベース」「外部脳」「知識管理」「wiki」「Obsidian」「ノート整理」
  「情報整理」「記事取り込み」「論文管理」に関するリクエストが来たら必ずこのスキルを使うこと。
  /wiki-ingest, /wiki-ingest-inbox, /wiki-compile, /wiki-query, /wiki-lint, /wiki-init コマンドもこのスキルが担当。
  ソース素材の取込、wikiページの構築・更新、横断検索と引用付き回答生成、
  ヘルスチェックと自動修正など、ナレッジベース関連の操作は全てこのスキルの守備範囲。
  トリガー: ai-brain, knowledge-base, wiki-ingest, wiki-ingest-inbox, wiki-compile, wiki-query, wiki-lint,
  wiki-init, ナレッジベース, 外部脳, 知識管理, Obsidian, ノート整理, 情報整理
---

# AI External Brain — Karpathy式ナレッジベース管理

## 概要

Obsidian vault上にKarpathy提唱のAI外部脳システムを構築・運用するスキル。
3層構造（raw / wiki / CLAUDE.md）と4操作サイクル（Ingest / Compile / Query / Lint）で
使うほど賢くなるパーソナルナレッジベースを実現する。

## 環境情報

- **メインVault名**: Obsidian Vault
- **メインVaultパス**: `C:\Users\zooyo\Documents\Obsidian Vault`
- **inbox**: vault root直下 `C:\Users\zooyo\Documents\Obsidian Vault\inbox\`
- **Obsidian CLI**: `"/c/Users/zooyo/Downloads/Obsidian/Obsidian.com"`
- **Vault CLAUDE.md**: vault root に配置済み
- **備考**: `C:\Users\zooyo\Documents\Obsidian\ytakeshita` は別vaultとして存在するが、日常運用（inbox・スケジュール実行等）はObsidian Vault側で行う

## セッション初期化

**毎セッションの冒頭で必ず実行**:

1. vault rootの `CLAUDE.md` を Read して構造・ルールを把握
2. `wiki/index.md` を Read してナレッジベースの現状を把握
3. `wiki/log.md` の先頭10行を Read して直近の操作を確認

## アーキテクチャ（3層構造）

詳細は `references/schema-overview.md` を Read ツールで読み込むこと。

| 層 | パス | 役割 |
|----|------|------|
| Inbox | `inbox/` | バッチ投入バッファ。ユーザーが事前配置、処理後に空になる |
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

**入力**: URL / ファイルパス / テキスト（単体は `/wiki-ingest`、一括は `/wiki-ingest-inbox`）
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

**安全ルール**: 書き込み先は `wiki/` または `raw/` 配下のみ。既存フォルダへの書き込み禁止。`inbox/` は読み取り＋処理後削除のみ。
**機密情報**: raw/に個人情報・認証情報を含むファイルを投入しないこと。要約経由で拡散するリスクあり。

主要コマンド:
```bash
OB="/c/Users/zooyo/Downloads/Obsidian/Obsidian.com"
V="vault=Obsidian Vault"

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
| `/wiki-ingest` | ソース素材の取込・要約生成（単体） |
| `/wiki-ingest-inbox` | inbox/の全ファイルをバッチ取込 |
| `/wiki-compile` | wiki整合性維持・知識統合 |
| `/wiki-query` | 横断検索＋引用付き回答 |
| `/wiki-lint` | ヘルスチェック＋自動修正 |

## ループ運用（/loop対応）

`/loop /wiki-compile` または `/loop /wiki-lint` でセルフペースの自動運用が可能。
各tickはSKILL.mdのセッション初期化から始まるため、コンテキスト不要で自己完結する。

### 共通: 変更検出ロジック

1. `wiki/log.md` を Read し、最新の該当操作（compile or lint）のタイムスタンプを取得
2. Bashで `find wiki/ -name "*.md" -newer <前回log時刻の基準ファイル>` を実行
3. 変更ファイルリストが空か否かで分岐

### セルフペースcompile

**起動**: `/loop /wiki-compile`
**ScheduleWakeupのprompt**: `/wiki-compile`（毎tick同一文字列で継続）

**各tickのフロー**:
1. セッション初期化（index.md + log.md Read）
2. 変更検出: wiki/sources/ の前回compile以降の更新を検出
3. 昇格候補: concepts/ の stub で sources数 >= 2 のものを検出
4. 分岐:
   - 変更あり → 差分compile（昇格・wikilink・syntheses・index再構築・log記録）
   - 変更なし → スキップ（log記録不要）
5. ScheduleWakeup で次tickスケジュール

**間隔決定**:
| 状況 | delaySeconds | 理由 |
|------|-------------|------|
| compile実行あり（ファイル変更した） | 120 | compile自体の変更が追加差分を生む可能性 |
| source更新あり・昇格未達 | 180 | 近い将来の昇格に備え短めに待機 |
| 変更なし | 1200 | 20分後に再チェック |

### セルフペースlint

**起動**: `/loop /wiki-lint`
**ScheduleWakeupのprompt**: `/wiki-lint`

**各tickのフロー**:
1. セッション初期化（index.md + log.md Read）
2. 変更検出: wiki/ 配下全体の前回lint以降の更新を検出
3. 分岐:
   - 変更あり → 変更ファイル対象の差分lint（未解決wikilink・frontmatter・デッドエンド・命名規則）
   - 変更なし → 定期ヘルスチェックのみ（孤立ページ・陳腐化 >6ヶ月）
4. log.mdに記録（問題なければ「lint: clean」）
5. ScheduleWakeup で次tickスケジュール

**間隔決定**:
| 状況 | delaySeconds | 理由 |
|------|-------------|------|
| lint修正実行あり | 120 | 修正の副作用チェック |
| 変更あり・問題なし | 270 | キャッシュ内で次を待つ |
| 変更なし・定期clean | 1800 | 30分後に定期チェック |

### 並行運用ガイド

compileを先に起動し、5-10分後にlintを起動する。
lintはcompileの出力をチェックする側なので、この順序が自然。

```
セッション1: /loop /wiki-compile
セッション2: /loop /wiki-lint    ← 5-10分後
```

注意: 両者が同時にlog.mdへ追記する可能性があるが、追記操作のみなので競合リスクは低い。
index.mdの再構築はcompileのみが行う（lintは変更しない）。

## 関連スキル

- **obsidian-cli** — vault読み書きの基盤（輸送層）
- **skill-improve** — スキル品質管理

## 改訂履歴

| 日付 | 変更内容 | 変更理由 |
|------|---------|---------|
| 2026-04-12 | 初版作成 | Karpathy式AI外部脳の実装 |
| 2026-04-13 | description最適化・Cowork導入・環境情報設定 | トリガー精度向上・実環境適用 |
| 2026-04-13 | ループ運用セクション追加 | /loop /wiki-compile, /loop /wiki-lint のセルフペース自動化対応 |
| 2026-04-14 | inbox/バッチIngest機能追加 | inbox/フォルダ新設、/wiki-ingest-inboxコマンド追加 |
