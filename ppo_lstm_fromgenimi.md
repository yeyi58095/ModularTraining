# PPO + LSTM 學習率分析與訓練優化指南

本文件匯整了 PPO（Proximal Policy Optimization）結合 LSTM（Long Short-Term Memory）時，學習率（Learning Rate, $lr$）對系統訓練穩定度與收斂性的影響，並針對實際訓練獎勵曲線（Training Reward History）進行診斷與提出相應的優化策略。

---

## 一、 Learning Rate 在 PPO + LSTM 系統中的影響

相較於標準的 MLP（多層感知器）策略網路，LSTM 引入了時間維度與 BPTT（Backpropagation Through Time），使得整個系統對 Learning Rate 的敏感度大幅提升。

### 1. 學習率過大（$lr > 10^{-3}$）
* **隱狀態表徵漂移與策略崩潰（Representational Drift & Policy Collapse）：**
  LSTM 的隱狀態（$h_t, c_t$）高度依賴歷史軌跡累積時間特徵。當 $lr$ 過大時，LSTM 權重矩陣（如 $W_{hh}, W_{ih}$）劇烈變動，導致上一代策略產生的隱狀態在經過更新後無法被當前網路正確認識。表現為訓練過程中 **Reward 驟降且無法恢復**。
* **BPTT 梯度爆炸風險：**
  沿時間展開（Unroll Steps）進行反向傳播時，梯度容易呈指數級累積。過大的 $lr$ 極易引發梯度爆炸，導致權重出現 `NaN` 或 `Inf`。
* **破壞 PPO 信任區域（Trust Region）假設：**
  PPO 透過 Clipped Objective 限制動作概率比率 $r_t(\theta) = \frac{\pi_\theta(a_t|s_t)}{\pi_{\theta_{old}}(a_t|s_t)}$ 在 $[1-\epsilon, 1+\epsilon]$ 區間。但若 $lr$ 過大，參數空間的步長過大，背後的隱特徵表達會發生過度跳躍，使「近優化（Proximal）」假設失效。

### 2. 學習率過小（$lr < 10^{-5}$）
* **門控機制無法學習長程依賴（Long-Term Dependencies）：**
  LSTM 的 Forget Gate 與 Input Gate 需要足夠的梯度信號來學會何時保留或遺忘資訊。$lr$ 過低會使網路傾向於尋求局部解（如無視歷史，退化為僅依賴單步 Observation 的策略）。
* **收斂過慢與 Epoch 更新不足：**
  PPO 在同一個 Rollout Batch 上進行多個 Optimization Epochs 時，過低的 $lr$ 會使 Policy 與 Value Function 的更新量極小，顯著拉長訓練時間。

### 3. 與系統其他組件的交互作用
* **Backbone 設計（Shared vs. Separate）：**
  * **共享 Backbone：** Value Loss（MSE）產生的梯度常大於 Policy Loss。若 $lr$ 偏高，Value Loss 會主導 LSTM 的更新，破壞策略網路所需的時序特徵。
  * **獨立 Backbone：** Actor 與 Critic 各自擁有獨立 LSTM，Critic 可以設定略高於 Actor 的學習率（例如 $lr_{critic} = 5 \times 10^{-4}$, $lr_{actor} = 1 \times 10^{-4}$）。
* **Advantage 估計不穩定：**
  若 Critic 的 $lr$ 過高，估計出的 $V(s_t)$ 會劇烈震盪，導致 GAE（Generalized Advantage Estimation）的 $\hat{A}_t$ 雜訊過大，干擾 Actor 的梯度方向。

---

## 二、 訓練獎勵曲線（Reward History）診斷

根據實際觀察到的 Episode 1 – 3,920 獎勵曲線，系統呈現非常典型的 **「前期探索瓶頸 $\rightarrow$ 突然爆發 $\rightarrow$ 頂峰回落與高方差震盪」** 過程：

```
Reward
 ^
2500 |                                    /^\
2000 |                                   /   \  /\  <- 衝高後回落與劇烈震盪
1500 |                                  /     \/  \
1000 |                                 /
 500 |                                /
   0 |-------------------------------/              <- 長期平台期 (0~3200 eps)
     +------------------------------------------> Episode
     0     500   1000  1500  2000  2500  3000  3500
```

1. **漫長平台期（Episode 0 – 3,200）：**
   * 平均 Reward 長期卡在 100–200 低位。
   * 原因：LSTM 需長時間累積軌跡以學會時序特徵提取，且初期探索力度（如 Entropy）或 $lr$ 相對保守。
2. **突破與快速收斂（Episode 3,200 – 3,550）：**
   * Episode 3,200 附近找到有效策略（Breakthrough），Reward 迅速衝高至 2,000+。
3. **頂峰回落與高方差震盪（Episode 3,550 – 3,920）：**
   * 觸頂後跌至 1,400 附近，隨後在 1,750 震盪，且單集獎勵方差極大。
   * 原因：固定 $lr$ 導致在高分區的更新步長過大，破壞了 LSTM 剛建立好的隱狀態表徵；同時伴隨策略熵崩潰（Entropy Collapse）與 Value Net 估計落後。

---

## 三、 動態學習率（Learning Rate Scheduling）策略

為了避免後期衝高後崩潰，動態調整學習率是 PPO + LSTM 的最佳實踐：

1. **線性遞減（Linear Decay）— 推薦**
   * **機制：** 學習率隨訓練進度從初始值（如 $3 \times 10^{-4}$）線性下降至極小值（如 $1 \times 10^{-5}$ 或 $0$）。
   * **作用：** 前期用大 $lr$ 快速突破平台期，後期用小 $lr$ 精細微調，防止大步長更新破壞隱狀態表徵。
2. **基於 KL 散度的自適應調整（KL-based Adaptive LR）**
   * **機制：** 監控新舊策略間的 KL 散度（$D_{KL}$）。若 $D_{KL} > d_{target} \times 1.5$ 則調小 $lr$；若 $D_{KL} < d_{target} / 1.5$ 則調大 $lr$。
   * **作用：** 確保每輪更新幅度受控，防止單次梯度過大導致策略毀壞。
3. **預熱與遞減（Warmup + Decay）**
   * **機制：** 前 5%–10% 步數內將 $lr$ 從極小值線性升至主學習率，隨後再線性遞減。
   * **作用：** 防止初期 LSTM 隱狀態充滿雜訊時產生巨大梯度打壞網路。

---

## 四、 具體優化建議清單

| 項目 | 建議設定 | 預期效果 |
| :--- | :--- | :--- |
| **LR 排程** | Linear Decay（例如 $3 \times 10^{-4} \rightarrow 1 \times 10^{-5}$） | 保持前期突破力，並穩定高分區的學習結果 |
| **Gradient Clipping** | `max_grad_norm = 0.1 ~ 0.3` | 截斷 BPTT 劇烈梯度，保護 LSTM 隱狀態權重 |
| **Entropy Coefficient** | 保持 `ent_coef = 0.01` 左右 | 防止策略過早收斂至確定性行為而失去適應力 |
| **Value Loss Weight** | 若共享 Backbone 建議設為 `0.25 ~ 0.5` | 避免 Value Function 梯度主導 LSTM 特徵抽取 |
| **Sequence Chunking** | $T = 16 \sim 64$ | 設定適當的反向傳播時間展開步長 |
