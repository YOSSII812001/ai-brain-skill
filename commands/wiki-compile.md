# AI Brainの記憶整理: $ARGUMENTS

このcommandはvaultを直接編集しない。睡眠モードの共通orchestratorへrequestを渡す。

## scope

- 省略 / `all`: wiki全体
- `concepts`: conceptsだけ
- `sources`: sourcesだけ
- その他のページ名: `page:<ページ名>`へ正規化

absolute path、`..`、wiki外pathは拒否する。

## 実行

現在のvault rootにある`CLAUDE.md`を読み、`AI_BRAIN_RUNTIME_ROOT`と`AI_BRAIN_SCRIPT_PATH`を取得する。値がない場合や、現在のvaultと`VAULT_PATH`が一致しない場合は実行しない。

PowerShellで次を実行する。`{script-path}`、`{runtime-root}`、`<scope>`だけを検証済みの値で置換する。

```powershell
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{script-path}\manage-ai-brain-sleep.ps1" -Action RunNow -RuntimeRoot "{runtime-root}" -Operation compile -Scope "<scope>"
```

taskがoff / paused / attentionの場合は直接agentを起動せず、表示された操作を1件だけ案内する。
