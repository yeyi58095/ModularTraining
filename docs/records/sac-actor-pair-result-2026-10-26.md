# SAC actor-rate pair: both branches through2100

## Intake and identity

Archived root2351stdout.log, sac-actor-pair-latest.json and sac-replay-pair-latest.json under artifacts/incoming/sac-actor-control-2100-20261026. Original/destination paths and SHA manifest recorded before moves; verified after. Pair receipt identifies same baseline1600 parent SHA00dc22b89426dc88a169de5fc5d0a18ae5287e92a686778f4ec4804b4c44c53b. Control20261025_235136_recovery_tpb9f03642 at5e-5; candidate20261025_235817_recovery_tpd681ba86 at1e-5. Receipt's prepared_only is preparation-time metadata, not current run status.

Control log has500 unique consecutive episodes1601–2100,520648 new interactions, ending cumulative1905477 (parent1384829). Normal save2100, suspected_regression pause, no rollback, success0. Stage1 throughout. Final model-close warning follows save; no proof of corrupt checkpoint. Current remote state and MAT readability require the next command's checks. Candidate comparison uses previously archived2358stdout.

| Window | Control reward / full episodes | Candidate reward / full episodes |
| --- | --- | --- |
| 1601–1700 | 2673.36 /100 | 2642.04 /100 |
| 1701–1800 | 1362.98 /51 | 1300.96 /45 |
| 1801–1900 | 121.12 /0 | 152.42 /0 |
| 1901–2000 | 87.18 /0 | 133.44 /0 |
| 2001–2100 | 73.97 /0 | 1081.40 /34 |

Control mean steps by window:3000,1753.27,191.67,140.89,120.65. First short episode1733 versus candidate1723; the lower LR did not delay this particular first-short marker. Last control full episode1754; candidate last32 episodes2069–2100 all full. Candidate's646929 interactions exceed control by126281 (about24.25%), so equal500 episodes are not equal interaction/update budgets. No paired random-stream guarantee or multi-seed training replication. No measured elapsed times in these submitted files.

## Decision

Both branches regress despite different actor rates. Candidate's late recovery is encouraging but does not establish a stable improvement or curriculum root cause; first-short onset is not itself a causal effect estimate. Do not lower actor LR again, disable guard, promote stages artificially, or resume either paused child now.

Next user-executed action: frozen evaluation of Agent2100 from each branch on Stage1, seeds101/102/103, exploration off/on at unchanged scale1, max3000 steps (12 simulations total). Compare independent finite-route deviation after10s and survival, not only total reward. Existing good parent1600 frozen results are already available; do not repeat them. Endpoint-only evaluation cannot characterize stability of intermediate checkpoints or generalization. Confirm final policy recovery before selecting any next recovery parent.

Along with four evaluation JSONs, copy each branch's status, recovery, model, control, curriculum, guard/state JSON and worker_attempts.csv if present, plus the actor pair receipt. User returns one ZIP to project root. This is a stopped-run evidence export, not a complete resumable backup. No code changes or remote training launched in this review.
