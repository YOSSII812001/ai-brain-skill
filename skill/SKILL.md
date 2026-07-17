---
name: ai-brain
description: |
  Karpathy式AI外部脳。Obsidian vault上でraw/wiki/CLAUDE.mdの3層構造により
  パーソナルナレッジベースを管理するスキル。Ingest/Compile/Query/Lintの4サイクル運用。
  「ナレッジベース」「外部脳」「知識管理」「wiki」「Obsidian」「ノート整理」
  「情報整理」「記事取り込み」「論文管理」に関するリクエストが来たら必ずこのスキルを使うこと。
  /wiki-ingest, /wiki-ingest-inbox, /wiki-compile, /wiki-query, /wiki-lint, /wiki-init, /wiki-sleep コマンドもこのスキルが担当。
  ソース素材の取込、wikiページの構築・更新、横断検索と引用付き回答生成、
  ヘルスチェックと自動修正など、ナレッジベース関連の操作は全てこのスキルの守備範囲。
  トリガー: ai-brain, knowledge-base, wiki-ingest, wiki-ingest-inbox, wiki-compile, wiki-query, wiki-lint,
  wiki-init, wiki-sleep, 自動整理, 睡眠モード, ナレッジベース, 外部脳, 知識管理, Obsidian, ノート整理, 情報整理
---

# AI External Brain — Karpathy式ナレッジベース管理

## 概要

Obsidian vault上にKarpathy提唱のAI外部脳システムを構築・運用するスキル。
3層構造（raw / wiki / CLAUDE.md）と4操作サイクル（Ingest / Compile / Query / Lint）で
使うほど賢くなるパーソナルナレッジベースを実現する。

## 環境情報

環境依存値の正典は vault root の `CLAUDE.md`。
詳細は `references/environment-config.md` を Read ツールで読み込むこと。

必須値:
- **Vault名**: vault schema の `VAULT_NAME`
- **Vaultパス**: vault schema の `VAULT_PATH`
- **inbox**: `VAULT_PATH\inbox\`
- **Obsidian CLI**: vault schema の `OBSIDIAN_CLI_PATH`
- **Skill path**: インストール先の `AI_BRAIN_SKILL_PATH`

公開版の `SKILL.md` は、ユーザー固有の Obsidian 実行パスを固定しない。
初回セットアップ時に `vault/CLAUDE.md` と command files のプレースホルダを置換する。

## セッション初期化

**毎セッションの冒頭で必ず実行**:

1. vault rootの `CLAUDE.md` を Read して構造・ルールを把握
2. `wiki/index.md` を Read してナレッジベースの現状を把握
3. `wiki/log.md` の先頭10行を Read して直近の操作を確認
4. `wiki/_meta/sleep-report.md` があればReadし、`wiki-sleep status`でtask、runner、設定、生存確認を点検

`status`は安全に直せる既知driftだけを自動修復する。`paused`や`attention`を状態確認だけで解除しない。

## 睡眠モード

詳細は`references/sleep-mode.md`をReadすること。

### 初回同意

対象vaultに現行`consentVersion`がない場合、setup scriptを対話実行しない。AIが利用者へ次の意味を説明する。

> 外部脳にも、人間の睡眠のような整理時間があります。
> compileは、新しい情報を過去の知識と結びつける「記憶の整理」です。4時間ごとに確認します。
> lintは、切れたリンクや古い知識を見つける「記憶の健康診断」です。毎日17:00に確認します。
> この設定でよいですか？

利用者へ1つだけ質問し、次のどれかを受け取る。

- このまま設定する
- 時間を変更する
- 自動整理を使わない

回答後にだけ、明示引数へ変換する。

- 既定値: `-SleepModeChoice Accept -CompileIntervalHours 4 -LintTime "17:00"`
- 時間変更: `-SleepModeChoice Custom`と利用者が指定した値
- 無効化: `-SleepModeChoice Disable`

setupのdry-runで初回整理の件数と容量を取得する。初回大量整理が必要なら見積りを示し、同じHuman Gateで承認された場合だけ`-ApproveInitialBulk`を付ける。setup、Scheduled Task、runner自身は`Read-Host`を使わない。

### 自然言語の操作

利用者の言葉を次へ正規化する。

| 利用者の依頼 | action |
|---|---|
| 状態を教えて、昨夜の結果 | `status` |
| 時間を変えて | `configure` |
| 自動整理を再開して | `enable` |
| 自動整理を止めて | `disable` |
| 今すぐ整理して | `run-now compile` |
| 今すぐ健康診断して | `run-now lint` |
| 調子を直して | `doctor`または`doctor --repair` |
| vaultを移動した | `rebind` |
| 自動整理を削除して | `uninstall` |

schedule変更、disable、uninstall、初回大量整理、未知設定や状態の再生成はHuman Gateである。実行内容と保持・削除されるものを説明し、人が明示的に承認した後だけ承認引数を渡す。通常run、安全な既知driftの修復、enableでは質問しない。

`attention`では表示された操作を1件だけ案内する。未知actionや複数の復旧案を推測しない。

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

主要コマンド例:
```powershell
$ObsidianCli = "<OBSIDIAN_CLI_PATH>"
$VaultArg = "vault=<VAULT_NAME>"

# 読み書き
& $ObsidianCli read "path=wiki/index.md" $VaultArg
& $ObsidianCli create "path=wiki/concepts/example.md" 'content=...' $VaultArg
& $ObsidianCli append "file=wiki/log" 'content=...' $VaultArg

# 検索
& $ObsidianCli search "query=キーワード" "path=wiki/" $VaultArg
& $ObsidianCli links "file=wiki/concepts/example" $VaultArg
& $ObsidianCli backlinks "file=wiki/concepts/example" $VaultArg
& $ObsidianCli orphans $VaultArg
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
| `/wiki-sleep` | 自動整理の設定・状態・停止・再開・今すぐ実行・診断 |

## ループ運用（上級者向け互換）

通常運用は睡眠モードを使う。`/loop /wiki-compile`と`/loop /wiki-lint`も、独自lockや直接編集をせず、1回のpending requestとして共通オーケストレーターへ渡す。詳細は`references/loop-operation.md`をReadすること。

## 関連スキル

- **obsidian-cli** — vault読み書きの基盤（輸送層）
- **skill-improve** — 繰り返し発生する構造問題をスキル改善候補へ戻す

## 改訂履歴

| 日付 | 変更内容 | 変更理由 |
|------|---------|---------|
| 2026-04-12 | 初版作成 | Karpathy式AI外部脳の実装 |
| 2026-04-13 | description最適化・Cowork導入・環境情報設定 | トリガー精度向上・実環境適用 |
| 2026-04-13 | ループ運用セクション追加 | /loop /wiki-compile, /loop /wiki-lint のセルフペース自動化対応 |
| 2026-04-14 | inbox/バッチIngest機能追加 | inbox/フォルダ新設、/wiki-ingest-inboxコマンド追加 |
| 2026-07-17 | 睡眠モード追加 | 4時間ごとの記憶整理、毎日17:00の健康診断、非表示実行、安全な復元、Human Gateを統合 |
