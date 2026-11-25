# Stage 6 offline review — 2026-10-13

No training, simulation, runtime edits, checkpoint changes, or Git operations were performed. Existing working-tree edits were left intact. MATLAB only loaded supplied MAT traces and exported numeric arrays.

## Integrity and environment

- Main ZIP SHA256: cbed0437d94e4c295cf829bd29a08cb57a32310eb5f18d81ded2759663d84e83; all 380 manifest files verified.
- Extra ZIP SHA256: 878dbc48ebdb6d5caceee3e6efda4976cf44562688b0ff354e0d79c672231025; matches user value. Both ZIP CRC checks passed.
- All evaluation reports and local runtime SLX SHA256 agree: b28c5a5c967347c498cb23f032b483841ca63b98ab4da137ca902e193225714c.

## Performance

Checkpoints 22400/25800/31600 each complete 10/10 mild-wind cases and 6/10 full-wind cases (seeds201:210). Full-wind mean rewards: 2267.00 / 2256.62 / 2262.88. Failures recur at202/204/205/207. Detailed reruns use deliberately selected failures plus201/210 controls: their 2/6 completion fraction is not a new generalization estimate.

All 9 retention tests (three checkpoints x stages1:3, seed101) reach3000 steps. Completion retained in these cases does not imply unchanged precision: fixed-turn observation7 RMS increases from0.13466 at22400 to0.20685 at31600.

Actor relative L2 difference vs22400 is0.12173 at25800 and0.21976 at31600; critic0.28454 and0.52032. Parameters finite; reported rates remain actor2.5e-5/critic1e-4. Thus weights are not frozen, but parameter movement does not establish beneficial learning. Audit initial_snapshot_count=0: no matched initial/resume pairs verified by that audit. Package contains r000002 initial; do not claim initialization equivalence from this report.

## Confirmed distance-reference defect

Actual runtime guidance chart167 allocates global_path=zeros(500000,3), appends each changed planned_path, but sets path_CTE=global_path without limiting to path_length. Outside the bounding box it selects the nearest historical waypoint and uses current_index+1 as segment end unless at the end of the allocated array. At the final filled waypoint the next entry is an unused zero, creating a fictitious segment toward(0,0).

Reconstructing concatenated logged planned_path snapshots plus the unused zero reproduces terminal guidance_d to six decimal places for all12 failure traces. In all9 cases involving202/204/205, the selected nearest index equals the filled history length and its next point is the zero padding. In207 the selected index is within filled history; it is a different failure mechanism.

For31600:

| seed | terminal time s | logged d m | lateral to terminal tangent m | nearest index / filled length |
|---|---:|---:|---:|---|
|202|259.6|50.424913|7.017|3936/3936|
|204|99.8|50.895169|1.549|1544/1544|
|205|69.5|50.180986|2.891|1095/1095|
|207|73.0|50.352440|46.875|1215/1244|

The lateral column is distance to an extended terminal line, not to the finite planned path or future desired trajectory. Finite-path terminal distances for202/204/205 are84.2/82.4/56.3m. Do not assert physically perfect tracking or that correcting d alone yields valid mission completion. The vehicle has passed the available path; path availability and reference consistency remain important.

In202/204/205 target remains about50m ahead while reported d changes at bounding-box transitions. At20568.1->68.2s, d jumps3.6->28.3m but terminal lateral remains about3.5m; at69.5 d reaches50.18. This is a confirmed reference defect, not evidence that PPO learning rate is the cause.

## Seed207 remains a separate geometric/control problem

At69.8s target forward projection49.9m and d48.1 (old-history defect already present). At69.9s planner updates, target projection28.7m and heading error59.4deg. By72.0 heading error84.3deg, real finite-path distance40.6m;72.1 outside branch changes target behind vehicle (projection-23.6m). At73.0 independent finite-polyline distance50.35m agrees with logged d. V2 outside terminal-overshoot rule does not cover this pre-terminal lateral departure.

## Next step

Keep run paused. Develop isolated evaluation candidates for bounded valid-history CTE indexing and planner/target continuity; preserve failure threshold and evaluate physical geometry rather than merely suppressing termination. Compare on supplied checkpoints and paired scenarios before any runtime deployment or further training. Existing data is sufficient to begin this work; no additional lab data requested now. Full curriculum is not qualified.
