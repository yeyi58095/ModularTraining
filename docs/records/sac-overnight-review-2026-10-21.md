# SAC 1000-episode review and overnight continuation

User supplied stdout_new.log (SHA256 49ABBBC5A6B52ED01345228F2908BD785AF509D94E075408E5E1303195CF4B46), containing exactly 500 unique episode rows501–1000 of run20261021_200746_tpecf075ee_586a_4d3b_b636_4c63d8cea43b. User separately supplied supervisor paused at2026-10-21T22:44:18+08:00 after normal save. No remote process was independently inspected.

| Episodes | Mean reward | Mean steps | Full3000-step episodes |
| --- | ---: | ---: | ---: |
| 501–600 | 91.05 | 146.39 | 0/100 |
| 601–700 | 96.25 | 155.73 | 0/100 |
| 701–800 | 103.67 | 170.11 | 0/100 |
| 801–900 | 158.98 | 251.29 | 0/100 |
| 901–1000 | 1544.85 | 1878.95 | 51/100 |

Episodes956–1000 form45 consecutive full-length episodes. Total steps in this attempt260247; previous500 episodes74160, cumulative334407. Trailing mean2558.0822 is now explained: trainingcurriculum.outcome uses the last50 stage rewards; recomputed rounded stdout last50 mean2558.082 matches. The displayed1544.85 is the configured100-episode average. These are different windows, not contradictory scores.

No evidence justifies changing LR, reward, termination or course gates tonight. Stage1 still requires minimum2000 episodes and three100-episode condition windows. No convergence or frozen-evaluation success inferred. Monitor for another sustained collapse after high performance, given the older run's history.

## Execution finding

500 warnings say Fast Restart cannot be enabled. All500 episodes also report inability to save an operating point for FAFA_Simulation/OBSERVATION/MATLAB Function3 due to unbounded variable-size signals [Infx3]. The option was requested on but was not successfully usable. This can explain verbose logs and motivates inspecting initialization/compilation cost; no wall-time decomposition establishes its share of runtime.

Expose fastRestart as a validated retry/control/attempt option (legacy default on), explicitly set off for this overnight continuation. Do not edit SLX or bound signals during overnight setup. Turning it off avoids repeatedly requesting an unsupported operating-point mode; it does not promise faster compilation or remove all initialization overhead.

## Authorized overnight semantics

User explicitly requested repeated overnight training. Use retry on the same saved agent with maxAttempts=0, keeping500 episodes/attempt,100 checkpoints,serial CPU. This removes the supervisor's per-launch attempt count cap only. Stage budgets, guard decisions, watchdog/no-progress limits, final success and STOP still stop/pause as before. No continuous_training snapshot changes, parent-run cloning, replay reset, automatic LR tuning or rollback. Remote commands remain user executed.

Preferred monitoring recorded in AGENTS.md: MATLAB training_status(sacDir,50); PowerShell tools/plot_training_rewards.py for the exact same SAC receipt, --watch6 --view. Old progressive_v2 selection and root-level plot path are inappropriate for this SAC run.

## Local verification

`test_sac_flight('', 'serial','off')` exited0: two actual CPU spatial_v2 episodes, normal save/restore across two attempts, actor/replay continuity and five-step frozen evaluation. Both attempt payloads contain fastRestart=off and both stdout files have zero Fast Restart cannot-be-enabled warnings. Test run20261021_231255_tp04eab73e_b8b3_46f8_a01f_0d017b07489d; logs remain ignored. Nonfatal variant-search/modified-model-close warnings remain; no production SLX edits. This is not an overnight duration or convergence benchmark.

PowerShell supervisor and all three PowerShell guide blocks pass AST parsing. No remote command was executed by the assistant.

`test_sac_serial_recipe` exited0: serial CPU500 defaults, fastRestart validation, maxAttempts=0 preparation without launching, and immutable execution-mode checks passed.
