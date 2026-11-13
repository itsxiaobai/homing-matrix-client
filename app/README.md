# homing

Homing（原「RING」，2026-11-12 更名，避開 Amazon Ring LLC 商標）的 Flutter App 本體。
基於 Matrix 協定（SDK：`matrix` / matrix-dart-sdk）；專案說明、藍圖與進度見上層目錄的
`README.md`／`agent_v1_3.md`／`PROGRESS.md`。

## 開發

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

依賴授權清單與新增依賴規則見上層 `DEPENDENCIES.md` 與 `AGENTS.md`（新增／升級依賴須先停下取得人類批准）。
