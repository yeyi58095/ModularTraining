# Remote MATLAB native MAT I/O crashes

Received matlab-crash-review-20261027-013424.zip, SHA256706FBB40F14DC901277972E483CBDD16F40E573F4D7C8F8F4A77C846607ABC4D. Archived and hash-verified under artifacts/incoming/matlab-crash-20261027 with intake manifest; extracted five entries. Windows-events.txt is empty, not evidence of absence of a crash.

Two R2024b Update10 native interpreter-thread reports:

- 2026-10-26 23:54:05, PID35284, access violation in hdf5.dll object/dataset reads, libmat matGetVariable and saveload inFullLoadFcn. The dump alone does not identify the MAT filename.
- 2026-10-27 00:54:03, PID20584, abort/wassert in hdf5.dll H5O__free, H5Dcreate2, libmat and saveload inFullSaveFcn. The .preparing inventory has a temporary checkpoint MAT of67046455 bytes with this timestamp; no finalized Agent2100/control/recovery receipt. prepare_recovery_training writes this via checkpoint_save_final using-v7.3. Strong evidence of a save-stage crash before child publication/retry, not a training instability event.

Do not rename .preparing, reuse partial MAT, delete locks or retry the source. User reports no remaining MATLAB process. Native stacks identify the I/O subsystem but do not establish OOM, bad disk, source corruption or a particular MATLAB bug. Source2100 previously loaded/evaluated successfully. Crash paths under B:\temp do not establish that B: caused the problem.

MAT-v7.3 uses HDF5; v7 has a per-variable2^31-byte limit (MathWorks https://www.mathworks.com/help/matlab/import_export/mat-file-versions.html). Compressed0.30GB source size does not prove v7 capacity suitability. Do not globally change checkpoint format based on this alone.

Added probe_sac_v7_save: source must be paused with exclusive lock; isolated artifacts folder, stage-by-stage diary, load once, preserve state while adjusting actor to1e-5, save-v7, require all variables present, reload and compare optimizer/policy/options, actor/critic/target parameters, chronological replay+IDs and training scalar statistics, verify source SHA. No train/sim, recovery publication or runtime change. The probe artifact is not a resumable run. Native crashes cannot be caught by MATLAB try/catch; diary stage markers and crash logs remain necessary.

Local validation passed with exit0 using paused small MLP child from the previous two-episode fixture (tests/output/sac-v7-probe.log). Initial call against completed fixture was correctly rejected by paused-only gate. Initial equality check on history handle objects failed after successful save/reload; changed to explicit scalar-statistics equality, not relaxed numerical tolerances. Large remote2100 and cross-process resumption remain unvalidated. Next remote action is this isolated probe and return report.json/probe.log only, not retry. Existing-v7.3 training writes remain unchanged even if probe succeeds.
