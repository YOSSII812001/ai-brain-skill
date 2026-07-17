# AI Brain睡眠モード: $ARGUMENTS

compileは「眠っている間の記憶整理」、lintは「毎日の健康診断」である。
既定はcompile 4時間ごと、lint 毎日17:00。通常はターミナルを表示せず自動で動く。

## action

- 省略 / `status`: 状態、最終成功、次回予定
- `configure compile <minutes> lint <HH:mm>`: 整理予定を変更
- `enable`: 再開
- `disable`: 停止
- `run-now compile [scope]`
- `run-now lint [scope]`
- `doctor`: 診断
- `doctor --repair`: taskや状態の既知問題を診断して安全修復
- `approve-bulk [max-files] [max-bytes]`: 初回の大量整理を1回だけ承認
- `doctor --repair --approve-state-reset`: 壊れた状態ファイルを退避して初期化
- `rebind "<new-vault-path>"`: vault移動後に旧taskを止めて新しい場所へ結び直す
- `reconfigure --approve-config-reset`: 壊れた設定を退避して再生成
- `repair-installation`: 現在の設定を保ったままsetupを再実行
- `uninstall`: taskを削除しruntimeは保持

## 実行

現在のvault rootにある`CLAUDE.md`を読み、`AI_BRAIN_RUNTIME_ROOT`、`AI_BRAIN_SCRIPT_PATH`、`VAULT_PATH`を取得する。値がない場合や、現在のvaultと`VAULT_PATH`が一致しない場合は実行しない。

actionを検証し、次のscriptの対応するparameterへ変換して実行する。

```powershell
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{script-path}\manage-ai-brain-sleep.ps1" -Action Status -RuntimeRoot "{runtime-root}"
```

`approve-bulk`では、最初に`Status`の`bulkEstimate`を表示する。対象ファイル数、対象バイト数、変更上限を人間に説明し、明示的な承認を受けた後だけ`-Action ApproveBulk`を実行する。必要なら`-BulkMaxFiles`と`-BulkMaxBytes`を渡す。承認は24時間・1回限りである。

`configure`では、新旧の予定を表示して人間に1回確認する。承認後だけ`-Action Configure -CompileMinutes <minutes> -LintLocalTime <HH:mm> -ApproveScheduleChange`を実行する。

`disable`では定期整理が止まることを説明し、人間の承認後だけ`-ApproveDisable`を渡す。`uninstall`ではtaskだけを削除し、runtime・recovery・技術ログは残すことを示す。人間の承認後だけ`-ApproveUninstall`を渡す。復元データを消す高機能なuninstallはこの機能に含めない。通常の状態確認で承認したと推測しない。

`doctor --repair --approve-state-reset`では、状態ファイルを変更する前に人間の明示的な承認を受ける。実行後は`stateResetBackupPath`を必ず伝える。

`rebind`では、新しいvault pathが実在することを確認してから、`setup-ai-brain.ps1 -PreviousRuntimeRoot "{runtime-root}" -VaultPath "{new-vault-path}" -ReconfigureSleep -Apply`を1回実行する。新taskの試運転と旧taskの削除が両方成功した結果だけを完了として伝える。

`reconfigure --approve-config-reset`では、設定を変更する前に現在の既定（記憶の整理は4時間ごと、健康診断は17:00）を説明し、人間の選択を1回受ける。その後、`setup-ai-brain.ps1 -VaultPath "{vault-path}" -ReconfigureSleep -ApproveConfigReset -SleepModeChoice {Accept|Custom|Disable} -Apply`を1回実行し、`configResetBackupPath`を必ず伝える。

`repair-installation`では、`setup-ai-brain.ps1 -VaultPath "{vault-path}" -Apply`を実行する。既存の同意と時刻を再利用し、破損した配布物やtaskを再登録する。

`doctor`が配布物やbootstrapの破損を検知した場合は、自動復元しない。`repair-installation`を1回だけ案内する。

停止中でも`run-now`は1回だけ実行できる。定期処理中に重なった要求は、その処理の終了時に同じ非表示プロセスが引き取る。

未知actionを推測しない。正常時は状態だけを短く返す。attention時は`attentionAction`を1件だけ返す。
