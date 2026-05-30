# GitEdit

[![CI](https://github.com/sowaretokyo/GitEdit/actions/workflows/ci.yml/badge.svg)](https://github.com/sowaretokyo/GitEdit/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/sowaretokyo/GitEdit?display_name=tag)](https://github.com/sowaretokyo/GitEdit/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](#必要環境)

GitHub Desktop の哲学を受け継ぐ、macOS ネイティブの Git GUI クライアント。

> 「ほどよく出来ることを制限して、変なことが起きないように」をそのままに、Apple らしい使い心地で。

## ダウンロード

最新版（macOS 14 以降 / Universal binary）：

**👉 [GitEdit.dmg をダウンロード](https://github.com/sowaretokyo/GitEdit/releases/latest/download/GitEdit.dmg)**

リリースノートは [Releases](https://github.com/sowaretokyo/GitEdit/releases/latest) から。
Vercel 上の LP からもダウンロードできます（準備中）。

## 特徴

- **SwiftUI + AppKit ネイティブ** — 軽量、瞬間起動、Mac らしい操作感
- **完全日本語 UI**
- **コミットメッセージ ↑↓ 履歴** — 過去のコミットメッセージを呼び出し
- **個別ステージング** — ファイル単位でチェックして選択的にコミット
- **差分ビューア / 編集モード** — 色分けされた unified diff、その場で編集して保存
- **コミット履歴** — 相対日付・著者アバター付きリスト
- **検索 / エクスプローラ** — `git grep` ベースの全文検索とファイルツリー
- **ネットワーク操作** — フェッチ / プル / プッシュ をトーストで通知
- **初心者向けガードレール** — force push, interactive rebase 等は隠す or 明示警告

## 必要環境

- macOS 14 (Sonoma) 以降
- システムの `git`（macOS Command Line Tools で入る）

開発する場合は追加で：

- Xcode 15 以降（または `swift` 5.10+）

## 開発

```bash
# Xcode で開く（推奨）
open Package.swift

# ターミナルで実行
swift run
```

## ローカルでの .app / .dmg ビルド

```bash
# .app を build/GitEdit.app に生成
bash scripts/build-app.sh

# 署名 + Notarize + .dmg 化（Apple Developer 加入が必要）
export SIGNING_IDENTITY="Developer ID Application: <Your Name> (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_ID_PASSWORD="app-specific-password"
export APPLE_TEAM_ID="ABCDE12345"
bash scripts/sign-and-notarize.sh
```

未署名で動作確認だけしたい場合は `scripts/build-app.sh` だけ走らせて `build/GitEdit.app` を開けば OK（初回は右クリック→開く）。

## リリースフロー（CI）

`v*` タグを push すると GitHub Actions が自動で Universal `.dmg` をビルド・署名・Notarize して
Releases に添付します。

### 簡単な方法（推奨）

```bash
bash scripts/release.sh
```

直近のタグから patch / minor / major のどれを上げるかを対話で選び、確認後にタグを切って
push します。実行前に「main にいる」「未コミット変更なし」「origin/main と同期済み」を自動で
チェックします。

```bash
# 引数で直接指定もできる
bash scripts/release.sh patch    # v0.1.0 → v0.1.1
bash scripts/release.sh minor    # v0.1.0 → v0.2.0
bash scripts/release.sh major    # v0.1.0 → v1.0.0
bash scripts/release.sh 1.2.3    # 明示的なバージョン
```

### 手動で

```bash
git tag v0.1.0 && git push origin v0.1.0
```

配布ファイル名はバージョンに依存させず常に `GitEdit.dmg` 固定です。
これにより以下の URL は永久不変で、Vercel LP 側からのリンクを張り替える必要はありません：

```
https://github.com/sowaretokyo/GitEdit/releases/latest/download/GitEdit.dmg
```

DMG 内のレイアウト（ウィンドウサイズ・アプリ位置・Applications ショートカット）は
[create-dmg](https://github.com/create-dmg/create-dmg) で整形しています。
`scripts/assets/dmg-background.png` を置くとそれを背景画像として使います
（推奨サイズ 540×380）。

事前に **Settings → Secrets and variables → Actions** に以下を登録してください：

| Secret | 内容 |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Developer ID Application 証明書（.p12）を `base64 -i cert.p12` した文字列 |
| `P12_PASSWORD` | .p12 のパスワード |
| `KEYCHAIN_PASSWORD` | CI 内で作る一時キーチェーンのパスワード（任意の文字列） |
| `SIGNING_IDENTITY` | `Developer ID Application: <Your Name> (TEAMID)` |
| `APPLE_ID` | Apple ID メールアドレス |
| `APPLE_ID_PASSWORD` | [App-specific password](https://appleid.apple.com/account/manage) |
| `APPLE_TEAM_ID` | 10 桁のチーム ID |

## 構成

```
Sources/GitEdit/
├── GitEditApp.swift       # @main + AppDelegate
├── Editor/                # CodeEditor (NSTextView) / DiffView
├── Theme/                 # デザイントークン
├── Views/                 # SwiftUI ビュー
├── ViewModels/            # 状態管理
├── Models/                # データモデル
├── Services/              # git CLI ラッパー、パーサー
└── Resources/             # AppIcon.png, i18n strings
scripts/
├── build-app.sh           # SwiftPM → .app バンドル化
├── sign-and-notarize.sh   # 署名 + Notarize + .dmg
└── entitlements.plist     # Hardened Runtime 用
.github/workflows/release.yml  # タグ push で .dmg を Releases に
```

## 参考

- GitHub Desktop (TypeScript/Electron): https://github.com/desktop/desktop

## コントリビュート

歓迎します。Issue / PR どちらも受け付けています。

- [CONTRIBUTING.md](./CONTRIBUTING.md) — 開発環境・アーキ方針・コーディング規約
- [CHANGELOG.md](./CHANGELOG.md) — 各バージョンの変更点
- [SECURITY.md](./SECURITY.md) — 脆弱性報告窓口
- [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) — Contributor Covenant 2.1

## ライセンス

[MIT](./LICENSE) — © 2026 [株式会社ソワレ東京](https://sowaretokyo.co.jp)
