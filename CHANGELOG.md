# Changelog

このプロジェクトの主な変更点を [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/)
形式で記録します。バージョニングは [Semantic Versioning](https://semver.org/lang/ja/)
に従います。

## [Unreleased]

### 追加 (Added)

- ブランチのマージとブランチ削除を UI から実行できるようにした（未マージブランチの削除は明示確認付き、黙って強制削除しない）
- マージ競合の解決 UI を追加（競合ファイル一覧、自分/相手の変更の採用、エディタで編集、解決マーク、マージ続行/中止）
- stash（変更の退避）を追加：ブランチ切替時の「持っていく/退避する/キャンセル」3択ダイアログ、手動退避（未追跡ファイル既定で含む）、一覧からの復元・pop・削除（pop 失敗時も退避は失われない）
- hunk 単位・行単位のステージング/アンステージングを追加（未ステージ/ステージ済みの2セクション表示）
- 直前コミットの修正（amend）を追加（プッシュ済みコミットは修正不可としてブロック）
- リモートと分岐した状態での pull 時に「マージして取り込む」誘導ダイアログを追加
- 直前操作の取り消し（undo）を追加：コミット・amend・マージ・ブランチ切替を1段階戻せる（プッシュ済み履歴の巻き戻しはブロック）
- 差分の side-by-side（分割）表示を追加（統合/分割をトグルで切替、設定は永続化）
- 画像ファイルの変更前/変更後の並置プレビューを追加
- 部分 stash を追加：hunk/行を選択して一部だけ退避（git 2.35 以降）。stash 一覧に内容プレビュー（ファイル一覧）も追加
- コミット編集を追加：履歴の右クリックからメッセージ編集・ひとつ前のコミットへの統合・削除・並び替え（プッシュ済み・マージコミットを含む範囲は編集不可、操作後は undo で復元可能）
- サイドバーのリポジトリをグループ化・ピン留めできるようにした（既存データは自動移行、旧バージョンとの相互運用も安全）
- リポジトリを独立した新しいウィンドウで開けるようにした（右クリックまたは ⌘N、複数リポジトリの同時表示に対応）
- プルリクエストタブを追加：PR 一覧/詳細/CI ステータス表示、PR ブランチのチェックアウト（フォーク PR は閲覧専用）、PR 作成、レビュー（コメント・承認・変更リクエスト）、マージ（マージ方法選択・確認付き）まで GitEdit 内で完結
- ブランチ名やコミットメッセージ中の issue 番号（#123）から GitHub の issue を開けるリンクを追加

### 変更 (Changed)

- fast-forward できない pull のエラー文言から「リベース」の表現を除去（UI はマージのみを誘導）

## [0.1.5] - 2026-07-07

### 追加 (Added)

- Git 実行時の `PATH` を正規化し、GUI 起動時でも Homebrew / pnpm / Volta / asdf / nodenv などの開発ツールを見つけやすくした

### 修正 (Fixed)

- 変更チェックボックスを操作したとき、変更一覧の並びが意図せず変わる場合がある問題を修正
- Git エラー詳細シートで、技術的な詳細を展開しても生ログが表示されない場合がある問題を修正

### 変更 (Changed)

- GitHub Actions / Release workflow で利用する Actions のバージョンを更新

## [0.1.4] - 2026-06-13

### 修正 (Fixed)

- Sparkle の自動アップデートを Notarization に通せるよう署名処理を修正

## [0.1.3] - 2026-06-13

### 修正 (Fixed)

- Sparkle helper を Notarization に通せるよう署名処理を修正

## [0.1.2] - 2026-06-13

### 追加 (Added)

- 変更一覧で Shift キーによる範囲選択を追加
- 変更ファイルの破棄操作を追加
- 未 push コミットが履歴上で分かりやすくなる表示を追加
- 追加したリポジトリと選択中リポジトリの永続化を追加
- ファイルシステム監視による画面更新を強化
- Sparkle によるアプリ内アップデート確認を追加

### 修正 (Fixed)

- カレントリポジトリの表示が崩れる問題を修正
- エディタで編集した内容がコミット前に staged されない問題を修正
- 初回 push で upstream 未設定により失敗しやすい問題を修正
- 差分編集後の内容反映と保存タイミングを改善

### 変更 (Changed)

- 画面サイズとリポジトリ周辺 UI のレイアウトを調整
- リリース workflow を Sparkle feed 生成に対応

## [0.1.1] - 2026-05-30

### 追加 (Added)

- 対話的にバージョンを上げてタグを push する `scripts/release.sh` を追加
- 配布 DMG 用の背景画像とアセット管理メモを追加

### 変更 (Changed)

- 配布 DMG の見た目を調整し、`releases/latest/download/GitEdit.dmg` で常に最新版を取得できるようにした
- README をスリム化し、開発・運用情報を `CONTRIBUTING.md` に集約

## [0.1.0] - 2026-05-30

初回 OSS リリース。

### 追加 (Added)

- ローカルリポジトリの追加・クローン・初期化
- ファイル変更一覧と個別ステージング（チェックボックス UI）
- 差分ビューア（unified diff、行番号ガター付き）
- 編集モード：差分タブ内で直接ファイル編集・保存
- コミット履歴ビューアと、コミットごとのファイル別差分
- ブランチピッカー（ローカル / リモート / アップストリーム追従）
- フェッチ / プル / プッシュ（初回 push の自動 `-u` 含む）
- ファイル全文検索（`git grep` ベース）
- ファイルエクスプローラ（gitignore 認識）
- GitHub OAuth サインイン（Device Authorization Grant）
- アカウントアバター表示（GitHub / Gravatar）
- ライト / ダーク / システム追従テーマ
- 日本語 / 英語ロケール対応
- ファイルシステム監視による自動更新（FSEvents）
- `.app` ビルド・署名・Notarization スクリプトと
  GitHub Releases 自動配布の CI

### セキュリティ (Security)

- `git` 引数はすべて配列で渡し、シェル経由の実行を排除
- 認証トークンは Keychain 保存
- OAuth body エンコードは `URLComponents` を使用

[Unreleased]: https://github.com/sowaretokyo/GitEdit/compare/v0.1.5...HEAD
[0.1.5]: https://github.com/sowaretokyo/GitEdit/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/sowaretokyo/GitEdit/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/sowaretokyo/GitEdit/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/sowaretokyo/GitEdit/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/sowaretokyo/GitEdit/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/sowaretokyo/GitEdit/releases/tag/v0.1.0
