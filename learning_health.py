"""Advisory regression detection over logged rewards; never controls training."""
import math
import statistics


def assess_learning(rows, window=1000, patience=5, ratio=0.5, min_reference=500):
    """Compare nonoverlapping contiguous windows with the best earlier window.

    Gaps reset the pending window and streak. A single spike cannot be the
    reference. Thresholds are engineering defaults, not validated PPO criteria.
    """
    if not isinstance(window, int) or not isinstance(patience, int) or window < 1 or patience < 1:
        raise ValueError("Regression window and patience must be positive integers")
    if not math.isfinite(ratio) or not 0 < ratio < 1:
        raise ValueError("Regression ratio must be between 0 and 1")
    if not math.isfinite(min_reference) or min_reference <= 0:
        raise ValueError("Regression minimum reference must be positive")
    pending = []
    best = None
    latest = None
    streak = 0
    streak_start = None
    previous = None
    windows = 0
    for row in rows:
        if previous is not None and row["episode"] != previous + 1:
            pending.clear()
            streak = 0
            streak_start = None
            latest = None
        previous = row["episode"]
        pending.append(row)
        if len(pending) < window:
            continue
        score = statistics.fmean(r["reward"] for r in pending)
        latest = dict(first_episode=pending[0]["episode"], last_episode=pending[-1]["episode"],
                      reward_mean=score, steps_mean=statistics.fmean(r["steps"] for r in pending))
        windows += 1
        if best is not None and best["reward_mean"] >= min_reference and score < ratio * best["reward_mean"]:
            if streak == 0:
                streak_start = pending[0]["episode"]
            streak += 1
        else:
            streak = 0
            streak_start = None
        if best is None or score > best["reward_mean"]:
            best = latest.copy()
        pending.clear()
    if latest is None or best is None or best["reward_mean"] < min_reference or windows < 2:
        state = "insufficient_evidence"
    elif streak >= patience:
        state = "suspected_regression"
    elif streak:
        state = "watch"
    else:
        state = "no_regression_detected"
    return dict(state=state, advisory_only=True, window=window, patience=patience,
                ratio=ratio, minimum_reference=min_reference, completed_windows=windows,
                consecutive_low_windows=streak, low_streak_first_episode=streak_start,
                best_window=best, latest_completed_window=latest, pending_records=len(pending),
                caveat="Logged rewards only; worker/environment/restart changes can confound this signal. No automatic stop, rollback or tuning.")
