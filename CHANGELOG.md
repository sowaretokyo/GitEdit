# Changelog

このプロジェクトの主な変更点を [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/)
形式で記録します。バージョニングは [Semantic Versioning](https://semver.org/lang/ja/)
に従います。

## [Unreleased]

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

[Unreleased]: https://github.com/sowaretokyo/GitEdit/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/sowaretokyo/GitEdit/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/sowaretokyo/GitEdit/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/sowaretokyo/GitEdit/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/sowaretokyo/GitEdit/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/sowaretokyo/GitEdit/releases/tag/v0.1.0
