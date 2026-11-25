"""Report terminal geometry for four historical PPO Stage 6 failure traces."""

import argparse
import json
from pathlib import Path

import numpy as np


DEFAULT_INPUT = Path(__file__).resolve().parents[2] / "diagnostic_packages" / "stage6_review"


def review(seed, folder):
    filename = folder / f"ep31600_stage6_seed{seed}.json"
    trace = json.loads(filename.read_text(encoding="utf-8-sig"))

    def series(name):
        return np.asarray(trace[name]["data"], dtype=float).reshape(-1)

    time = np.asarray(trace["P_E"]["t"])
    position = np.column_stack((series("P_E"), series("P_N")))
    target = np.column_stack((series("target_E"), series("target_N")))
    heading = series("psi")
    forward = np.sum((target-position) * np.column_stack((np.cos(heading), np.sin(heading))), axis=1)
    guidance = series("guidance_d")
    jumps = np.linalg.norm(np.diff(target, axis=0), axis=1)
    events = np.flatnonzero((jumps > 20) | (np.abs(np.diff(guidance)) > 10)) + 1
    print("\nSEED", seed, "end", time[-1], "maxroll", np.max(np.abs(series("phi"))), "events",
          [(round(time[i], 1), round(jumps[i-1], 1), round(guidance[i]-guidance[i-1], 1)) for i in events])

    indices = set(range(max(0, len(time)-151), len(time), 10))
    indices.add(len(time)-1)
    for event in events:
        if time[event] > time[-1]-20:
            indices.update([event-1, event])

    heading_error = np.rad2deg(series("guidance_heta"))
    valid = series("window_valid")
    for i in sorted(indices):
        snapshot = max((s for s in trace["planned_path"] if s["t"] <= time[i]+1e-7),
                       key=lambda s: s["t"])
        path = np.asarray(snapshot["path"])[:, :2]
        segments = np.diff(path, axis=0)
        tangent = segments[-1] / np.linalg.norm(segments[-1])
        offset = position[i] - path[-1]
        along = offset @ tangent
        lateral = np.linalg.norm(offset - along*tangent)
        inside = np.all(position[i] >= path.min(axis=0)-30) and np.all(position[i] <= path.max(axis=0)+30)
        projection = np.sum((position[i]-path[:-1]) * segments, axis=1)
        fractions = np.clip(projection / np.maximum(np.sum(segments**2, axis=1), 1e-12), 0, 1)
        finite = np.min(np.linalg.norm(position[i]-path[:-1]-fractions[:, None]*segments, axis=1))
        print(f"{time[i]:5.1f} d={guidance[i]:5.1f} geom={finite:5.1f} fwd={forward[i]:6.1f} "
              f"heta={heading_error[i]:6.1f} inside={inside} along={along:6.1f} lat={lateral:5.1f} "
              f"valid={valid[i]:.0f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=DEFAULT_INPUT,
                        help="Directory of exported Stage 6 JSON traces")
    options = parser.parse_args()
    for seed in (202, 204, 205, 207):
        review(seed, options.input_dir)
