# AI Brain — Obsidianを「話しかけて使う」外部脳に

Claude Code / Codex対応

Claude CodeやCodexに普段の言葉で頼むだけで、Obsidianを「使うほど育つ外部脳」に変えるskillです。

難しいコマンドを覚える必要はありません。たとえば、こんな頼み方で使えます。

```text
このURLを外部脳に入れて
最近追加したメモを整理して
手元の知識から、RAGとファインチューニングの違いを教えて
リンク切れや古い情報がないか見て
自動整理が動いているか教えて
```

AI Brainが依頼の意図を読み取り、取込・整理・検索・点検などの適切な処理へつなぎます。`/wiki-query`や`/wiki-compile`などのスラッシュコマンドは、直接操作したい人向けの任意機能です。

> [!NOTE]
> このskillは、Obsidianそのものを置き換えるアプリではありません。Claude CodeまたはCodexとObsidianの間に入り、自然な依頼をナレッジベース操作へ変換するラッパーとして働きます。

## できること

| やりたいこと | 普段の言葉での頼み方 | AI Brainの処理 |
|---|---|---|
| 記事やメモを追加する | 「このURLを外部脳に入れて」 | 内容を保存し、要約と関連ページを作る |
| 複数のメモをまとめて取り込む | 「inboxのメモを全部整理して」 | inboxを順番に取り込み、処理済みのものを整理する |
| 知識をつなぎ直す | 「最近のメモを整理して」 | 関連する知識を結び、目次を更新する |
| 手元の知識から答えを得る | 「過去のメモから○○を教えて」 | ナレッジベースを横断し、出典付きで答える |
| 状態を点検する | 「リンク切れや古い情報を見て」 | リンク、書式、古いページなどを点検する |
| 自動整理を管理する | 「自動整理の状態を教えて」 | 状態や直近の結果を確認する |

内部では、次の4つの処理を使い分けています。

| 処理 | 役割 |
|---|---|
| **Ingest（取込）** | URL、ファイル、文章を外部脳へ追加する |
| **Compile（整理）** | 新旧の知識を結び、ページと目次を整える |
| **Query（検索・回答）** | 複数のメモを横断し、出典付きの答えを作る |
| **Lint（点検）** | リンク切れ、書式の乱れ、古い情報を見つけて直す |

## 仕組み

既存のノートや取り込んだ原文を守りながら、AIが管理するwiki層だけを育てます。

```text
Obsidian Vault
├── main/          ← 既存のノート（AIは読み取りのみ）
├── inbox/         ← まとめて取り込みたいファイルの一時置き場
├── raw/           ← 取り込んだ原文（AIは読み取りのみ）
│   ├── articles/  papers/  repos/  datasets/  assets/
├── wiki/          ← AIが整理・更新するナレッジ層
│   ├── index.md  log.md
│   ├── _meta/sleep-report.md
│   ├── concepts/  entities/  sources/
│   ├── syntheses/  outputs/  attachments/
├── CLAUDE.md      ← 構造と運用ルール
└── その他の既存フォルダはそのまま
```

| 層 | 場所 | 役割 |
|---|---|---|
| 既存コンテンツ | `main/`など | AIは読めるが、書き換えない |
| 原文 | `raw/` | 取り込んだ素材を保存し、書き換えない |
| ナレッジ | `wiki/` | AIが要約、関連付け、検索結果を管理する |
| ルール | `CLAUDE.md` | vault固有の場所や運用ルールを定義する |

## 必要なもの

- Windows
- [Claude Code](https://claude.ai/claude-code) または [Codex](https://github.com/openai/codex)
- [Obsidian](https://obsidian.md) 1.12.4以降（CLI対応版）
- Git

## 導入方法

### いちばん簡単な方法：AIにセットアップを頼む

リポジトリをcloneしたら、Claude CodeまたはCodexで次のように頼んでください。

```text
このai-brain-skillをセットアップして。
Obsidianのvaultは「C:\path\to\your\Obsidian Vault」です。
まず変更内容だけ見せて、確認後に適用して。
```

AIは[SETUP.md](SETUP.md)に従い、最初に変更予定だけを表示します。あなたが内容を確認するまで、skillやWindowsの自動実行設定は適用しません。

セットアップ中に、自動整理を次のどれにするか1回だけ聞きます。

- 標準設定を使う：4時間ごとに知識を整理し、毎日17:00に点検する
- 好きな時間へ変える
- 自動整理を使わない

導入後は、普段の言葉でそのまま使えます。

### 手動でセットアップする

まずは変更を加えない確認モードで実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-ai-brain.ps1 `
  -VaultPath "C:\path\to\your\Obsidian Vault" `
  -VaultName "Obsidian Vault" `
  -Target codex `
  -SleepModeChoice Accept
```

表示されたコピー先、初回整理の見積り、自動整理の予定を確認します。問題がなければ、同じコマンドへ`-Apply`を追加して適用します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-ai-brain.ps1 `
  -VaultPath "C:\path\to\your\Obsidian Vault" `
  -VaultName "Obsidian Vault" `
  -Target codex `
  -SleepModeChoice Accept `
  -Apply
```

Claude Codeへ入れる場合は、`-Target codex`を`-Target claude`へ変えてください。詳しい設定、時刻変更、再設定は[SETUP.md](SETUP.md)にまとめています。

## 使い方

### 普段の使い方

特別な書式はありません。Claude CodeやCodexに、やりたいことをそのまま伝えます。

```text
この論文を外部脳に入れて: https://example.com/paper

プロジェクトAについて、これまでのメモをまとめて

今日追加した情報を整理して、関連する知識につないで

外部脳の調子を見て、直せる問題は直して
```

「外部脳」「ナレッジベース」「Obsidian」「メモを整理」「手元の知識から教えて」などの言葉を含めると、AIがこのskillを見つけやすくなります。

### スラッシュコマンドで直接操作する

スラッシュコマンドは必須ではありません。処理を明示したい場合だけ使ってください。

| コマンド | 用途 | 自然な頼み方の例 |
|---|---|---|
| `/wiki-init` | 初回のフォルダ作成 | 「外部脳を初期化して」 |
| `/wiki-ingest` | URLやファイルを1件取り込む | 「このURLを外部脳に入れて」 |
| `/wiki-ingest-inbox` | inboxをまとめて取り込む | 「inboxを全部整理して」 |
| `/wiki-compile` | 知識と目次を整理する | 「最近のメモを整理して」 |
| `/wiki-query` | 手元の知識を検索する | 「過去のメモから○○を教えて」 |
| `/wiki-lint` | リンクや書式を点検する | 「外部脳を健康診断して」 |
| `/wiki-sleep` | 自動整理を管理する | 「自動整理の状態を教えて」 |

直接操作する場合の例です。

```text
/wiki-ingest https://example.com/interesting-article
/wiki-query RAGとファインチューニングの違いは？
/wiki-compile all
/wiki-lint all
/wiki-sleep status
```

## 睡眠モード：覚えていなくても整理が続く

睡眠モードは、外部脳をWindowsの裏側で定期的に整える機能です。

| 処理 | 標準の予定 | 内容 |
|---|---|---|
| 記憶の整理（Compile） | 4時間ごと | 新しい知識を結び、役立つ下書きを育て、目次を更新する |
| 健康診断（Lint） | 毎日17:00 | リンク、書式、名前、古いページ、孤立ページを点検する |

常駐アプリは動かしません。Windowsタスクスケジューラが必要な時だけPowerShellを起動し、処理後に終了します。登録後の定期実行や「今すぐ整理」では、通常はターミナルを表示しません。PCをスリープ解除することもありません。

最新の結果と次回予定は、`wiki/_meta/sleep-report.md`で確認できます。状態変更も自然な言葉で頼めます。

```text
自動整理の状態を教えて
今すぐ知識を整理して
毎日の健康診断を今すぐ実行して
自動整理を止めて
自動整理を再開して
調子が悪いので診断して
```

内部の直接コマンドは次のとおりです。

```text
/wiki-sleep status
/wiki-sleep run-now compile
/wiki-sleep run-now lint
/wiki-sleep disable
/wiki-sleep enable
/wiki-sleep doctor
```

詳しい安全対策、復旧、削除方法は[睡眠モードの仕様](references/sleep-mode.md)を参照してください。

## データを守る仕組み

- AIが書き込む場所は`raw/`と`wiki/`に限定します。既存ノートは変更せず、`raw/`へ保存した原文もあとから書き換えません。
- 秘密情報らしい内容を含むファイルは、AIへ渡す前にファイル単位で除外します。
- 大きなvaultは安定した単位に分け、途中で止まっても完了済みの処理を繰り返しません。
- 変更は一度作業領域で検証し、問題がなければまとめて反映します。
- 反映に失敗した場合は、記録を使って元の状態へ戻します。
- ログには、vaultの本文やAIの生出力を保存しません。

## 主な改善点

現在の版では、最初の公開版より導入と日常利用を大きく簡単にしています。

| 改善 | どう変わったか |
|---|---|
| 自然言語の入口 | コマンド名を知らなくても、依頼の意図から適切な処理を選べる |
| 安全なセットアップ | 適用前に変更予定と初回整理の見積りを確認できる |
| 環境ごとの設定 | vaultやObsidianの場所を1回のセットアップで反映できる |
| 自動整理 | CompileとLintをWindowsの裏側で定期実行できる |
| 大きなvaultへの対応 | 入力を分け、途中から再開し、最後にまとめて反映できる |
| 秘密情報の除外 | 怪しいファイルは全文を除外し、内容や場所をログへ残さない |
| 復旧 | 作業記録、ロールバック、診断、日次レポートを備える |
| 継続的な検証 | ローカル検証とGitHub Actionsで配布物のずれを検出する |

## リポジトリ構成

```text
ai-brain-skill/
├── README.md                        # この説明
├── SETUP.md                         # AIと進める詳しいセットアップ
├── SKILL.md                         # Codex向け配布用skill
├── skill/
│   ├── SKILL.md                     # Claude Code向け配布用skill
│   └── references/                  # 23 micro-reference files
├── commands/                        # 7個のwiki-*コマンド
├── references/                      # Codex向け参照ファイル
├── scripts/
│   ├── setup-ai-brain.ps1           # 確認モードから始まるインストーラー
│   ├── invoke-ai-brain-sleep.ps1    # 自動整理の実行役
│   ├── manage-ai-brain-sleep.ps1    # 状態確認、修復、操作
│   └── validate-repo.ps1            # ローカル・CI共通の検証
├── tests/
│   └── run-tests.ps1                # PowerShell回帰テスト
└── vault/
    └── CLAUDE.md                    # vault用ルールのひな型
```

## 開発者向け検証

READMEやskillを変更した場合は、次の検証を実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-repo.ps1
```

この検証では、参照ファイルの同期、READMEのファイル数、古い設定値、PowerShell構文、Markdownリンクなどを確認します。CIではWindows PowerShell 5.1とPowerShell 7の回帰テストも実行します。

## 設計方針

- 必要な参照ファイルだけを読み、AIの会話領域を使いすぎない
- 既存のvaultを移動せず、そのまま共存する
- AIが管理する範囲を`wiki/`へ限定する
- すべてのwikiページへYAML frontmatterを付け、検索と点検に使う
- コマンドを知っている人にも、知らない人にも同じ機能を提供する

## クレジット

[Andrej Karpathy](https://x.com/karpathy)の「LLM Wiki / AI External Brain」という考え方（[original gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)）をもとにしています。詳しいガイドは[@hooeem](https://x.com/hooeem/status/2041196025906418094)、日本語での紹介は[@ClaudeCode_love](https://x.com/ClaudeCode_love/status/2042886840177557533)を参考にしています。

## ライセンス

MIT
