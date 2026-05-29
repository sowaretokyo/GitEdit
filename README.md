# GitCode

GitHub Desktop の哲学を受け継ぐ、macOS ネイティブの Git GUI クライアント。

> 「ほどよく出来ることを制限して、変なことが起きないように」をそのままに、Apple らしい使い心地で。

## 特徴

- **SwiftUI + AppKit ネイティブ** — 軽量、瞬間起動、Mac らしい操作感
- **完全日本語 UI**
- **コミットメッセージ ↑↓ 履歴** — 過去のコミットメッセージを呼び出し
- **初心者向けガードレール** — force push, interactive rebase 等は隠す or 明示警告

## 必要環境

- macOS 14 (Sonoma) 以降
- Xcode 15 以降
- システムに `git`（macOS Command Line Tools で入る）

## 開発

```bash
# Xcode で開く（推奨）
open Package.swift

# ターミナルで
swift build
swift run
```

## 構成

```
Sources/GitCode/
├── GitCodeApp.swift       # @main エントリ
├── Theme/                 # デザイントークン
├── Views/                 # SwiftUI ビュー
├── ViewModels/            # 状態管理
├── Models/                # データモデル
└── Services/              # git CLI ラッパー、パーサー
```

## 参考

- GitHub Desktop (TypeScript/Electron): https://github.com/desktop/desktop
  - ローカルに参考用クローンあり: `../desktop/`
  - git コマンドのシーケンスや UX 判断の参考に使用。

## ロードマップ

### Phase 1（雛形・コミット動線）
- [x] プロジェクト雛形
- [x] Welcome 画面
- [x] ローカルリポジトリ追加
- [x] ファイル変更一覧
- [x] コミットメッセージ ↑↓ 履歴
- [x] 全ステージ → コミット

### Phase 2（読み取り強化）
- [ ] 個別ステージ/アンステージ
- [ ] 差分ビューア
- [ ] 履歴ビュー（コミットリスト）

### Phase 3（ネットワーク・ブランチ）
- [ ] fetch / pull / push
- [ ] ブランチ作成・切替・マージ
- [ ] clone / init

### Phase 4（賢い UX）
- [ ] 巨大ファイル警告
- [ ] Conventional Commits 補助
- [ ] .gitignore プリセット
- [ ] conflict 解決 UI

### Phase 5（拡張）
- [ ] GitHub API 連携（PR、Issue）
- [ ] 軽量コードエディタ（GitCode の "Code" 部分）
