function spec = ppo_mlp()
% 前饋模型變體：繼承基準規格，將 lstmUnits 設為 0，由 builder 使用一般輸入層。
% 觀測／動作介面不變；回傳 spec，不在此建構或訓練 agent。
% Feedforward PPO: same observation/action contract, no recurrent layer.
spec = trainingmodels.load_profile('ppo_lstm128');
spec.name = 'ppo_mlp';
spec.lstmUnits = 0;
end
