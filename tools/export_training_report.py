#!/usr/bin/env python3
# 精簡診斷報告：彙整完整日誌、設定白名單、worker 與 learning health。
# 輸出有大小上限且移除來源絕對路徑的 report.json；只診斷，不自動停訓或回滾。
"""Export bounded, path-free training diagnostics for GitHub (standard library only).

Reads logs, never controls MATLAB. Reports observations, not checkpoint lineage.
"""
import argparse
from collections import Counter, deque
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import statistics

from plot_training_rewards import log_files, read_episodes, select_session
from learning_health import assess_learning

ROOT = Path(__file__).resolve().parents[1]
MAX_BYTES = 1_500_000
CONTROL_KEYS = ("numWorkers", "minWorkers", "fallbackWorkers", "checkpointEvery", "episodesPerProcess",
                "targetReward", "averageWindow", "trainingDevice", "maxAttempts",
                "maxNoProgressFailures", "startupTimeoutSeconds", "stallTimeoutSeconds")
MODEL_KEYS = ("schemaVersion", "lstmUnits", "actorHidden", "criticHidden", "meanHidden",
              "stdHidden", "sampleTime", "discountFactor", "miniBatchSize",
              "experienceHorizon", "numEpoch", "entropyLossWeight", "actorLearnRate",
              "criticLearnRate", "actorGradientThreshold", "criticGradientThreshold")
EVENTS = {
    "checkpoint_skipped": "Skipping unusable checkpoint",
    "rollback_refused": "Checkpoint:RollbackWouldOverwrite",
    "license_error": "license",
    "out_of_memory": "out of memory",
    "startup_timeout": "startup_timeout",
    "stall_timeout": "stall_timeout",
    "matlab_error_line": "Error using",
}


# 只保留有限數字、布林與短數值陣列，其他值不輸出至分享報告。
def numeric(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)) and math.isfinite(value):
        return value
    if isinstance(value, list) and len(value) <= 32:
        result = [numeric(item) for item in value]
        if all(item is not None for item in result):
            return result
    return None


# 有大小上限地讀 metadata；缺檔、寫入中或壞 JSON 記 warning 並返回空資料。
def read_json(path, warnings):
    if not path.is_file():
        warnings.append(f"missing:{path.name}")
        return {}
    try:
        if path.stat().st_size > 1_000_000:
            raise ValueError("oversized metadata")
        value = json.loads(path.read_text(encoding="utf-8-sig"))
        if not isinstance(value, dict):
            raise ValueError("metadata must be an object")
        return value
    except (ValueError, OSError):
        warnings.append(f"unreadable_or_changing:{path.name}")
        return {}


# 按欄位白名單抽取可分享數值，排除任意字串與本機路徑。
def settings(value, keys):
    return {key: numeric(value[key]) for key in keys
            if key in value and numeric(value[key]) is not None}


# 抽取 guard／recovery 的允許欄位，原因只接受已知值，不暴露父 run 絕對位置。
def recovery_metadata(session, warnings):
    result = {}
    for filename, keys in {
        "training_guard.json": ("window", "patience", "reward_ratio", "steps_ratio",
                                "min_reference_reward", "min_reference_steps", "origin_episode",
                                "max_additional_episodes"),
        "training_guard_state.json": ("paused", "suspected_regression", "low_windows", "episode",
                                      "stage_index", "reference_reward", "reference_steps",
                                      "reference_end_episode", "latest_reward", "latest_steps"),
        "recovery.json": ("parent_episode", "actor_learning_rate_before", "actor_learning_rate_after",
                          "weights_preserved"),
    }.items():
        if not (session / filename).is_file():
            continue
        raw = read_json(session / filename, warnings)
        value = settings(raw, keys)
        if filename == "training_guard_state.json":
            value["reason"] = raw.get("reason") if raw.get("reason") in {
                "continue", "suspected_regression", "recovery_budget"} else "unknown"
        result[Path(filename).stem] = value
    return result


# 將所選 episode 區間彙整為 reward、steps 等統計；只是日誌觀察，不代表 checkpoint 實際進度。
def summarize(rows):
    if not rows:
        return None
    rewards = [r["reward"] for r in rows]
    steps = [r["steps"] for r in rows]
    return dict(first_episode=rows[0]["episode"], last_episode=rows[-1]["episode"],
                count=len(rows), reward_mean=statistics.fmean(rewards),
                reward_min=min(rewards), reward_max=max(rewards),
                steps_mean=statistics.fmean(steps), steps_min=min(steps), steps_max=max(steps),
                short_under_256_fraction=sum(s < 256 for s in steps) / len(rows),
                full_3000_fraction=sum(s == 3000 for s in steps) / len(rows),
                q0_mean=statistics.fmean(r["q0"] for r in rows),
                logged_average_last=rows[-1]["average_reward"])


# 在連續 episode 中找完整 reward 視窗最高均值；遇缺口清空，不跨缺口拼接。
def rolling_best(rows, window=50):
    queue = deque()
    best = None
    total = 0.0
    previous = None
    for row in rows:
        if previous is not None and row["episode"] != previous + 1:
            queue.clear()
            total = 0.0
        previous = row["episode"]
        queue.append(row["reward"])
        total += row["reward"]
        if len(queue) > window:
            total -= queue.popleft()
        if len(queue) == window and (best is None or total / window > best["mean"]):
            best = {"mean": total / window, "ending_episode": previous, "window": window}
    return best


# 分塊讀取允許來源並計算 SHA-256，使用相對路徑；當下檔案指紋不是歷史版本證明。
def fingerprint(paths, base):
    result = {}
    for path in sorted(paths):
        if path.is_file() and not path.is_symlink():
            h = hashlib.sha256()
            with path.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    h.update(block)
            result[path.relative_to(base).as_posix()] = h.hexdigest()
    return result


# 清除非有限紀錄，限制詳細 attempt 數與輸出大小，分開呈現日誌 learning health 和 runtime guard。
def export_report(session, machine, diagnostics=None, first=None, last=None, health_options=None):
    warnings = []
    rows, duplicates, used = read_episodes(session)
    invalid = sum(not all(math.isfinite(r[k]) for k in ("reward", "average_reward", "q0"))
                  for r in rows)
    rows = [r for r in rows if all(math.isfinite(r[k]) for k in ("reward", "average_reward", "q0"))]
    if not rows:
        raise ValueError("No complete finite episode records found; no report was written.")
    curriculum = None
    health_rows = rows
    if (session / "curriculum.json").is_file():
        state = read_json(session / "curriculum_state.json", warnings)
        start, index = state.get("start_episode"), state.get("stage_index")
        if type(start) is int and start >= 0 and type(index) is int and index >= 1:
            curriculum = dict(stage_index=index, stage_start_episode=start)
            health_rows = [row for row in rows if row["episode"] > start]
        else:
            curriculum = dict(state="unknown")
            health_rows = []
            warnings.append("curriculum_state_unknown:learning_health_not_evaluated")
    health = assess_learning(health_rows, **(health_options or {}))
    health["scope"] = "current_curriculum_stage" if curriculum is not None else "whole_experiment"
    model = read_json(session / "model.json", warnings)
    control = read_json(session / "control.json", warnings)
    control_settings = settings(control, CONTROL_KEYS)
    if control.get("trainingDevice") in {"cpu", "gpu"}:
        control_settings["trainingDevice"] = control["trainingDevice"]
    status = read_json(session / "status.json", warnings)
    logs = log_files(session)
    # Keep every attempt in aggregate counts; only retain 200 detailed summaries.
    attempt_tail = deque(maxlen=200)
    event_counts = Counter()
    by_attempt = {}
    for row in rows:
        by_attempt.setdefault(row["attempt"], []).append(row)
    changed_logs = 0
    for attempt, stdout in logs:
        before = stdout.stat()
        events = Counter()
        for path in (stdout, stdout.with_name("stderr.log")):
            if path.is_file():
                with path.open(encoding="utf-8-sig", errors="replace") as stream:
                    for line in stream:
                        if line.endswith("\n"):
                            for key, phrase in EVENTS.items():
                                if phrase.lower() in line.lower():
                                    events[key] += 1
        after = stdout.stat()
        changed_logs += (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns)
        event_counts.update(events)
        attempt_tail.append(dict(attempt=attempt, stdout_bytes=after.st_size,
                                 retained_episodes=summarize(by_attempt.get(attempt, [])),
                                 event_line_counts=dict(events)))
    diag = diagnostics if diagnostics is not None else session / "diagnostics"
    reasons, workers = Counter(), Counter()
    worker_tail = deque(maxlen=200)
    worker_csv = diag / "worker_attempts.csv"
    if worker_csv.is_file():
        with worker_csv.open(encoding="utf-8-sig", newline="") as stream:
            for row in csv.DictReader(stream):
                try:
                    item = {key: int(row[key]) for key in
                            ("Attempt", "TargetWorkers", "RequestedWorkers", "ActualWorkers", "ExitCode")}
                    duration = float(row["DurationSeconds"])
                    if not math.isfinite(duration):
                        raise ValueError("nonfinite duration")
                    item["DurationSeconds"] = duration
                except (ValueError, KeyError, TypeError):
                    warnings.append("malformed_worker_row")
                    continue
                reason = row.get("Reason", "unknown")
                if reason not in {"normal_exit", "pool_start_failed", "matlab_error", "license_error",
                                  "startup_timeout", "stall_timeout"}:
                    reason = "other"
                item["Reason"] = reason
                reasons[reason] += 1
                workers[str(item["ActualWorkers"])] += 1
                worker_tail.append(item)
    else:
        warnings.append("missing:worker_attempts.csv; use --diagnostics for legacy location")
    chosen = [r for r in rows if (first is None or r["episode"] >= first)
              and (last is None or r["episode"] <= last)]
    if not chosen:
        raise ValueError("No episodes in requested focus range.")
    size = max(1, math.ceil(len(chosen) / 400))
    source = session / "model_source"
    snapshot_paths = list((source / "+trainingmodels").glob("*.m"))
    snapshot_paths += list((source / "+trainingmodels").glob("*/*.m"))
    local_paths = [ROOT / name for name in ("retry.m", "training.m", "tools/export_training_report.py",
                                          "tools/plot_training_rewards.py", "tools/learning_health.py")]
    local_paths += list((ROOT / "runtime").glob("*.m")) + list((ROOT / "runtime").glob("*.ps1"))
    local_paths += list((ROOT / "runtime").glob("*.slx"))
    local_paths += list((ROOT / "+trainingmodels").glob("*.m"))
    local_paths += list((ROOT / "+trainingmodels").glob("*/*.m"))
    local_paths += list((ROOT / "+trainingcurriculum").glob("*.m"))
    local_paths += list((ROOT / "+trainingguard").glob("*.m"))
    local_paths += list((ROOT / "+trainingtools").glob("*.m"))
    if not snapshot_paths:
        warnings.append("missing:model_source snapshot")
    model_name = model.get("name", "unknown")
    if not isinstance(model_name, str) or not re.fullmatch(r"[a-z][a-z0-9_]{0,100}", model_name):
        model_name = "unknown"
    state = status.get("state")
    if state not in {"running", "paused", "stopped", "restarting", "success", "retrying", "error"}:
        state = "unknown"
    report = dict(schema_version=1, machine=machine, session_id=session.name,
                  exported_at_utc=datetime.now(timezone.utc).isoformat(), model=model_name,
                  model_settings=settings(model, MODEL_KEYS), control_settings=control_settings,
                  status=state, curriculum=curriculum, learning_health=health,
                  recovery_monitor=recovery_metadata(session, warnings),
                  episode_count=len(rows), first_episode=rows[0]["episode"],
                  last_episode=rows[-1]["episode"], duplicate_lines_replaced=duplicates,
                  missing_episodes=rows[-1]["episode"] - rows[0]["episode"] + 1 - len(rows),
                  nonfinite_records_excluded=invalid, attempts_with_data=used,
                  attempts_total=len(logs), best_contiguous_rolling50=rolling_best(rows),
                  latest_1000_observed=summarize(rows[-1000:]),
                  latest_100_episodes=rows[-100:],
                  focus=dict(first=first, last=last, bin_records=size,
                             windows=[summarize(chosen[i:i+size]) for i in range(0, len(chosen), size)]),
                  event_line_counts=dict(event_counts), latest_200_attempts=list(attempt_tail),
                  completed_attempt_reasons=dict(reasons), completed_attempt_actual_workers=dict(workers),
                  latest_200_worker_attempts=list(worker_tail),
                  saved_model_source_sha256=fingerprint(snapshot_paths[:200], source),
                  current_checkout_sha256=fingerprint(local_paths[:200], ROOT),
                  warnings=sorted(set(warnings)), logs_changed_during_event_scan=changed_logs,
                  limitations=[
                      "Live read, not an atomic snapshot; incomplete final episode lines ignored.",
                      "Latest attempt wins per episode; not verified against saved checkpoint lineage.",
                      "Current checkout hashes do not prove what a remote or historical process executed.",
                      "At most 400 bins, 100 raw episodes, 200 attempts and 200 hashes per source group.",
                      "Event counts are substring matches, not confirmed failure causes; no raw log text exported.",
                      "No KL, policy entropy, gradient, critic loss, or termination-cause telemetry.",
                      "Steps thresholds 256/3000 describe the present FAFA configuration."])
    return report


# 解析 CLI 機器標記、episode 範圍與診斷選項，匯出精簡報告。
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session", type=Path, help="Explicit experiment folder (recommended), or parent to select newest")
    parser.add_argument("--machine", required=True, help="Alias such as lab or dorm; do not use hostnames")
    parser.add_argument("--diagnostics", type=Path, help="Explicit legacy diagnostics folder; never follows control.json paths")
    parser.add_argument("--from-episode", type=int)
    parser.add_argument("--to-episode", type=int)
    parser.add_argument("--regression-window", type=int, default=1000)
    parser.add_argument("--regression-patience", type=int, default=5)
    parser.add_argument("--regression-ratio", type=float, default=0.5)
    parser.add_argument("--regression-min-reference", type=float, default=500)
    parser.add_argument("--output", type=Path, help="Default: SESSION/reports/report.json")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,31}", args.machine):
        parser.error("--machine must be a short letters/digits/underscore/hyphen alias")
    if any(n is not None and n < 1 for n in (args.from_episode, args.to_episode)):
        parser.error("Episode bounds must be positive")
    if args.from_episode and args.to_episode and args.from_episode > args.to_episode:
        parser.error("--from-episode must not exceed --to-episode")
    try:
        session = select_session(args.session)
        default_output = (session / "reports" / "report.json").resolve()
        output = args.output or default_output
        output = output.expanduser().resolve()
        if output.suffix != ".json" or (output.is_relative_to(session) and output != default_output):
            raise ValueError("Within an experiment, only reports/report.json may be written; other .json outputs must be outside it.")
        health_options = dict(window=args.regression_window, patience=args.regression_patience,
                              ratio=args.regression_ratio, min_reference=args.regression_min_reference)
        assess_learning([], **health_options) # Validate before reading large logs.
        report = export_report(session, args.machine, args.diagnostics, args.from_episode, args.to_episode, health_options)
        payload = (json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")
        if len(payload) > MAX_BYTES:
            raise ValueError("Report exceeds 1.5 MB safety limit; no report was written.")
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_suffix(".json.tmp")
        temporary.write_bytes(payload)
        temporary.replace(output)
        print(f"Read: {session}\nReport: {output}\nBytes: {len(payload):,}; episodes: {report['episode_count']:,}")
        print(f"Learning health: {report['learning_health']['state']} (advisory only)")
        return 0
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Error: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
