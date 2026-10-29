# SAC 飛控文獻初篩與本專案判讀（2026-10-28）

本次依 current-status 及 10/26 actor final、10/27 MLP shared-input/action-value、10/28 critic frozen 紀錄判讀；沒有重跑模型或核對其他聊天室。文獻為出版者／作者機構／arXiv 摘要與書目初篩，未逐篇完成全文方法及超參數稽核。

## 實驗結論

- 已有可用的 Stage1 凍結策略，但持續更新後反覆退步。recurrent 100k1600 在既有固定無風路線的關探索評估跑滿3000步，後10秒原路線最大偏差0.984m；MLP來源2100為3000步、3.4881m。跨架構數字不是等預算排名。
- MLP慢critic2200為3000步、6.1824m；2500只163步、50.3589m。初始119次跑滿比低actor組82次更久，仍未穩定保留能力，且互動步數不同。
- 關探索仍失敗，排除「只有抽樣探索噪音」的解釋。MLP也退步，不能把問題完全歸因LSTM。擴buffer及降LR都未建立穩定解法，不等於這些因素完全無關。
- 同輸入actor分布及Q動作偏好改變，支持策略／價值學習動態值得追查；未校準回報及TD誤差，不能確診Q高估、entropy或optimizer問題。
- 建議以等互動步數、獨立訓練seed、固定checkpoint凍結評估檢驗「學到後保留能力」；測試seed不等於訓練seed。保留既有門檻與paused。未新增訓練授權或配方。

## 優先文獻

1. Dally & van Kampen (2022), *Soft Actor-Critic Deep Reinforcement Learning for Fault Tolerant Flight Control*, AIAA SciTech, DOI 10.2514/6.2022-2078. 噴射機耦合飛控、串級SAC與故障／擾動評估。適合作為飛控架構及驗證基準，不是本專案循跡配方已驗證可移植。
   - https://arxiv.org/abs/2202.09262
2. Seres, Liu & van Kampen (2023), *Risk-sensitive Distributional Reinforcement Learning for Flight Control*, IFAC-PapersOnLine 56(2), 2013–2018, DOI 10.1016/j.ifacol.2023.10.1097. 比較DSAC與SAC，報告distributional critics改善learning consistency。與目前學習不穩問題相關，但不能由摘要推定DSAC能解決本專案退步。
   - https://repository.tudelft.nl/record/uuid%3A15883e3a-79ff-42ac-9152-bcaa390f2dcf
3. Teirlinck & van Kampen (2024), *Hybrid Soft Actor-Critic and Incremental Dual Heuristic Programming Reinforcement Learning for Fault-Tolerant Flight Control*, AIAA SciTech, DOI 10.2514/6.2024-2406. Cessna Citation II六自由度模型、串級高度控制內迴路，SAC與IDHP混合。
   - https://repository.tudelft.nl/record/uuid%3A02616c7b-ffaa-45f1-9b32-875a6a9e3061
   - 作者程式：https://github.com/CasperTeirlinck/RLFC-SACIDHP
4. Jansen & van Kampen (2025), *Longitudinal Handling Qualities Evaluation for Soft Actor-Critic Deep Reinforcement Learning Flight Control*, AIAA SciTech, DOI 10.2514/6.2025-2794. 俯仰角速度命令追蹤，以縱向操縱品質及偏離標稱條件評估；可參考其reward以外的驗收方式。
   - https://repository.tudelft.nl/record/uuid%3A5078b54b-5ea7-4ec4-afce-0e8964361fb8
5. *UAV Navigation using Reinforcement Learning: a Systematic Approach to Progressive Reward Function Design* (2026), Journal of Intelligent & Robotic Systems, DOI 10.1007/s10846-026-02408-7. 在固定翼運動學模擬器比較PPO/SAC/TD3及reward分解，使用路徑偏差與控制振盪指標；和本案循跡問題接近，但不等於完整動力學飛控驗證，也不證明本案reward有錯。
   - https://link.springer.com/article/10.1007/s10846-026-02408-7

建議先讀1建立SAC飛控基準、2研究學習一致性、5對照循跡任務定義。這是閱讀優先序，並非立即換演算法或改reward的決策。
