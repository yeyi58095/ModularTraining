# SAC frozen checkpoint review — 2026-10-22

## Received evidence

User placed no-exploration.json and with-exploration.json in the project root at12:44. Archived unchanged into artifacts/incoming/sac-review-2000-20261022, with intake-manifest.json recording absolute source/destination, byte size and SHA256. Both moved-file hashes were verified; reports retain their remote outputDir and trace references. Referenced MAT traces and checkpoint weights were not supplied or independently inspected.

- no-exploration.json SHA256: 257569289F6D9B50B83BB6595D2AA67961EB50399F562D6F15A96F0AE4BD8B43
- with-exploration.json SHA256: B38F3048ADFF625683D60290149FD4FEB0BFD040A69686CD3DF263669C7DF23E

Both report status/phase complete, weights_unchanged=true, MATLAB2024b CPU, spatial_v2, Stage1 straight_calm, seeds101/102/103, max3000 steps, exploration_std_scale1. Each has12 results. Model, curriculum, runtime and all four corresponding checkpoint hashes agree across reports. These are evaluator-reported integrity checks, not a local re-evaluation.

| Checkpoint | No exploration steps (all3) | Exploration steps (101/102/103) | No exploration reward | No exploration route max after10s |
| --- | ---: | --- | ---: | ---: |
| 1100 | 3000 | 3000/3000/3000 | 2853.53 | 2.63m |
| 1300 | 3000 | 3000/3000/3000 | 2442.71 | 26.08m |
| 1500 | 95 | 96/96/95 | 57.03 | unavailable: ends before10s |
| 2000 | 142 | 144/145/144 | 94.06 | 50.65m |

Exploration route maxima after10s:1100=3.84–4.92m;1300=28.38–31.50m;2000=50.11–50.76m. Initial position contributes50m to all-sample distance: do not confuse that with late deviation. All1500/2000 trials end with environment_done and distance_threshold evidence. This is terminal observation evidence, not instrumented proof of an internal IsDone branch or physical cause. Action saturation fraction is zero for all failing trials; gross action clipping is not supported by these summaries.

## Interpretation

1500 and2000 fail even with exploration disabled. Thus stochastic exploration alone cannot explain the regression. 1100 is the strongest of these four on this fixed calm straight route. 1300 already loses tracking accuracy despite reaching the step limit; full episode length is not route completion or sufficient quality assurance. The latest checkpoint2000 is not recovered on this frozen evaluation, despite high rewards near1905 in the earlier training CSV. The supplied CSV ended1905, so deterioration during1906–2000 remains possible; do not label this an evaluator bug or checkpoint corruption without the missing history/traces.

The three no-exploration seeds yield identical metrics under each checkpoint, consistent with this fixed calm deterministic scenario. They are not three independent routes or evidence of broad robustness. Reports do not contain alpha/loss histories or replay contents, so buffer replacement, critic error and update balance remain hypotheses. No learning-rate, replay, entropy or update-frequency root cause is established.

Next decision: retain original run paused and preserve all checkpoints. Use1100 as a reference, not automatic rollback. Before controlled child-run changes, inspect the final1906–2000 training log and available learning diagnostics; compare continuation candidates with equal environment steps and the same frozen checks. No runtime/model changes, training start/stop or remote access were performed in this intake review.

## Final attempt log received at12:59

Root sac-attempt4-tail.txt archived unchanged alongside the two JSON reports; SHA256381817D56F728088851328209749FCCCC74CABA6F9A3CE6480CE11715841B41F, verified after move; separate attempt4-intake-manifest.json. Parsed500 unique episode rows1501–2000; repeated tail rows deduplicated with equality checks. Attempt4 steps628069, giving32.65 steps/s over reported19237.1s (includes startup/save).

The missing interval resolves the apparent contradiction: ep1991 reward2680.11/3000steps,1992=2465.05/3000,1993=2440.11/3000,1994=1185.73/3000,1995=285.22/667,1996=125.42/228,1997=121.98/226,1998=157.56/259,1999=135.97/241,2000=171.12/292. All remain Stage1. Thus another collapse occurred before the final save, within attempt4, not solely on evaluator load or process restart. The final100-episode mean2622.19 and94% full-length rate conceal the last6-episode mean166.21; these are historical-window statistics, not performance of frozen Agent2000. Training stops normally with success0; no stage pass inferred.

This supports preserving1100 as the reference and keeping2000 paused. It does not identify buffer/LR/critic/entropy as a cause. A future controlled comparison should fork the same1100 checkpoint into baseline and a single-change candidate (e.g. replay capacity500000), preserving lineage and evaluating on equal step budgets; enlarging capacity cannot reconstruct old overwritten experiences. No such branches or training were created here.
