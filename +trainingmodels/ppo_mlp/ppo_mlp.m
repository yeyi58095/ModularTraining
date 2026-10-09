function spec = ppo_mlp()
% Feedforward PPO: same observation/action contract, no recurrent layer.
spec = trainingmodels.load_profile('ppo_lstm128');
spec.name = 'ppo_mlp';
spec.lstmUnits = 0;
end
