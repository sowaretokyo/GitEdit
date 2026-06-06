# Contributing to GitEdit

GitEdit へのコントリビューションを歓迎します。Issue / Pull Request どちらも歓迎です。

## はじめに

- バグ報告や機能要望は **Issues** に。テンプレートに沿って書いてもらえると助かります。
- 大きめのデザイン変更（新規タブ追加、データモデル変更など）は、PR を出す前に Issue で
  方向性を相談してください。手戻り防止のためです。
- 小さな修正（typo、配色、コメント補強、テスト追加）は直接 PR を投げて構いません。

## 開発環境

- macOS 14 (Sonoma) 以降
- Xcode 15.4 以降（または Swift 5.10+）
- システム `git`

```bash
git clone https://github.com/sowaretokyo/GitEdit.git
cd GitEdit
swift build
swift test          # 全パーサのユニットテストが走る（< 0.1 秒）
swift run           # アプリ起動
open Package.swift  # Xcode で開く
```

## プロジェクト構成

```
Sources/GitEdit/
├── GitEditApp.swift       # @main + AppDelegate（アプリアイコン設定など）
├── Editor/                # CodeEditor (NSTextView) / DiffView / DiffLineAnalyzer
├── Models/                # Branch, Commit, FileChange, FileNode, Repository, ...
├── Services/              # GitClient (git CLI ラッパ), パーサ群, GitHub API/Auth, Keychain, FSEvents
├── ViewModels/            # @MainActor な ObservableObject 群（状態管理）
├── Views/                 # SwiftUI ビュー（Sidebar/Repository/Search/Explorer/Welcome）
├── Settings/              # 環境設定ウィンドウ
├── Theme/                 # デザイントークン (DT.Space, DT.Status, ...)
├── Localization/          # i18n の L() helper
└── Resources/             # AppIcon.png, ja.lproj/en.lproj の文字列
Tests/GitEditTests/        # パーサ・モデルのユニットテスト
scripts/                   # ビルド・署名・配布スクリプト
.github/workflows/         # CI + Release ワークフロー
```

## アーキテクチャ方針

- **MVVM**: ロジックは ViewModel に集約。View は表示と入力転送のみ。
- **`@MainActor` ViewModel**: 全 ViewModel が `@MainActor`。UI スレッドへの戻りを書かなくて済む。
- **git CLI 経由**: libgit2 ではなく `git` をサブプロセス呼び出し。引数は必ず配列で渡し、
  シェル展開を経由させない（`GitClient.runGit(_:)` 参照）。
- **パーサは pure function**: `GitStatusParser` / `GitBranchParser` / `DiffLineAnalyzer` /
  `FileTreeBuilder` などはすべて入力 → 出力の関数。テストしやすさのため。
- **デザイントークン**: padding / radius / status color は `DT.*` 経由。マジックナンバー禁止。
- **i18n**: ユーザーに見える文字列は必ず `L("...")` を通す。`Resources/{ja,en}.lproj` を更新。

## コーディング規約

- インデント 4 スペース。Swift 標準の命名規則。
- 内部限定の関数・型は `private` / `fileprivate` を明示。
- コメントは「なぜ」を書く。「何をしているか」はコード自身が語るので冗長コメントは避ける。
- `TODO:` / `FIXME:` は理由と Issue 番号を併記。残骸を放置しない。

## セキュリティ

- `git` への引数は必ず `[String]` 配列で渡す（`/bin/sh -c "..."` 形式で組み立てない）。
- 認証情報・トークンは `KeychainStore` 経由で保存。UserDefaults / プレーンテキストに書かない。
- URL / フォーム body のエンコードは `URLComponents` を使う（独自パーセントエンコードを避ける）。
- 脆弱性の報告は [SECURITY.md](./SECURITY.md) を参照してください。

## テスト

新しいパーサや解析ロジックを足したら `Tests/GitEditTests/` に対応するテストを追加してください。
View 層は手動確認で OK ですが、計算プロパティや純粋関数はカバーできるなら追加が望ましいです。

```bash
swift test
```

CI でも自動で走ります（`.github/workflows/ci.yml`）。

## コミット規約

`<type>: <概要>` の形を緩く採用しています。type は以下のいずれか：

- `feat:` 新機能
- `fix:` バグ修正
- `refactor:` 挙動を変えないコード整理
- `test:` テスト追加・修正
- `docs:` ドキュメント
- `chore:` ビルド・CI・依存関係などの作業
- `style:` 見た目・整形のみ

本文では「なぜそうしたか」を書いてもらえると助かります。

## Pull Request

1. main から作業ブランチを切る
2. `swift build` と `swift test` をパスさせる
3. PR テンプレートに沿って説明を書く
4. レビュー → マージ

軽微な PR はそのまま、デザイン判断を含む PR は Issue で擦り合わせてから出してもらえると
スムーズです。

## リリース運用（メンテナ向け）

`bash scripts/release.sh` で対話的にタグを切ると CI が `.dmg` を作って Releases に上げます。
CI で署名・Notarize するため、リポジトリの **Settings → Secrets and variables → Actions**
に以下を登録しておく必要があります：

| Secret | 内容 |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Developer ID 証明書 (.p12) を `base64 -i cert.p12` した文字列 |
| `P12_PASSWORD` | .p12 のパスワード |
| `KEYCHAIN_PASSWORD` | CI 内で作る一時キーチェーンのパスワード（任意） |
| `SIGNING_IDENTITY` | `Developer ID Application: <Name> (TEAMID)` |
| `APPLE_ID` | Apple ID メールアドレス |
| `APPLE_ID_PASSWORD` | [App 用パスワード](https://account.apple.com/account/manage) |
| `APPLE_TEAM_ID` | 10 桁のチーム ID |

DMG レイアウトは `scripts/sign-and-notarize.sh` 内の `create-dmg` 呼び出しで定義。
背景画像は `scripts/assets/dmg-background.png`（540×380 / Retina は 1080×760）。

## ライセンス

このプロジェクトに貢献することで、あなたのコントリビューションが
[MIT License](./LICENSE) の下で公開されることに同意したものとみなされます。
