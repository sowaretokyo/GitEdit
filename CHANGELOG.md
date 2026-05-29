# Changelog

このプロジェクトの主な変更点を [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/)
形式で記録します。バージョニングは [Semantic Versioning](https://semver.org/lang/ja/)
に従います。

## [Unreleased]

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

[Unreleased]: https://github.com/sowaretokyo/GitEdit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/sowaretokyo/GitEdit/releases/tag/v0.1.0
