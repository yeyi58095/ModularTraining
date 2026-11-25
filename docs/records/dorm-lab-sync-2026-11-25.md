# 11/25 宿舍與實驗室資料交接

宿舍保留原始資料，另以各正式倉庫的 `origin/main` 為基準整合。實驗室端以已推到 GitHub 的版本參與比對。I: 的未提交修改與本機原始資料仍須在實驗室檢視。

| 倉庫 | 對照與取回內容 |
| --- | --- |
| ModularTraining | `Paper/Flower/Deep Reinforcement Learning/ModularTraining` 的訓練引擎、模型配方、入口、測試與架構文件可追溯至本倉庫首筆提交 `a729ca0`。舊版分析器依賴相鄰 Simulink 目錄。整合版保留可指定 run 的 CLI，修正為載入本倉庫 `tools/` 的解析器。宿舍診斷程式的對應入口與本機資料位置見[歷史診斷指南](../guides/historical-diagnostics.md)。 |
| RollOscillation | 宿舍找到的 GUIDED_1 原始飛行資料及 Simulink／ONNX 輸入，對應既有[基準紀錄](https://github.com/yeyi58095/RollOscillation/blob/4f122a5ed44c986ba992691838ec6ceb7fed9164/results/baseline.md)。程式沿用 `4f122a5ed44c986ba992691838ec6ceb7fed9164`。SAC 滾轉分析仍由 ModularTraining 維護。 |
| Meetings | 桌面研究目錄散放的 11/26 簡報與 GitHub 固定檔逐位元相同。其餘從 MyReport、Paper 及本專案的 meeting/output 找回。各版本與配套見[整合提交](https://github.com/yeyi58095/Meetings/commit/c27414eccb3077585cf94b120cbb5b043af8a9e7)。 |

宿舍原工作樹在同步前沒有已追蹤的程式異動。兩個未追蹤的離線 ZIP 和 Dally 論文的四張頁面圖及一份擷取文字留在原處。歷史資料夾中的模型、完整 run、replay、原始日誌和診斷包可在需要重算時另外移交。

## 驗證

- Python 47 項測試和 PowerShell 的 episode 格式、supervisor 路徑檢查通過。另以 60 回合獨立測資從專案外執行 PPO 分析器，對照最近 50 回合均值、worker 統計、解析器位置與輸出位置。
- 四個 Stage 6 真實種子的幾何輸出與原腳本相同。MATLAB R2024b 核對 E18400 配方、40 列 SAC 風況摘要和退步分析圖。歷史 A/B 入口已核對模型雜湊防護，本次未重跑模擬或訓練。
- RollOscillation 通過四項單元測試、四個 CLI 入口與 18 個相對連結檢查。
- Meetings 已核對 16 份 PowerPoint 的封裝及關聯、65 個簡報與場次索引的本機連結，並用 Git 儲存的實際內容驗證 10/27 USB 清單的 127 個 SHA-256。舊展示文件庫中指向完整專案或原始評估產物的參考，仍需配套的本機資料。
