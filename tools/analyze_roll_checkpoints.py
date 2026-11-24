"""Compare measured bank and bank commands from two frozen straight-route checkpoints."""

import argparse
import csv
import json
import math
from pathlib import Path
import statistics

import matplotlib

matplotlib.use("Agg")
from matplotlib import pyplot as plt


SAMPLE_PERIOD_S = 0.1
TIME_TOLERANCE_S = 0.002
LAG_SAMPLES = 12
MIN_LAG_PAIRS = 20
PERIOD_BAND_S = (1.5, 3.0)
WINDOWS_S = ((10, 20), (20, 30), (30, 40), (20, 40))
COLUMNS = ("time_s", "bank_command_deg", "measured_roll_deg", "east_m", "north_m")


def near_time(left, right):
    return abs(left - right) <= TIME_TOLERANCE_S


def read_trace(package, relative):
    relative = Path(relative)
    source = (package / relative).resolve()
    if relative.is_absolute() or not source.is_relative_to(package):
        raise ValueError(f"Trace CSV must be inside the package: {relative}")
    with source.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames is None or not set(COLUMNS).issubset(reader.fieldnames):
            raise ValueError(f"Missing required trace columns in {relative}")
        rows = [tuple(float(row[name]) for name in COLUMNS) for row in reader]
    if not rows or any(not math.isfinite(value) for row in rows for value in row):
        raise ValueError(f"Empty or nonfinite trace: {relative}")
    if any(left[0] >= right[0] for left, right in zip(rows, rows[1:])):
        raise ValueError(f"Trace times must increase strictly: {relative}")
    return rows


def load_pairs(package):
    manifest = json.loads((package / "roll_cases.json").read_text(encoding="utf-8-sig"))
    pairs = {}
    for item in manifest["cases"]:
        episode = item["episode"]
        scenario = item["scenario"].strip()
        wind = item["wind"]
        steps = item["steps"]
        done = item["environment_done"]
        if type(episode) is not int or episode <= 0 or not scenario:
            raise ValueError("Each case requires a positive episode and a scenario name")
        if len(wind) != 3 or not all(type(value) in (int, float) and math.isfinite(value) for value in wind):
            raise ValueError(f"Expected three finite wind components for {scenario}")
        if type(steps) is not int or steps < 0 or type(done) is not bool:
            raise ValueError(f"Invalid step count or termination flag for {scenario} E{episode}")
        by_episode = pairs.setdefault(scenario, {})
        if episode in by_episode:
            raise ValueError(f"Duplicate trace for {scenario} E{episode}")
        rows = read_trace(package, item["trace_csv"])
        by_episode[episode] = (dict(item, scenario=scenario), rows)
    episodes = sorted({episode for by_episode in pairs.values() for episode in by_episode})
    if len(episodes) != 2:
        raise ValueError("Provide traces for exactly two checkpoint episodes")
    for scenario, by_episode in pairs.items():
        if sorted(by_episode) != episodes:
            raise ValueError(f"Each scenario needs both checkpoints: {scenario}")
        if by_episode[episodes[0]][0]["wind"] != by_episode[episodes[1]][0]["wind"]:
            raise ValueError(f"Checkpoint wind settings differ for {scenario}")
    return episodes, pairs


def rising_periods(times, angles, center=0.0):
    crossings = []
    for t0, t1, a0, a1 in zip(times, times[1:], angles, angles[1:]):
        if a0 <= center < a1:
            crossings.append(t0 + (center - a0) * (t1 - t0) / (a1 - a0))
    return [right - left for left, right in zip(crossings, crossings[1:])]


def summarize_periods(periods):
    in_band = [period for period in periods if PERIOD_BAND_S[0] <= period <= PERIOD_BAND_S[1]]
    return {
        "intervals_s": periods,
        "interval_count": len(periods),
        "median_s": statistics.median(periods) if periods else None,
        "count_1p5_to_3_s": len(in_band),
    }


def correlation_lag(command, roll):
    pair_count = len(command) - 2 * LAG_SAMPLES
    if pair_count < MIN_LAG_PAIRS:
        return None, "insufficient_pairs"
    core = command[LAG_SAMPLES:-LAG_SAMPLES]
    if max(core) - min(core) <= 1e-9:
        return None, "constant_command"
    scores = {}
    for lag in range(-LAG_SAMPLES, LAG_SAMPLES + 1):
        start = LAG_SAMPLES + lag
        actual = roll[start:start + pair_count]
        if max(actual) - min(actual) > 1e-9:
            scores[lag] = statistics.correlation(core, actual)
    if not scores:
        return None, "constant_measured_roll"
    best = max(scores, key=lambda lag: (scores[lag], -abs(lag)))
    return {
        "pairs_per_shift": pair_count,
        "shift_samples_actual_after_command": best,
        "shift_s_actual_after_command": round(best * SAMPLE_PERIOD_S, 6),
        "correlation_at_best_shift": scores[best],
        "correlation_at_zero_shift": scores.get(0),
        "evaluated_shift_count": len(scores),
        "at_search_limit": abs(best) == LAG_SAMPLES,
    }, "measured"


def angle_statistics(values):
    if not values:
        return {"range_deg": None, "peak_to_peak_deg": None, "mean_deg": None, "rms_about_mean_deg": None}
    mean = statistics.mean(values)
    bounds = (min(values), max(values))
    return {
        "range_deg": bounds,
        "peak_to_peak_deg": bounds[1] - bounds[0] if len(values) >= 2 else None,
        "mean_deg": mean,
        "rms_about_mean_deg": math.sqrt(statistics.mean((value - mean) ** 2 for value in values)),
    }


def summarize_window(rows, start, end):
    selected = [row for row in rows if start - TIME_TOLERANCE_S <= row[0] < end - TIME_TOLERANCE_S]
    times = [row[0] for row in selected]
    command = [row[1] for row in selected]
    roll = [row[2] for row in selected]
    cross_track = [abs(row[4]) for row in selected]
    expected = round((end - start) / SAMPLE_PERIOD_S)
    contiguous = all(near_time(right - left, SAMPLE_PERIOD_S) for left, right in zip(times, times[1:]))
    complete = contiguous and len(times) == expected and all(
        near_time(time, start + index * SAMPLE_PERIOD_S) for index, time in enumerate(times)
    )
    coverage = "empty"
    if times:
        coverage = "complete" if complete else "partial" if contiguous else "gapped"
    zero_periods = []
    centered_periods = []
    lag = None
    lag_status = "nonuniform_sampling"
    if contiguous:
        zero_periods = rising_periods(times, roll)
        if roll:
            centered_periods = rising_periods(times, roll, statistics.mean(roll))
        lag, lag_status = correlation_lag(command, roll)
    return {
        "window_s": [start, end],
        "coverage": coverage,
        "expected_samples": expected,
        "sample_count": len(selected),
        "time_range_s": [times[0], times[-1]] if times else None,
        "measured_roll": angle_statistics(roll),
        "bank_command": angle_statistics(command),
        "bank_command_median_step_deg": statistics.median(
            abs(right - left) for left, right in zip(command, command[1:])
        ) if contiguous and len(command) >= 2 else None,
        "measured_roll_median_step_deg": statistics.median(
            abs(right - left) for left, right in zip(roll, roll[1:])
        ) if contiguous and len(roll) >= 2 else None,
        "measured_rising_zero": summarize_periods(zero_periods),
        "measured_rising_centered": summarize_periods(centered_periods),
        "command_measured_lag": lag,
        "lag_status": lag_status,
        "cte_rms_m": math.sqrt(statistics.mean(value ** 2 for value in cross_track)) if cross_track else None,
        "cte_peak_m": max(cross_track) if cross_track else None,
    }


def summarize_case(case, rows):
    return dict(
        case,
        sample_count=len(rows),
        time_range_s=[rows[0][0], rows[-1][0]],
        whole_trace_measured_roll=angle_statistics([row[2] for row in rows]),
        whole_trace_bank_command=angle_statistics([row[1] for row in rows]),
        windows=[summarize_window(rows, start, end) for start, end in WINDOWS_S],
    )


def plot_comparison(destination, episodes, pairs):
    count = len(pairs)
    fig, axes = plt.subplots(count, 2, figsize=(11, 2.8 * count + 0.9),
                             squeeze=False, sharex="row", layout="constrained")
    fig.suptitle("Frozen straight-flight roll comparison · analysis window shaded", fontsize=15)
    colors = ("#975036", "#156485")
    for index, (scenario, by_episode) in enumerate(pairs.items()):
        command_axis, roll_axis = axes[index, :]
        last_time = max(40, *(rows[-1][0] for _, rows in by_episode.values()))
        for episode, color in zip(episodes, colors):
            case, rows = by_episode[episode]
            times, command, roll, _, _ = zip(*rows)
            command_axis.step(times, command, where="post", color=color, alpha=0.65,
                              linewidth=0.7, label=f"E{episode}")
            roll_axis.plot(times, roll, color=color, linewidth=1.2, label=f"E{episode}")
        command_axis.set_title(f"{scenario.replace('_', ' ').capitalize()} · {tuple(case['wind'])}", fontsize=11)
        roll_axis.set_title("Measured roll", fontsize=11)
        command_axis.set_ylabel("Bank command (deg)")
        command_axis.set_ylim(-42, 42)
        roll_axis.set_ylabel("Roll (deg)")
        for axis in (command_axis, roll_axis):
            axis.axvspan(20, 40, color="#e5ebf0", zorder=0)
            axis.axhline(0, color="#56626b", linewidth=0.55, alpha=0.55)
            axis.set_xlim(0, last_time)
            axis.set_xlabel("Time (s)")
            axis.grid(axis="y", color="#ccd3d8", alpha=0.6)
    axes[0, 1].legend(loc="upper right", fontsize=8)
    fig.savefig(destination, dpi=150)
    plt.close(fig)


def analyze(package):
    package = package.resolve()
    episodes, pairs = load_pairs(package)
    report = {
        "schema_version": 1,
        "case_manifest": "roll_cases.json",
        "pair_episodes": episodes,
        "nominal_sample_period_s": SAMPLE_PERIOD_S,
        "time_tolerance_s": TIME_TOLERANCE_S,
        "windows_s": WINDOWS_S,
        "period_band_s": PERIOD_BAND_S,
        "lag": {
            "search_s": [-round(LAG_SAMPLES * SAMPLE_PERIOD_S, 6), round(LAG_SAMPLES * SAMPLE_PERIOD_S, 6)],
            "minimum_pairs_per_shift": MIN_LAG_PAIRS,
            "interpretation": "Fixed-pair Pearson shift. Positive means the measured roll follows the command. Closed-loop correlation is descriptive.",
        },
        "coverage": "Windows include the start and exclude the end. Partial windows use available samples only. Gaps disable periods and lag.",
        "cross_track": "Absolute north position in meters from the straight eastward reference line at north=0.",
        "cases": [
            summarize_case(*by_episode[episode])
            for by_episode in pairs.values()
            for episode in episodes
        ],
    }
    plot_comparison(package / "roll_comparison.png", episodes, pairs)
    destination = package / "roll_metrics.json"
    destination.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path, help="Directory containing roll_cases.json and trace CSVs")
    args = parser.parse_args()
    try:
        print(analyze(args.package))
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
