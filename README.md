# GitEdit

[![CI](https://github.com/sowaretokyo/GitEdit/actions/workflows/ci.yml/badge.svg)](https://github.com/sowaretokyo/GitEdit/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/sowaretokyo/GitEdit?display_name=tag)](https://github.com/sowaretokyo/GitEdit/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

GitHub Desktop の哲学を受け継ぐ、macOS ネイティブの Git GUI クライアント。

## ダウンロード

**👉 [GitEdit.dmg をダウンロード](https://github.com/sowaretokyo/GitEdit/releases/latest/download/GitEdit.dmg)**（macOS 14+ / Universal）

## 特徴

- SwiftUI + AppKit ネイティブで軽量・瞬間起動
- 完全日本語 UI
- 個別ステージング・差分ビューア・その場編集
- コミット履歴 / `git grep` ベース全文検索 / ファイルエクスプローラ
- 初心者向けガードレール（force push 等は隠す）

## 開発

```bash
open Package.swift   # Xcode で開く
swift run            # 起動
swift test           # テスト
```

## リリース

```bash
bash scripts/release.sh
```

`patch / minor / major` を対話で選ぶとタグを切って push、CI が `.dmg` を [Releases](https://github.com/sowaretokyo/GitEdit/releases/latest) に上げます。

## コミュニティ

- [CONTRIBUTING.md](./CONTRIBUTING.md) — 開発・アーキ方針・CI Secrets
- [CHANGELOG.md](./CHANGELOG.md) — 変更履歴
- [SECURITY.md](./SECURITY.md) — 脆弱性報告

## ライセンス

[MIT](./LICENSE) — © 2026 [株式会社ソワレ東京](https://sowaretokyo.co.jp)
