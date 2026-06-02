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

## 局外 Hub 鏡頭與物件佈局規則

- 規則頁：`局外鏡頭及物件佈局規則`
  - https://www.notion.so/373dacf0068d8196b344de60ba67c86f
- Hub 據點球、鏡頭、物件佈局邏輯屬於局外系統，不要影響 `RunWorld.gd` 或 `RunWorld.tscn`。
- Hub camera 使用固定構圖參數，不因 `hub_sphere_radius` 變大而自動拉遠；球體出框可以接受，優先維持角色畫面大小與操作可讀性。
- Hub camera 需保留 `hub_camera_fov` 與 `hub_camera_screen_offset_y` 可調；不要再把 `HubCamera.fov` 寫死在程式裡。
- 目前接近範本的 Hub 構圖候選值：
  - `hub_sphere_radius = 70.0`
  - `hub_camera_pitch_deg = 31.0`
  - `hub_camera_yaw_offset_deg = 6.0`
  - `hub_camera_distance = 17.0`
  - `hub_camera_height = 12.5`
  - `hub_camera_look_at_height = 1.4`
  - `hub_camera_screen_offset_y = 0.16`
  - `hub_camera_fov = 44.0`
- Hub 球面地板格線需使用「平面方格投影到球面」的方式，不要使用會在角色腳下匯聚的經緯線格線。
- Hub 球面方格由 `HubSphereController.gd` 的 `SURFACE_GRID_EXTENT_RATIO`、`SURFACE_GRID_STEP`、`SURFACE_GRID_SEGMENT_STEP` 控制。
- Hub 物件佈局採用「平面編輯，運行時投影到球面」：
  - 物件放在 `HubSphereController/HubPrimitiveReferenceVisuals` 底下。
  - 場景編輯時，`position.x` / `position.z` 是平面擺放座標。
  - 場景編輯時，`position.y` 是離球面的高度偏移；通常保持 `0`，代表底部貼球。
  - 運行時由 `HubSphereController.gd` 使用 Hub 球半徑將平面座標投影到球面。
  - 投影後物件 local Y 軸需對齊球面法線，`rotation.y` 作為平面朝向並轉為球面切線方向。
- Hub 佈局目前以範本式灰模構圖為目標：
  - 中央據點主物件放在玩家前方約 `z = -18 ~ -24`。
  - 左右 landmark 分布在約 `x = -24 ~ 26`、`z = -20 ~ -22`。
  - 前景左右方塊放在約 `x = ±18 ~ ±24`、`z = 12 ~ 16`，建立前景深度。
- Hub root 與 `HubSphereController.gd` 需保留可調參數：
  - `project_scene_primitives_to_sphere`
  - `hub_placement_plane_size`
  - `show_hub_placement_plane_debug`
  - `hub_player_move_speed`
  - `hub_walk_radius`
  - `hub_sphere_radius`
  - `hub_camera_fov`
  - `hub_camera_screen_offset_y`
- 使用者已於 2026-06-02 測試確認：物件可直接移動到位置上，並可調整大小；目前版本可用。
- 使用者已於 2026-06-03 要求依範本直接調整；目前版本包含球面方格地板、前景物件、中央基座與左右 landmark。

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
