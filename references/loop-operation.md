# Loop operation

Use `/loop /wiki-compile` or `/loop /wiki-lint` for self-paced operation.
Each tick starts with the normal session initialization, so the loop does not need previous context.

## Shared change detection

1. Read `wiki/log.md` and find the latest matching operation timestamp.
2. Detect files changed after that timestamp.
3. Branch on whether changed files exist.

Use PowerShell on Windows and keep the detection read-only:

```powershell
Get-ChildItem -LiteralPath $VaultWikiPath -Recurse -Filter *.md |
  Where-Object { $_.LastWriteTimeUtc -gt $LastRunUtc }
```

## Self-paced compile

Start with `/loop /wiki-compile`.
Schedule the next tick with prompt `/wiki-compile`.

Flow:

1. Run session initialization.
2. Detect changed files under `wiki/sources/`.
3. Find stub concepts with at least 2 sources.
4. If changes exist, run the relevant compile steps.
5. If no changes exist, skip work and schedule the next tick.

Delay rules:

| Situation | delaySeconds | Reason |
|---|---:|---|
| Compile changed files | 120 | Recheck cascading changes |
| Sources changed, no promotion yet | 180 | Watch threshold crossing |
| No changes | 1200 | Idle check every 20 minutes |

## Self-paced lint

Start with `/loop /wiki-lint`.
Schedule the next tick with prompt `/wiki-lint`.

Flow:

1. Run session initialization.
2. Detect changed files under `wiki/`.
3. If changes exist, lint only changed files.
4. If no changes exist, run periodic health checks.
5. Record the result in `wiki/log.md`.

Delay rules:

| Situation | delaySeconds | Reason |
|---|---:|---|
| Lint fixed files | 120 | Check side effects |
| Changes exist, all clean | 270 | Stay inside prompt cache |
| No changes, periodic clean | 1800 | Idle check every 30 minutes |

## Parallel operation

Start compile first, then start lint after 5-10 minutes.
Compile owns index rebuilds. Lint checks the result and must not rebuild `wiki/index.md`.
