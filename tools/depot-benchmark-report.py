#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Summarize depot chunk-phase logs and optional native control measurements.

Read-only: this does not download content, change installs, or measure a phone.
Supply one log per independent trial of the same fresh/resumed workload.
"""

import argparse
import json
import math
import re
import statistics
from pathlib import Path


def positive(value, label):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise ValueError(f"{label} must be finite and positive")
    return number


def cpu(fields):
    if "process-cpu-seconds" not in fields and "process-cpu-cores" not in fields:
        return None
    seconds = float(fields["process-cpu-seconds"].removesuffix("s"))
    cores = float(fields["process-cpu-cores"])
    if not all(math.isfinite(value) and value >= 0 for value in (seconds, cores)):
        raise ValueError("invalid process CPU measurement")
    return {"seconds": seconds, "average_cores": cores}


def trial(path):
    rows = []
    installs = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        if "[steam-install] timing " in line:
            fields = dict(re.findall(r"([\w-]+)=([^\s]+)", line.split("[steam-install] timing ", 1)[1]))
            try:
                app, completed, fetched = int(fields["app"]), int(fields["completed"]), int(fields["fetched-bytes"])
                wall = positive(fields["wall"].removesuffix("s"), "install wall")
                if app <= 0 or completed not in (0, 1) or fetched < 0:
                    raise ValueError("invalid install measurement")
                installs.append({"app": app, "completed": bool(completed), "fetched_bytes": fetched,
                                 "seconds": wall, "process_cpu": cpu(fields),
                                 "payload_mib_per_second": fetched / wall / 1048576 if completed else None})
            except (KeyError, ValueError) as error:
                raise ValueError(f"invalid install timing record at line {line_number}") from error
        marker = "[steam-depot] timing "
        if marker not in line:
            continue
        fields = dict(re.findall(r"([\w-]+)=([^\s]+)", line.split(marker, 1)[1]))
        try:
            depot = int(fields["depot"])
            fetched = int(fields["fetched-bytes"])
            retries = int(fields["retries"])
            wall = positive(fields["wall"].removesuffix("s"), "wall")
            if depot <= 0 or fetched < 0 or retries < 0:
                raise ValueError("invalid depot, bytes or retry count")
            stages = {}
            for key in ("network-sum", "decode-sum", "decrypt-sum", "decompress-sum", "checksum-sum", "write-sum",
                        "resume-check-sum", "resume-sha1-sum"):
                if key in fields:
                    value = float(fields[key].removesuffix("s"))
                    if not math.isfinite(value) or value < 0:
                        raise ValueError("invalid stage duration")
                    stages[key] = value
            measured_cpu = cpu(fields)
            resume = None
            if any(key in fields for key in ("resume-checks", "resume-hits", "resume-checked-bytes")):
                checks, hits, checked = (int(fields[key]) for key in
                                        ("resume-checks", "resume-hits", "resume-checked-bytes"))
                if checks < 0 or hits < 0 or hits > checks or checked < 0:
                    raise ValueError("invalid resume measurement")
                resume = {"checks": checks, "hits": hits, "checked_bytes": checked}
        except (KeyError, ValueError) as error:
            # Never echo the raw log line: surrounding logs may contain tokens.
            raise ValueError(f"invalid timing record at line {line_number}") from error
        rows.append({"depot": depot, "fetched_bytes": fetched, "chunk_phase_seconds": wall,
                     "retries": retries, "stage_seconds": stages, "process_cpu": measured_cpu, "resume": resume})
    if not rows and not installs:
        raise ValueError("no depot or install timing records")
    if len({row["depot"] for row in rows}) != len(rows):
        raise ValueError("repeated depot IDs; supply a log containing one install trial")
    fetched = sum(row["fetched_bytes"] for row in rows)
    # Fully resumed depots do not provide a network throughput sample.
    seconds = sum(row["chunk_phase_seconds"] for row in rows if row["fetched_bytes"] > 0)
    complete = all(row["completed"] for row in installs) if installs else None
    return {"depots": rows, "install_measurements": installs, "install_completed": complete,
            "fetched_bytes": fetched, "chunk_phase_seconds": seconds,
            "payload_mib_per_second": fetched / seconds / 1048576 if seconds and complete is not False else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", type=Path)
    parser.add_argument("--control", type=Path,
                        help='JSON array of native URLSession trials: [{"bytes": 104857600, "seconds": 10}]')
    args = parser.parse_args()
    try:
        trials = [trial(path) for path in args.logs]
        rates = [entry["payload_mib_per_second"] for entry in trials if entry["payload_mib_per_second"] is not None]
        report = {"metric": "downloaded payload / completed depot chunk-phase wall time",
                  "trials": trials, "measured_trials": len(rates),
                  "median_payload_mib_per_second": statistics.median(rates) if rates else None,
                  "limitations": ["Excludes manifest acquisition, local resume checks and finalization.",
                                  "Payload includes retried responses; this is not useful installed-byte throughput.",
                                  "Aborted depots lack completion records; report those failures separately.",
                                  "Stage durations overlap across concurrent chunks.",
                                  "Process CPU includes other work in Madeira; average cores can exceed one.",
                                  "Resume SHA-1 is a substage of the total resume check duration.",
                                  "Incomplete install trials with summaries are excluded from rate medians.",
                                  "Compare matching workloads on the same phone, network and CDN."]}
        if args.control:
            controls = json.loads(args.control.read_text(encoding="utf-8"))
            if not isinstance(controls, list) or not controls:
                raise ValueError("control must be a nonempty JSON array")
            control_rates = [positive(row["bytes"], "control bytes") /
                             positive(row["seconds"], "control seconds") / 1048576 for row in controls]
            median = statistics.median(control_rates)
            ratio = statistics.median(rates) / median if rates else None
            report["control"] = {"measured_trials": len(control_rates), "median_mib_per_second": median,
                                 "payload_rate_ratio": ratio, "target_ratio": 0.7,
                                 "payload_rate_target_met": ratio >= 0.7 if ratio is not None else None}
        print(json.dumps(report, indent=2, allow_nan=False))
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(2, f"Cannot summarize measurements: {error}\n")


if __name__ == "__main__":
    main()
