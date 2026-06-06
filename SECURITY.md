# Security Policy

## 脆弱性の報告

GitEdit に脆弱性を見つけた場合、**公開の Issue や PR では報告しないでください**。
以下の手段で非公開に報告してください：

- メール: **service@sowaretokyo.co.jp**（件名に `[GitEdit Security]` を付けてください）
- GitHub の [Private vulnerability reporting](https://docs.github.com/ja/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)

報告には以下を含めていただけると助かります：

- 影響を受けるバージョン
- 再現手順（PoC があれば理想）
- 想定される影響範囲
- 修正案（もしあれば）

## 対応方針

- 初回の確認応答は 5 営業日以内を目安にお返しします
- 重大度に応じて、修正・公開アドバイザリ・CVE 取得を検討します
- 修正後、報告者のクレジット表記を希望される場合は CHANGELOG に記載します

## サポート対象バージョン

| Version  | サポート |
| -------- | -------- |
| 0.1.x    | ✅       |
| < 0.1    | ❌       |

最新のマイナーバージョンのみセキュリティパッチを提供します。

## 既知のリスクと方針

GitEdit はサンドボックス無効で動作します（システムの `git` を呼び出す必要があるため）。
ローカル環境の `git` 設定・SSH 鍵・キーチェーンへアクセスします。これは macOS Hardened
Runtime + Apple Notarization で保証された配布バイナリに対する一般的な仕組みです。

組織内で「不明な開発者」アプリの実行を制限している場合、IT 管理者にお問い合わせください。
