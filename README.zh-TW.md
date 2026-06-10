# P4 Skills

適用於 Perforce (P4) 版本控制的 AI Agent 技能集合。

[English](README.md)

## 技能列表

### [p4-workspace-check](skills/p4-workspace-check/SKILL.md)

在執行任何需要工作區的 P4 指令前，驗證當前目錄對應的 P4 客戶端工作區是否正確。若偵測到不符，會自動將 `P4CLIENT` 修正為對應的工作區。許多其他技能都會以此作為前置步驟。

---

### [p4-duplicate-stream](skills/p4-duplicate-stream/SKILL.md)

複製一個 P4 Stream 及其所有下游子 Stream，並以新名稱建立完整的 Stream 階層。支援以字串替換方式批次重新命名，或由使用者逐一指定新名稱。只複製 Stream 設定，不複製任何檔案內容。

**適用情境：** 想要為現有 Stream 樹建立一組平行的新 Stream，例如開新版本線或建立實驗性分支。

---

### [p4-export](skills/p4-export/SKILL.md)

將指定 Perforce Changelist 中的所有檔案匯出至本機目錄，並保留 Depot 的相對資料夾結構。輸出資料夾會自動命名為 `CL<編號>`，刪除類型的檔案會略過不處理。

**適用情境：** 想要在本機保存某個 CL 的檔案快照，用於審閱、封存或分享。

---

### [p4-list-changelists](skills/p4-list-changelists/SKILL.md)

依日期區間、提交者、描述文字或 Changelist 編號範圍，列出符合條件的已提交 P4 Changelist。技能可將「昨天」、「上週」、「今天」等自然語言日期轉成腳本需要的明確篩選格式。

**適用情境：** 想要查詢或產生符合特定條件的 P4 CL 清單，例如列出某人在某段時間內提交、描述含有指定字串、或編號落在指定範圍內的 CL。

---

### [p4-merge-cl](skills/p4-merge-cl/SKILL.md)

將特定已提交的 Perforce Changelist，從來源 Stream 合併到一個或多個目標 Stream。會處理目標工作區準備、定位來源 CL、執行 `p4 merge` 或必要時退回 `p4 integrate`、安全 resolve，以及建立新的待提交 CL 來承接合併結果。

**適用情境：** 想要把某個修正或功能所對應的特定 CL，從一條 Stream 精準合併到其他版本線，包含一次處理多組來源與目標工作區的情況。

---

### [p4-move-conflict-files](skills/p4-move-conflict-files/SKILL.md)

掃描指定 Changelist 中所有未解決的衝突檔案，並將它們移至一個新建立的待提交 CL，讓衝突可以在獨立的 CL 中處理，不影響原始 CL 的其他檔案繼續推進。

**適用情境：** 某個 CL 中有部分檔案發生衝突，想要將衝突檔案獨立出來個別處理。

---

### [p4-port-cl](skills/p4-port-cl/SKILL.md)

將一個已提交的 Perforce Changelist 中的檔案層級變更，移植到一個或多個其他工作區或 Stream。會先在目標工作區中定位對應檔案，再套用相同的修改內容。

**適用情境：** 需要將同一個修正或功能同步到多個版本分支或工作區，例如跨產品版本的 hotfix 移植。

---

### [p4-stream-remap-ignore-manager](skills/p4-stream-remap-ignore-manager/SKILL.md)

專注於 Perforce Stream 的 `Remapped` 與 `Ignored` 區段進行嚴格稽核。遵循固定的互動式工作流程，匯出各 Stream 的設定後，依指定路徑產生統一的比對摘要報告，並以圖示標示符合項目。

**適用情境：** 想要跨多條 Stream 比對 Remapped／Ignored 設定，快速找出哪些 Stream 包含特定路徑的對映或忽略規則。

---

### [p4-claude-simplify](skills/p4-claude-simplify/SKILL.md)

對目前 P4 工作區中所有已開啟（opened）的檔案，同時啟動三個平行的 AI 審查 Agent，分別從程式碼重用、程式碼品質、執行效率三個面向進行審查，並自動修正發現的問題。

**適用情境：** 在提交前想要快速對所有變更做一次全面的自動化程式碼審查與優化。
