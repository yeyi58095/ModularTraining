# SAC stored-state review

Received tp1dbfe526_bddb_4482_8ea1_d042f6bf9421.zip. Six expected JSON entries inspected before extraction. Archived under artifacts/incoming/sac-state-review-20261025 with original path/destination/SHA manifest and post-move hash verification; report-hashes.json covers extracted reports. All five diagnostic reports complete, source_unchanged and policy_state_saved true. Four child MAT hashes match previous frozen evaluations; parent hash matches pair receipt. No training performed.

| Snapshot | Alpha | Frozen outcome | Latest10000 transition mean reward | Terminal markers |
| --- | ---: | --- | ---: | ---: |
| Parent1100 | 0.01679255 | 3000 steps | 0.842956 | 4 |
| 100k1400 | 0.00530855 | 85–88 steps | 0.695382 | 46 |
| 100k1600 | 0.00967182 | 3000 steps | 0.920945 | 4 |
| 500k1400 | 0.00375953 | 3000 steps | 0.944244 | 4 |
| 500k1600 | 0.00422215 | 195–219 steps | 0.581824 | 90 |

Options agree: gamma0.98, batch64, sequence32, LearningFrequency32, actor LR5e-5, twin critic LR1e-4, entropy LR1e-4, target entropy-1. Both replay capacities are full and match intended100k/500k. Actor/critic/entropy optimizer state fields present; presence alone does not establish optimizer history or correctness.

No nonfinite parameters in actor, critics or target critics, no nonfinite recent rewards. This excludes observed NaN/Inf corruption in inspected fields, not finite-valued critic error. Alpha differs from initialization and policy state is saved; no evidence here of reset to initial0.1. Lower alpha is not uniformly associated with failure:500k1400 succeeds with lower alpha than failing500k1600. Alpha is a regularization coefficient, not direct measurement of action standard deviation.

Twin critic-target L2 gaps: parent0.2427/0.1961;100k1400 0.4178/0.5680;100k1600 0.3574/0.3034;500k1400 0.1104/0.1251;500k1600 0.4119/0.4201. The increased candidate gap accompanies failure but is not a calibrated Q-error or causal threshold. Network norms are parameter magnitudes, not Q predictions. Do not label this critic divergence based on norms alone.

Recent terminal markers align with poor survival. They are not unique failed-episode counts or failure rates: a10000-step window cuts episodes, and markers may include horizon termination. Only recent data inspected, not full-buffer composition. Larger replay does not remove finite-policy degradation in this pilot; neither a buffer-capacity cure nor entropy-only fix is established.

Decision: preserve100k1600 and500k1400 as good reference checkpoints; keep runs paused. Do not reset alpha or change curriculum gates based on this table. Further mechanistic diagnosis needs actor distribution and twin-Q/TD behavior on the same recurrent sequences with explicit state warm-up and termination handling; these cannot be recovered from parameter norms. A training experiment should change one factor in a new child and retain a matched control, rather than changing curriculum, LR and entropy together. No validated new training recipe is claimed by this review.
