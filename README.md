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
open Package.swift   # Xcode で開く
swift run            # ターミナルから起動
swift test           # ユニットテスト
```

ローカルで `.app` だけ作りたい場合：

```bash
bash scripts/build-app.sh   # build/GitEdit.app を生成（未署名）
```

初回起動時は Gatekeeper に弾かれるので、Finder で右クリック → 開く。

## リリース

```bash
bash scripts/release.sh
```

`patch / minor / major` のどれを上げるかを対話で選ぶと、タグを切って push します。
あとは GitHub Actions が `.dmg` を作って [Releases](https://github.com/sowaretokyo/GitEdit/releases/latest) に上げます。

```bash
# 引数指定も可
bash scripts/release.sh patch    # v0.1.0 → v0.1.1
bash scripts/release.sh minor    # v0.1.0 → v0.2.0
bash scripts/release.sh major    # v0.1.0 → v1.0.0
```

ダウンロード URL はバージョンに依存せず常に固定：

```
https://github.com/sowaretokyo/GitEdit/releases/latest/download/GitEdit.dmg
```

### 初回セットアップ（Secrets）

CI で `.dmg` を署名・Notarize するため、リポジトリの
**Settings → Secrets and variables → Actions** に以下を登録：

| Secret | 内容 |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Developer ID 証明書 (.p12) を `base64 -i cert.p12` した文字列 |
| `P12_PASSWORD` | .p12 のパスワード |
| `KEYCHAIN_PASSWORD` | CI 内で作る一時キーチェーンのパスワード（任意） |
| `SIGNING_IDENTITY` | `Developer ID Application: <Name> (TEAMID)` |
| `APPLE_ID` | Apple ID メールアドレス |
| `APPLE_ID_PASSWORD` | [App 用パスワード](https://account.apple.com/account/manage) |
| `APPLE_TEAM_ID` | 10 桁のチーム ID |

### DMG の見た目

レイアウトは [create-dmg](https://github.com/create-dmg/create-dmg) で整形しています。
背景画像を差し替えたい場合は `scripts/assets/dmg-background.png` を置き換え
（540×380、Retina なら 1080×760）。

## 構成

```
Sources/GitEdit/        SwiftUI + AppKit 本体
Tests/GitEditTests/     パーサ・モデルのユニットテスト
scripts/
├── build-app.sh         SwiftPM → .app バンドル化
├── sign-and-notarize.sh 署名 + Notarize + .dmg
├── release.sh           対話的にタグを切って push
└── assets/              DMG 背景画像など
.github/workflows/
├── ci.yml               PR / main で swift test
└── release.yml          タグ push で .dmg を Releases に
```

詳しい構成とアーキ方針は [CONTRIBUTING.md](./CONTRIBUTING.md) を参照。

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
