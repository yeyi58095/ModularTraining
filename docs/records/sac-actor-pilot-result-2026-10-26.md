# SAC actor LR candidate through2100

Received2358stdout.log and training_status paste. Archived under artifacts/incoming/sac-actor-pilot-2100-20261026; original log path, destination and SHA recorded before move and verified after. Attachment copied as training-status.txt. User-reported run20261025_235817_recovery_tpd681ba86, attempt1, paused2026-10-26T05:35:09+08:00, suspected_regression, saved through2100 with no rollback. Normal training stop and save are logged; model-close warning follows successful save and does not itself establish a corrupt MAT. Remote MAT readability has not been independently tested.

500 unique consecutive episodes1601–2100;646929 new interactions. Prior cumulative1384829 plus646929 equals final2031758. Stage1 throughout. No measured duration provided; run folder timestamp is not reliable attempt-start timing. Configured candidate LR1e-5 is based on prepared recipe; this stdout alone is not a direct audit of optimizer LR.

| Episodes | Reward mean | Steps mean | Full/100 |
| --- | ---: | ---: | ---: |
| 1601–1700 | 2642.04 | 3000.00 | 100 |
| 1701–1800 | 1300.96 | 1740.16 | 45 |
| 1801–1900 | 152.42 | 230.12 | 0 |
| 1901–2000 | 133.44 | 205.53 | 0 |
| 2001–2100 | 1081.40 | 1293.48 | 34 |

First short episode1723, so initial122 all full. Last short2068;2069–2100 all32 full, mean reward2631.10. Last50 mean1983.851 matches footer1983.8508 within rounded-log precision. Last100 mean1081.40 includes earlier failure and is not the frozen final policy's score. Latest checkpoint quality requires a later frozen evaluation.

Actor-rate reduction has not eliminated regression in this pilot. It is not yet possible to infer superiority/inferiority to unchanged LR, because the prepared same-parent control has not been reported run. Preserve candidate pause/guard and original reference1600. Next user action: run the already prepared control child only, maxAttempts1 and existing500 added episode budget, serialCPU/fastRestart off. Do not recreate pair or resume candidate. Require receipt parent SHA and original-parent checkpoint hash, both child statuses paused, control attempt0, and model LR5e-5 before launch. No automated remote launch by assistant.

After control finishes, compare curves, interaction count and both saved checkpoint policies. Equal episode caps do not mean equal update/interaction budgets; one continuation each does not establish statistical superiority. Keep original curriculum gates and guard intact.
