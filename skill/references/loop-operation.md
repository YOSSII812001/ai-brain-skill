# Loop operation

`/loop /wiki-compile`と`/loop /wiki-lint`は、上級者向けの互換入口です。通常運用では睡眠モードを使います。

loopから実行する場合も、直接vaultを編集したり、独自のlockを作ったりしません。`/wiki-compile`または`/wiki-lint`がpending requestを保存し、S4Uタスクの共通オーケストレーターへ渡します。

## 守ること

- 定期処理と同じnamed mutex、staging、検証、journal、rollbackを使う
- `wiki/_meta/.lock`の時刻を見て削除しない
- taskが実行中なら新しいprocessを増やさず、終了前のpending再読込で引き取る
- compileとlintを並列実行しない。同時に必要ならcompile、lintの順にする
- sleep reportを変更検出から除外する
- `paused`または`attention`をloopで解除しない

繰り返し間隔を別に管理すると、4時間ごと・毎日17:00という利用者の設定と二重になります。そのため、loopは1回の安全な要求だけを発行し、次回予定は睡眠モードに任せます。
