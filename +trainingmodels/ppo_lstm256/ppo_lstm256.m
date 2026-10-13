function spec = ppo_lstm256()
% 模型變體：繼承 ppo_lstm128 規格，只改名稱與 LSTM 單元數為 256。
% 回傳 spec；其餘超參數沿用基準，不在此建構或訓練 agent。
spec = trainingmodels.load_profile('ppo_lstm128');
spec.name = 'ppo_lstm256';
spec.lstmUnits = 256;
end
