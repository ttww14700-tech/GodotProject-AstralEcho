每次開始處理此專案時，先讀取 Notion 專案頁：
https://app.notion.com/p/GodotProject-AstralEcho-370dacf0068d80dd93b8f7286e4935d4

如果 Notion 無法讀取，需明確告知使用者，並改用本地專案檔案與目前對話上下文繼續。

只有當使用者明確提出「紀錄這次」時，才需要寫入 Notion 工作日誌。

紀錄方式：
- 在 Notion 專案頁的工作日誌區域，或最近一篇工作日誌下方，新增一個子頁。
- 子頁名稱使用台北時間日期：`YYYY-MM-DD 工作日誌`。
- 如果同一天已有同名或同日期工作日誌，使用 `YYYY-MM-DD 工作日誌 (2)`、`(3)` 依序命名。
- 子頁內容需包含：
  - 本次修改摘要
  - 使用者提出的反饋
  - 已完成的驗證或測試
  - 下一步可觀察或待調整項目

除非使用者要求，不要自動修改 Notion 內容。

如果使用者要求更新 Notion 的灰模目標或規則：
- 先讀取相關 Notion 主頁與子頁。
- 若 checklist 項目下方有規則子頁，需同步更新子頁內容，再回到主頁更新 checklist 狀態。
- 只勾選已經由使用者確認完成，或已完成實作與驗證的項目。

## Git 交接資訊

- GitHub remote：`https://github.com/ttww14700-tech/GodotProject-AstralEcho.git`
- 本地分支：`main`
- 遠端分支：`origin/main`
- 最新 commit 以 `git log -1 --oneline` 查詢結果為準，不在此檔案固定記錄。
- 推送前需先執行 `git status --short --branch` 確認狀態。
- 一般提交流程：`git add .` → `git commit -m "..."` → `git push`。

## Git 忽略與提交規則

- `.godot/` 不上傳。
- `.DS_Store` 不上傳。
- `export_presets.cfg` 不上傳。
- `*.translation` 不上傳。
- 不要提交 Godot editor cache 或 macOS 暫存檔。
- 若 Notion 的 git 區塊與本地 `git remote -v` 或 `git status --short --branch` 不一致，以本地 git 查詢結果為準，並回報使用者。
- 若使用者說「上傳到 git」，需先檢查狀態、commit，再 push 到 `origin/main`。
