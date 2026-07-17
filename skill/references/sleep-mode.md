# 睡眠モード

睡眠モードは、AI外部脳を人の睡眠に近づける仕組みです。
利用者はノートを使い続けるだけでかまいません。

## 人の睡眠にたとえると

- compileは「記憶の整理」です。4時間ごとに新しい情報を結び直します。
- lintは「毎日の健康診断」です。毎日17:00にリンクや書式を点検します。
- 変更がなければAIを呼びません。不要な処理と利用料を増やしません。
- lintとcompileが重なったときは、compileを先に終えてからlintを動かします。

初回設定では、skillがこの間隔と時刻でよいか利用者に尋ねます。setup scriptとScheduled Taskは対話しません。
利用者は、そのまま使う、時刻を変える、自動整理を使わない、の3つから選べます。

## ふだんの使い方

利用者による定期メンテナンスは不要です。
`wiki/_meta/sleep-report.md` を開くと、次の内容を日本語で確認できます。

- 最後の生存確認
- 直近の結果と変更件数
- 次回の記憶の整理（compile）と記憶の健康診断（lint）
- 新しくつながった概念、修正したリンクと管理情報
- スキップした理由
- 自動復元を使ったか
- 人の対応が必要な場合の操作1件

AIは通常の利用開始時に状態を点検します。
12時間以上動作を確認できない場合は、登録済みタスクを実際に試運転します。
状態ファイルだけが消えた場合は、安全な初期状態へ自動復元します。
未知の形式や壊れた状態は推測で上書きせず、人の承認を求めます。

## 画面を出さない仕組み

Windowsでは、vaultごとにS4U方式のタスクを1件登録します。
登録に管理者権限が必要なPCでは、初回setupだけWindowsの管理者確認を1回表示します。
その1件に、4時間ごとのcompileと毎日17:00のlintの2つの開始条件を持たせます。

タスクは最小権限、非対話、非表示で動きます。
子プロセスは`UseShellExecute=false`、`CreateNoWindow=true`、標準入出力の直接接続で起動します。
起動ゲートは子プロセスをJob Objectへ入れてからAIを開始します。
時間切れや異常終了では、子孫プロセスをまとめて停止してから終了します。
無表示保証の対象は、登録後の定期実行と「今すぐ整理」です。初回setupの管理者確認は対象外です。

この方式は、Hermes Agent Desktopの非表示起動を参考にしています。
Hermesも非対話のProcessStartInfoと`-WindowStyle Hidden`を使います。
AI Brainは、Task SchedulerのHidden設定と起動ゲートを追加しています。

「一瞬も表示されない」という判定は、実機のウィンドウイベントE2Eで確認します。
コード上の設定だけでは合格にしません。

## 安全な反映

AIへ渡す入力は、機密候補を除いた作業用コピーです。
AIはツールとネットワークを使わず、JSONの変更案だけを返します。

AI Brainは変更案を検証してから、`wiki/`だけへ反映します。
書き込み前には空き容量、パス、frontmatter、内部リンク、件数、容量を確認します。
途中で失敗した場合はjournalとbackupから元へ戻します。

初回の整理はsetup中に差分を試算します。skillが件数と容量を見せ、利用者が同意した場合だけ`-ApproveInitialBulk`を渡します。承認は24時間・1回だけ有効です。

## 管理コマンド

- `wiki-sleep status`: 状態を点検し、安全に直せる問題を自動修復する
- `wiki-sleep configure`: 時刻を説明し、人の承認後に変更する
- `wiki-sleep enable`: 自動整理を再開する
- `wiki-sleep disable`: 自動整理を止める
- `wiki-sleep run-now compile`: compileを今すぐ動かす
- `wiki-sleep run-now lint`: lintを今すぐ動かす
- `wiki-sleep doctor --repair`: taskや状態の既知問題を診断して修復する。配布物の破損は自動復元せず、setupの再実行を案内する
- `wiki-sleep approve-bulk`: 初回の大量整理を1回だけ承認する
- `wiki-sleep uninstall`: taskを削除し、runtimeは保管する
- `wiki-sleep rebind`: vault移動後に新taskを試運転し、旧taskを削除する

schedule変更、停止、uninstall、初回大量整理はHuman Gateです。skillが変更内容を1つの質問で確認した後だけ、明示的な承認引数をscriptへ渡します。

自動整理を止めても、明示したcompileとlintは同じ安全制御で実行できます。

## 補足

- PCが停止中の時刻は処理しません。次の起動後に1回だけ追いつきます。
- PCを勝手にスリープ解除しません。
- 複数vaultは別のID、runtime、task、mutexで分離します。
- 技術ログは`%LOCALAPPDATA%\ai-brain\<vault-id>\logs\`へ保存します。
- 技術ログにはAIの会話本文や認証情報を保存しません。
- 旧compile/lintタスクは、対象vaultを確認し、XMLを退避して移行試験に合格した後に削除します。
- 旧タスクの個別停止と利用者が変えた時刻は、新しい設定へ引き継ぎます。
