# Lintサイクル

lintは、人の睡眠中の健康診断にあたります。記憶のつながりと管理情報を毎日点検します。

## 実行経路

定期実行と`/wiki-lint`は、compileと同じ睡眠モードのオーケストレーターを通します。

1. vault単位のnamed mutexを取得する。時刻だけでlockを期限切れにしない。
2. 未完了journalを先に復旧する。
3. 拒否対象名や秘密情報らしい内容を持つwikiファイルを丸ごと除外する。
4. 残ったwikiを、promptのUTF-8 byte上限に収まる決定的なchunkへ分ける。
5. 未完了batchがあれば、同じ入力の完了済みchunkを再利用する。
6. 各chunkでlintのJSON変更案を作る。workerは入力chunk内の既存pageだけを修正し、`wiki/index.md`と`wiki/log.md`を変更しない。
7. 共有ファイルを最後の1回で整え、chunk間の同一path変更と`wiki/`外への変更を拒否する。
8. 全変更の件数、容量、UTF-8、frontmatter、内部リンク、indexをまとめて検証する。
9. journalとbackupを作り、外部編集がない場合だけ1回反映する。
10. 最終検証に失敗した場合は、実行前manifestへ戻す。

lintは変更の有無にかかわらず、毎日17:00の健康診断として1回動きます。compileも期限なら、compileの完了後にlintを実行します。

除外したファイルの値、本文、pathはprompt、state、report、logへ残しません。
元ファイルと除外したwiki pathは変更しません。

## 点検内容

- 未解決wikilinkを直す。新しいstubが必要なら次回compileの候補にする
- 欠けたfrontmatterを補う
- デッドエンドと孤立ページへ適切なつながりを作る
- 命名違反を直す
- 6か月を超えた記述を`stale`候補にする
- 矛盾へ警告と両方のsourceを残す
- 繰り返す構造問題は`self-improvement-workflow.md`の改善候補にする

結果は`wiki/log.md`と`wiki/_meta/sleep-report.md`へ記録します。睡眠レポート自身は次回の変更として数えません。
