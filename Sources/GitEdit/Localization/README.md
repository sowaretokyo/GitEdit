# Localization

`L("日本語キー")` で囲んだ全ての文字列が翻訳対象。日本語キーがソース・オブ・トゥルース。

## 構成

- `Resources/ja.lproj/Localizable.strings` — 日本語（キーと一致する場合は省略可。L() の `value:` フォールバックで埋まる）
- `Resources/en.lproj/Localizable.strings` — 英語翻訳

## 翻訳の追加

新しい locale を足すには `Resources/<code>.lproj/Localizable.strings` を作るだけ。
キー（日本語）→ 翻訳 のマッピングを書く:

```
"コミット" = "Commit";
"変更されたファイル" = "Changed files";
```

足してない locale ではキー（日本語）がそのまま表示される。
