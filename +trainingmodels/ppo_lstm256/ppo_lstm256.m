function spec = ppo_lstm256()
spec = trainingmodels.load_profile('ppo_lstm128');
spec.name = 'ppo_lstm256';
spec.lstmUnits = 256;
end
