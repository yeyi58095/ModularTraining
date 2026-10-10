#!/usr/bin/env python3
"""Plot MATLAB training logs across attempts. Requires: pip install matplotlib.

Examples:
  python plot_training_rewards.py
  python plot_training_rewards.py +trainingmodels/ppo_lstm128/runs/SESSION_NAME
  python plot_training_rewards.py SESSION_PATH --watch 60

With no path, select the newest session in curriculum experiments, model runs or sessions.
Logs are only read. The original Flower project is not required.
If an episode is repeated after a restart, the latest attempt takes precedence.
"""

import argparse
import csv
import json
import os
from datetime import datetime
from pathlib import Path
import re
import time
import tempfile
import warnings


NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
EPISODE = re.compile(
    rf"Episode:\s*(\d+)\s*/\s*\d+\s*\|\s*"
    rf"Episode reward:\s*({NUMBER})\s*\|\s*"
    rf"Episode steps:\s*(\d+)\s*\|\s*"
    rf"Average reward:\s*({NUMBER})\s*\|\s*"
    rf"Step Count:\s*(\d+)\s*\|\s*Episode Q0:\s*({NUMBER})"
)
ATTEMPT = re.compile(r"attempt_?(\d+)$", re.IGNORECASE)


def log_files(session):
    found = []
    for directory in session.iterdir():
        match = ATTEMPT.fullmatch(directory.name)
        if directory.is_dir() and match:
            log = directory / "stdout.log"
            if log.is_file():
                found.append((int(match[1]), log))
    return sorted(found)


def select_session(path):
    root = Path(path).expanduser().resolve()
    if not root.is_dir():
        raise ValueError(f"Directory does not exist: {root}")
    if log_files(root):
        return root
    candidates = []
    children = list(root.iterdir())
    # New plan-oriented layout; also accept experiments/ or a plan directory.
    children.extend(root.glob("experiments/*/runs/*"))
    children.extend(root.glob("*/runs/*"))
    # Project root: search model run folders and the legacy sessions folder.
    models = root / "+trainingmodels"
    if models.is_dir():
        for model in models.iterdir():
            runs = model / "runs"
            if runs.is_dir():
                children.extend(runs.iterdir())
    legacy = root / "sessions"
    if legacy.is_dir():
        children.extend(legacy.iterdir())
    # A model directory may also be supplied directly.
    if (root / "runs").is_dir():
        children.extend((root / "runs").iterdir())
    for child in set(children):
        if child.is_dir():
            logs = log_files(child)
            if logs:
                candidates.append((max(p.stat().st_mtime for _, p in logs), child))
    if not candidates:
        raise ValueError(f"No attempt*/stdout.log found in {root} or its session folders.")
    return max(candidates)[1]


def read_episodes(session):
    episodes = {}
    duplicates = 0
    used_attempts = 0
    for attempt, log in log_files(session):
        matched = False
        # Only complete lines are used: the last line may still be being written.
        with log.open(encoding="utf-8-sig", errors="replace") as stream:
            for line in stream:
                if not line.endswith("\n"):
                    continue
                match = EPISODE.search(line)
                if not match:
                    continue
                ep, reward, steps, average, total_steps, q0 = match.groups()
                ep = int(ep)
                duplicates += ep in episodes
                episodes[ep] = {
                    "episode": ep, "reward": float(reward), "steps": int(steps),
                    "average_reward": float(average), "total_steps": int(total_steps),
                    "q0": float(q0), "attempt": attempt,
                }
                matched = True
        used_attempts += matched
    return [episodes[k] for k in sorted(episodes)], duplicates, used_attempts


def read_stages(session):
    """Use saved curriculum boundaries only, never infer stages from rewards."""
    plan_file = session / "curriculum.json"
    state_file = session / "curriculum_state.json"
    if not plan_file.is_file() or not state_file.is_file():
        return []
    try:
        plan = json.loads(plan_file.read_text(encoding="utf-8-sig"))
        state = json.loads(state_file.read_text(encoding="utf-8-sig"))
        index = state["stage_index"]
        stages = plan["stages"]
        completed = state["completed"]
        # MATLAB jsondecode -> jsonencode turns a singleton struct array
        # into an object when prepare re-saves state without advancing.
        if isinstance(stages, dict):
            stages = [stages]
        if isinstance(completed, dict):
            completed = [completed]
        if not isinstance(stages, list) or not isinstance(completed, list):
            raise ValueError("Stage history must be an array or a single object")
        if not isinstance(index, int) or not 1 <= index <= len(stages):
            raise ValueError("Invalid stage index")
        if len(completed) != index - 1:
            raise ValueError("Incomplete stage history")
        result = []
        boundary = 0
        for i, item in enumerate(completed):
            end = item["end_episode"]
            if (item["id"] != stages[i]["id"] or item["start_episode"] != boundary
                    or not isinstance(end, int) or end <= boundary):
                raise ValueError("Invalid stage boundary")
            result.append({"index": i + 1, "id": item["id"], "start": boundary})
            boundary = end
        if state["start_episode"] != boundary:
            raise ValueError("Current stage start disagrees with history")
        result.append({"index": index, "id": stages[index - 1]["id"], "start": boundary})
        return result
    except (OSError, ValueError, KeyError, TypeError, IndexError) as exc:
        # A writer may be replacing the state during --watch. Retry next refresh.
        warnings.warn(f"Stage labels unavailable; reward plot still updated: {exc}")
        return []


def annotate_stages(ax, stages, first_episode, last_episode):
    visible = [s for s in stages if s["start"] < last_episode]
    for i, stage in enumerate(visible):
        boundary = stage["start"] + 0.5  # between N and N+1, not on either episode
        if stage["index"] > 1 and boundary >= first_episode:
            ax.axvline(boundary, color="#b45309", linewidth=1.4, linestyle="-.",
                       label="Stage transition" if not any(
                           s["index"] > 1 and s["start"] + 0.5 >= first_episode
                           for s in visible[:i]) else None)
        next_start = visible[i + 1]["start"] if i + 1 < len(visible) else last_episode
        if next_start < first_episode:
            continue
        position = max(boundary, first_episode)
        label = f"Stage {stage['index']}\n{stage['id']}"
        ax.annotate(label, xy=(position, 0), xycoords=ax.get_xaxis_transform(),
                    xytext=(3, -40 - (i % 2) * 30), textcoords="offset points",
                    ha="left", va="top", fontsize=8, color="#92400e",
                    annotation_clip=False)


def save_png(fig, output):
    """Render away from the viewer's open file; keep the last good PNG on failure."""
    fd, name = tempfile.mkstemp(prefix=".reward-", suffix=".png", dir=output.parent)
    os.close(fd)
    temporary = Path(name)
    try:
        fig.savefig(temporary, format="png", dpi=180, facecolor="white", bbox_inches="tight")
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)


def draw(session, output, plt):
    rows, duplicates, attempts = read_episodes(session)
    if not rows:
        print(f"No complete episode records yet: {session}", flush=True)
        return False
    output.parent.mkdir(parents=True, exist_ok=True)
    x = [r["episode"] for r in rows]
    # Insert gaps rather than imply continuity across missing episodes.
    plot_x, rewards, averages = [], [], []
    for i, row in enumerate(rows):
        if i and row["episode"] != rows[i - 1]["episode"] + 1:
            plot_x.append(float("nan"))
            rewards.append(float("nan"))
            averages.append(float("nan"))
        plot_x.append(row["episode"])
        rewards.append(row["reward"])
        averages.append(row["average_reward"])

    with plt.rc_context({"font.size": 11, "axes.spines.top": False,
                         "axes.spines.right": False}):
        fig, ax = plt.subplots(figsize=(15, 6.5), layout="constrained")
        ax.plot(plot_x, rewards, color="#8aafcf", linewidth=0.6, alpha=0.5,
                label="Episode reward", rasterized=True)
        ax.plot(plot_x, averages, color="#086788", linewidth=1.8,
                label="Average reward (as logged)")
        boundaries = [rows[i]["episode"] for i in range(1, len(rows))
                      if rows[i]["attempt"] != rows[i - 1]["attempt"]]
        for i, boundary in enumerate(boundaries):
            ax.axvline(boundary, color="#64748b", linewidth=0.6, alpha=0.3,
                       linestyle="--", label="Attempt boundary" if i == 0 else None)
        latest = rows[-1]
        ax.scatter([x[-1]], [latest["average_reward"]], color="#086788", s=25, zorder=5)
        ax.set_title(
            f"Training Reward History | Episodes {x[0]:,} - {x[-1]:,}\n"
            f"{attempts} attempts with data | Latest average: {latest['average_reward']:,.2f}",
            loc="left", fontsize=15, pad=14)
        ax.set_xlabel("Episode")
        annotate_stages(ax, read_stages(session), x[0], x[-1])
        ax.set_ylabel("Reward")
        ax.grid(axis="y", alpha=0.18)
        ax.legend(loc="upper left", framealpha=0.9)
        ax.margins(x=0.01)
        fig.text(0.01, 0.005,
                 f"Session: {session.name} | Snapshot: {datetime.now():%Y-%m-%d %H:%M:%S}",
                 fontsize=8, color="#64748b")
        try:
            save_png(fig, output)
        finally:
            plt.close(fig)

    csv_path = output.with_suffix(".csv")
    with csv_path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    gaps = x[-1] - x[0] + 1 - len(rows)
    print(f"Episodes: {len(rows):,} | Latest: {x[-1]:,} | "
          f"Average: {latest['average_reward']:.2f} | "
          f"Duplicates replaced: {duplicates} | Missing episodes within range: {gaps}\n"
          f"PNG: {output}\nCSV: {csv_path}", flush=True)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("session", nargs="?", type=Path,
                        default=Path(__file__).resolve().parent,
                        help="Session directory, or parent containing sessions (newest selected)")
    parser.add_argument("--output", type=Path, help="PNG path (default: SESSION/reward_history.png)")
    parser.add_argument("--watch", type=float, default=0, metavar="SECONDS",
                        help="Refresh the same PNG and CSV periodically; Ctrl+C stops plotting only")
    args = parser.parse_args()
    if args.watch < 0 or (args.watch and args.watch < 1):
        parser.error("--watch must be 0 (one snapshot) or at least 1 second")
    try:
        import matplotlib
        matplotlib.use("Agg")  # Works on remote machines without a display.
        import matplotlib.pyplot as plt
    except ImportError:
        parser.exit(1, "Missing matplotlib. Install with: python -m pip install matplotlib\n")
    try:
        session = select_session(args.session)
        output = args.output.expanduser().resolve() if args.output else session / "reward_history.png"
        if output.suffix.lower() != ".png":
            parser.error("--output must end in .png")
        print(f"Reading session: {session}", flush=True)
        while True:
            try:
                success = draw(session, output, plt)
            except OSError as exc:
                if not args.watch:
                    raise
                print(f"Plot refresh failed: {exc}\n"
                      f"Retrying in {args.watch:g}s. If persistent, close the image viewer "
                      "or choose another --output path. Training is unaffected.", flush=True)
                time.sleep(args.watch)
                continue
            if not args.watch:
                return 0 if success else 1
            time.sleep(args.watch)
    except KeyboardInterrupt:
        print("\nPlot refresh stopped. Training is unaffected.")
        return 0
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Error: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
