# Shared-input MLP result

Received tp57ffdaef_9bcd_4ff3_928c_a8bbdc72a4f5.zip SHA B0C489C8C1BAEF2DCC116E3C67C996FFBD153B4A68F9BF6B998C033AF9BA2C23, archived with verified move manifest under artifacts/incoming/sac-mlp-shared-20261027. All three hashes match prior diagnostics; source_unchanged and six weights_unchanged flags true. Shared prefixes:256 steps from a complete3000-step episode in2100 replay and132 steps from a complete132-step episode in2500 replay. Summaries below use observations after first64.

| Model | Good-prefix abs Gaussian mean / std | Q on recorded good actions | Poor-prefix Q on recorded actions |
|---|---|---|---|
|2100|0.5562 /0.3648|43.950 /44.008|20.769 /20.824|
|2200|2.9465 /0.1355|44.666 /44.624|26.125 /26.005|
|2500|2.9085 /0.2624|44.944 /44.976|22.106 /22.126|

Policy outputs clearly differ on identical input. Gaussian mean is pre-action-transform, not a physical action or actuator angle. Good-input twinQ disagreement remains small(.0666/.0438/.0447), which does not prove accurate Q. Recorded-action values say nothing direct about values assigned to the changed actor's preferred action. No calibrated return or TD target is present, so do not claim overestimation or critic root cause. Do not directly infer benefit from entropy/critic LR changes.

Next bounded check: probe_sac_action_values selects16 evenly spaced observations after index64 from the same first prefix;33 normalized candidate actions from-1 to1; three models, two critics. Stores full action curves, recorded actions and actor Gaussian mean/std. No train/sim, one run exclusive lock,paused/hash/weight checks. Source inputs must correspond to first selected checkpoint. Local single-checkpoint MLP fixture passed exit0,16x33 action evaluations per critic; remote results not yet executed. Shared-inputs remains-v7 and source models remain unchanged. It is an off-policy diagnostic, not proof of actual long-horizon action quality. Keep training paused; no additional training recipe this turn.
