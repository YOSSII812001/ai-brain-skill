# AIと進めるセットアップ

この手順は、AIコーディングアシスタントが実行します。利用者が伝えるものは、リポジトリの場所とObsidian vaultの場所です。

## 初回に確認すること

AI skillはscriptを呼ぶ前に「睡眠モード」を説明し、利用者へ予定を確認します。setup scriptとScheduled Taskは質問せず、明示された選択だけを保存します。

- compile（コンパイル）は、人が眠っている間に記憶を整理する作業に相当します。増えたノートを結び直し、目次を整えます。既定は4時間ごとです。
- lint（リント）は、毎日の健康診断に相当します。リンク切れや書式の乱れを点検します。既定は毎日17:00です。
- どちらも通常はターミナルを表示せず、PCの裏側で動きます。

利用者は「このまま使う」「時間を変える」「無効にする」から選べます。初回に選んだ後は、普段のコマンド操作は不要です。

## 必要な情報

- `VaultPath`: Obsidian vaultの絶対パス
- `Target`: `claude`または`codex`
- `VaultName`: Obsidian CLIで使うvault名。省略時はフォルダ名
- `ObsidianCliPath`: Obsidian実行ファイル。省略時は標準の場所を探す
- `AgentExecutable`: Claude CodeまたはCodexの直接実行できる`.exe`。省略時は既知の場所を探す

## まずドライランする

リポジトリのルートで実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-ai-brain.ps1 `
  -VaultPath "C:\path\to\your\Obsidian Vault" `
  -VaultName "Obsidian Vault" `
  -Target claude `
  -SleepModeChoice Accept
```

`-Apply`を付けなければドライランです。コピー先、実行対象、compileの間隔、lintの時刻、初回整理の見積りを表示します。ファイルやタスクは変更しません。

見積りは次の3つを分けて表示します。

- vault全体のファイル数と容量
- 安全確認後にAIへ渡すテキストのファイル数と容量
- 除外するファイル数、分割数、1回の入力上限

`SleepModeChoice`を省略した場合は、skillによる同意が必要だと機械可読なエラーで返します。

S4Uタスクの登録に管理者権限が必要なPCでは、`-Apply`時にWindowsの管理者確認が1回だけ表示されます。これは人が始める初回設定です。登録後の定期実行と「今すぐ整理」は通常権限で動き、管理者確認やターミナルを表示しません。

## 内容を確認して導入する

表示内容が正しければ`-Apply`を付けます。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-ai-brain.ps1 `
  -VaultPath "C:\path\to\your\Obsidian Vault" `
  -VaultName "Obsidian Vault" `
  -Target claude `
  -SleepModeChoice Accept `
  -Apply
```

すべての環境で、skillが利用者の回答を次のどれかへ変換します。

```powershell
# 既定の4時間ごと・毎日17:00
-SleepModeChoice Accept

# 任意の予定
-SleepModeChoice Custom -CompileIntervalHours 6 -LintTime "19:30"

# 自動整理を使わない
-SleepModeChoice Disable
```

ドライランが初回整理の対象を表示した場合、skillは上記の内訳を利用者へ示します。利用者が同意した後だけ、適用時に`-ApproveInitialBulk`を追加します。この承認で許可するのは、最大100件のwiki変更を1回だけです。

`-Apply`は次を導入します。

- skill本体と23個のreference
- 7個の`wiki-*`コマンド
- vaultルートの`CLAUDE.md`
- `%LOCALAPPDATA%\ai-brain\<vault-id>\`のローカルruntime
- compileとlintを担当する1個のWindowsタスク

既存ファイルは変更前にruntimeの`migration\install-backup-*`へ退避します。途中で失敗した場合は、記録したファイルを検証しながら元に戻します。

## ターミナルを表示しない仕組み

タスクはS4U、Hidden設定、`-WindowStyle Hidden`を使います。子プロセスも`CreateNoWindow`で起動し、Windows Job Objectで終了まで管理します。無表示保証の対象は、登録後の定期実行と「今すぐ整理」です。

ただし、対象PCで「一瞬も表示されない」と言えるのは実機E2Eに合格した後です。セットアップは導入時にタスクを実行し、結果と生存確認を検証します。

## 導入後の確認

利用者は`wiki/_meta/sleep-report.md`を見るだけで、最終結果と次回予定を確認できます。

AI Brainは、秘密情報らしい内容や拒否対象名を持つファイルを丸ごと除外します。元ファイルは変更しません。睡眠レポートと状態表示には件数だけを残し、値、本文、対象pathは残しません。

安全な入力が1回の上限を超える場合、AI Brainは同じ基準で分割します。途中で止まっても、完了済みの分割は次回にやり直しません。すべての分割を検証した後、wikiへの変更を1回だけ反映します。

```text
/wiki-sleep status
/wiki-sleep run-now compile
/wiki-sleep run-now lint
/wiki-sleep disable
/wiki-sleep enable
/wiki-sleep doctor
```

初回の整理量が安全上限を超える場合は、自動で止まり、見積もりと`/wiki-sleep approve-bulk`だけを案内します。状態ファイルが壊れた場合も自動で捨てず、明示承認後にバックアップしてから直します。

## 再設定と高度な選択

予定を変更する場合は、`-ReconfigureSleep`を付けて再実行します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-ai-brain.ps1 `
  -VaultPath "C:\path\to\your\Obsidian Vault" `
  -Target codex `
  -ReconfigureSleep `
  -SleepModeChoice Custom `
  -CompileIntervalHours 4 `
  -LintTime "17:00" `
  -Apply
```

- `-SkipScheduledTask`: runtimeだけ導入し、Windowsタスクを登録しない高度な選択
- `-InstallScheduledTasks`: 互換用。現在は`-Apply`時に既定でタスクを登録する

vaultを移動した場合は、新しい`VaultPath`で再設定します。古いruntimeは自動削除しません。

## 開発者向け検証

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-repo.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run-tests.ps1 -Suite All
pwsh -NoProfile -File .\tests\run-tests.ps1 -Suite All
```

導入済みコマンドの差分は、次で確認します。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-command-sync.ps1 -Target claude
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-reference-parity.ps1
```
