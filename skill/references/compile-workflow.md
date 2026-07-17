# Compileサイクル

compileは、人が睡眠中に記憶を整理するように、新しい情報を過去の知識へ結びつける処理です。

## 実行経路

定期実行と`/wiki-compile`は、どちらも睡眠モードの共通オーケストレーターを通します。AIへvaultを直接編集させません。

1. vault単位のnamed mutexを取得する。経過時間だけで所有権を奪わない。
2. 未完了journalがあれば、新しい処理より先に復旧する。
3. `main/`、`raw/`、`wiki/`のmanifestを比較する。
4. 定期実行で変更がなければ、AIを呼ばず「確認済み・整理不要」と記録する。
5. 変更があればruntime上の作業用コピーからJSON変更案を作る。
6. 許可path、件数、容量、UTF-8、frontmatter、内部リンク、indexを検証する。
7. baselineが変わっていないことを確認し、journalとbackupを作って`wiki/`だけへ反映する。
8. 最終検証に失敗した場合は逆順に戻し、実行前hashとの一致を確認する。

`wiki/_meta/.lock`を30分で削除する旧契約は使いません。30分を超える正常な処理も、process treeとmutexが生きている限り継続中として扱います。

## 整理内容

1. `wiki/sources/`の新規・更新ページを確認する
2. 2つ以上のsourceがあるstubを完全記事へ育てる
3. 既存の概念へ新情報を統合する
4. wikilinkを補強する
5. `wiki/index.md`を再構築する
6. 必要な統合分析を`wiki/syntheses/`へ作る
7. frontmatterの`date_modified`を更新する
8. `wiki/log.md`へ記録する

睡眠レポート自身はmanifest比較から除外します。compileとlintが同時に必要な場合は、compileを先に1回だけ実行します。
