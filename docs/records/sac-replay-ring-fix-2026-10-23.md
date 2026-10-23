# SAC full replay ring validation fix

## Report and reproduction

User's remote preparation on2026-10-22 created baseline child20261022_132700_recovery_tp4c73786a, then failed while growing replay with SAC:Replay / Replay data changed. No pair receipt or candidate completion was reported. User explicitly paused work and resumed on2026-10-23. Keep the existing baseline and parent unchanged; prepare a new pair after updating rather than modifying partially completed artifacts.

Inspected local R2024b InMemoryReplay: allExperiences_ returns physical Memory_ slots when full; resize_ obtains getLastNData_ chronologically, resets storage and appends records/tracker IDs. Thus slot order rotates after expansion of an already wrapped ring. Previous tests covered only short, not-yet-wrapped buffers and failed to exercise this boundary.

New regression test using capacity128 reproduces the exact old assertion:32 and128 appended records pass;173 records fail. The original implementation was tested before modification, exiting1 with Replay data changed. This establishes a local explanation matching the remote symptom, not an independent inspection of the remote MAT.

## Fix

resize_sac_replay now compares complete oldest-to-newest records and tracker IDs through R2024b's hidden getLastNData accessor before/after reconstruction. Version restriction stays R2024b. This retains strict equality for every observation, next observation, action, reward, terminal marker and sequence-source ID; no sorting by reward, tolerance relaxation or clearing replay. Existing optimizer, policy/entropy state, actor/twin critic/target weight checks remain. Source replay is copied, not resized in place.

## Verification completed

The corrected batch passed test_sac_replay_wrapped for128-capacity buffers containing32,128,173 and400 appended records, then100000-capacity with100037 records expanded to500000, including MAT save/reload. Tests compare known reward chronology, complete records, terminal markers, tracker IDs and unchanged parent raw storage. test_sac_replay_resize also passed optimizer/entropy preservation and64 total synthetic learning steps; test_sac_replay_pair passed two-child preparation using the prior2-episode flight fixture. No remote production MAT was available locally. Raw logs and synthetic MAT remain under ignored tests/output.

## Remote next step

Original source run remains paused. Pull the fix, use a fresh MATLAB session and rerun the prepare-only pair command. A new baseline/candidate pair is deliberate: old baseline20261022_132700_recovery_tp4c73786a remains untouched and should not be launched. No need to delete locks, snapshots or incomplete artifacts. Receipt is copied only after both branches pass all checks. The original full checkpoint will rerun data integrity checks on the remote machine.
