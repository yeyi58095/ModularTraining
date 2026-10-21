# SAC stdout review — 2026-10-21

User supplied three root-level logs for run `20261020_201931_tpad1142e4_44c3_4019_a786_72e4faa3b614`, remote root `D:\daniel\ModularTraining`. Read-only analysis; no training, remote connection, runtime edits or checkpoint changes.

## Evidence

| File | Episodes | SHA256 |
| --- | --- | --- |
| sac_attemp1_stdout.log | 1–1000 | 34DD681E0932BCA1BB58E3992898AF2CC299DB490A74E0F2935647083FEBFC58 |
| sac_attemp2_stdout.log | 1001–2000 | 651C8BDFE115A21113C7244E03A3E672F2094AA16B1BDA59E9AAB01A432E08AE |
| sac_attemp3_stdout.log | 2001–2144 | EB619A0FFC8D33C42C86F6098D9E0E8948E9160DBC7A9DA003D6974C5BEF0002 |

Parsed all 2144 episode rows, with no missing episode IDs. All rows report Stage 1/8 straight_calm. Attempts 1 and 2 report normal stop and save; attempt 3 ends at episode 2144 without a completion footer. This does not establish current process state. Each attempt obtained six workers. Preserved crash-dump job warnings do not establish a crash in these attempts. Root reward_history.csv belongs to the older PPO run, not this SAC run.

## Results

Means below were recomputed from the printed per-episode values; full length means steps >= 3000.

| Episodes | Mean reward | Mean steps | Full length |
| --- | ---: | ---: | ---: |
| 1–100 | 99.16 | 161.42 | 0/100 |
| 1001–1100 | 2670.25 | 3000.00 | 100/100 |
| 1101–1200 | 2717.64 | 3000.00 | 100/100 |
| 1201–1300 | 2659.17 | 3000.00 | 100/100 |
| 1301–1400 | 347.44 | 475.21 | 12/100 |
| 1401–1500 | 39.84 | 76.87 | 0/100 |
| 1601–1700 | 1891.52 | 2235.17 | 70/100 |
| 1701–1800 | 2367.57 | 2606.44 | 86/100 |
| 1801–1900 | 39.56 | 76.22 | 0/100 |
| 1901–2000 | 331.20 | 404.63 | 4/100 |
| 2001–2100 | 306.23 | 441.75 | 3/100 |

Episode 1312 had 3000 steps; 1313 dropped to 139. Screenshot episode 1786 matches printed average 2735.20 and 3000 steps; episode 1787 then dropped to 670, and 1788 to 177. Both collapses occur within attempt 2, without a stage change or process boundary. They demonstrate training performance regression, not its physical or optimization cause.

Episodes 2133–2144 all reach 3000 steps. Latest printed rolling 100-episode metrics at 2144: reward 559.30, steps 702.38, full-length rate 12%. Stage minimum 2000 episodes now passes, but the other conditions do not. Earlier high performance at 1001–1300 could not pass the minimum-episode requirement. No frozen evaluation or convergence claim follows from these training logs. Footer trailing means are not substituted for recomputed 100-episode means; their aggregation was not verified.

## Speed limits and next evidence

### Uploaded diagnostic ZIP follow-up

### User-supplied utilization observations

User reports training still active while awaiting graceful attempt completion. NVIDIA telemetry from 2026-10-21 09:10:22–09:11:03 shows GTX1660 GPU utilization 0–3%, memory 884–885 MiB, power approximately 14.81–16.16 W. This is device-level telemetry, not MATLAB-specific attribution.

A subsequent 10-second process CPU sample shows PID22304 at 344.8% of one logical CPU, and PIDs16652/25144/29188/29432/36360/38460 each at 0.2%. The uploaded attempt_00003/processes.json maps 22304 to the main MATLAB process (child of launcher26044) and those six PIDs to its pool children. PID4972 is outside this recorded attempt tree and is not attributed to this run.

Within this CPU sample the main process was busy while all six workers were near idle. Combined with the separate GPU sample, this motivates profiling main-process work before increasing worker count. It does not establish the whole-attempt duty cycle, prove networks ran on CPU, or distinguish replay preparation, learning orchestration, synchronization, saving or other client work. Preserve graceful pause and perform any instrumented execution only after confirming inactivity and obtaining the applicable bounded-test authorization.

Read `sac-diagnostics-20261021-090503.zip` directly without extracting or modifying originals. It contains root metadata and three attempt folders. This supersedes the initial lack of attempt timing data below.

- All three attempt.json files specify `trainingDevice=gpu`; all pool_ready files report six actual workers. This verifies configuration, not measured GPU utilization or saved-network device state.
- control.json contains `maxAttempts=1`; status remains running attempt 3 at collection. Based on current supervisor implementation, the limit blocks the next attempt after this one exits, not the next checkpoint. No claim of completed pause.
- Attempt 1 supervisor start-to-exit: 20:19:32–21:29:58, 4226 seconds (1h10m26s), 1000 episodes and 316874 episode steps; aggregate throughput 74.98 steps/s.
- Attempt 2 supervisor start-to-exit: 21:30:41–next day 08:08:55, 38294 seconds (10h38m14s), 1000 episodes and 1501974 episode steps; aggregate throughput 39.22 steps/s.
- Thus steps increased 4.74x while total elapsed time increased 9.06x; aggregate throughput fell about 47.7%. These rates include startup, learning, saving and shutdown, not isolated simulator throughput. No measured bottleneck attribution is possible yet.
- Pool construction itself took 27.45, 28.82 and 28.51 seconds. Attempt 2/3 pool-start timestamps occur roughly six minutes after supervisor start, indicating pre-pool overhead requiring further profiling; checkpoint loading is only a hypothesis.
- Latest stdout is episode 2150, still Stage1. Episodes 2133–2150 all ran 3000 steps. Latest rolling 100: reward 694.60, steps 844.73, full-length rate 18%. Attempt 3 lacks result.json; first two have normal-exit results, all three stderr files are empty.
- Remote model.json matches the examined SAC candidate options (LSTM128, batch64, sequence32, replay100000, learningFrequency32). No optimizer/loss/entropy trajectories or GPU telemetry are included.

Supervisor log has a literal Z suffix whereas status.json carries +08:00; elapsed intervals above use differences within the same supervisor clock, not a timezone conversion. Collection timestamps are not episode completion timestamps. Keep the requested graceful pause; do not estimate completion time from episode count alone.

Follow-up: user supplied root `status.json`. It reports `state=running`, `attempt=3`, updated `2026-10-21T08:09:26.1288186+08:00`, with message starting attempt 3 using 1..6 workers and resuming this run's Agent_Final.mat. This is a supervisor start-event timestamp, not an episode timestamp or proof of current liveness; it cannot establish the duration of 144 episodes in the copied log. User requests copy-paste commands for future data collection.

Logs contain no wall-clock timestamps or elapsed durations, no measured GPU utilization, and no learner/simulation/save timing breakdown. Copied file mtimes and run-name timestamps cannot determine training duration. Six workers were acquired, but speedup and the actual training device are unverified.

Full episodes require 3000 steps versus 161.42 mean steps in episodes 1–100, an 18.59-fold increase in environment steps per episode; this is not an 18.59-fold measured wall-time increase. Local source uses recurrent SAC with twin critics and preserves replay/optimizer/target data; these are possible computational/storage costs, not measured bottlenecks or verified remote snapshot settings.

Prioritize existing run training_status.json, control/config snapshots, attempt timing metadata and pool_ready.json before proposing performance changes. Diagnose learning regression with frozen evaluations and available entropy/loss/action/trace evidence. Do not alter active run snapshots, relax gates or automatically launch more training.
