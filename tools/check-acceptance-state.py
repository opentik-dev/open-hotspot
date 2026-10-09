#!/usr/bin/env python3
"""Verify the single release/acceptance state against source and task metadata."""

import argparse
import json
import re
import sys
from pathlib import Path


REQUIRED_GATES = ("T003", "T006", "T011", "T012", "T052", "T086", "T087", "T088", "T090")


def read_assignment(path: Path, key: str) -> str:
    match = re.search(rf"^{re.escape(key)}:=([^\r\n]+)$", path.read_text(), re.MULTILINE)
    if not match:
        raise ValueError(f"missing {key} in {path}")
    return match.group(1).strip()


def task_done_map(tasks: Path) -> dict[str, bool]:
    result: dict[str, bool] = {}
    for line in tasks.read_text().splitlines():
        match = re.match(r"^- \[([ x])\] \*\*(T\d+)(?:\s|\*)", line)
        if match:
            result[match.group(2)] = match.group(1) == "x"
    return result


def check(project: Path, release_mode: bool) -> list[str]:
    errors: list[str] = []
    state_path = project / "docs/acceptance-state.json"
    try:
        state = json.loads(state_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        return [f"acceptance-state-invalid: {exc}"]

    working = state.get("working_tree", {})
    if state.get("format_version") != 1:
        errors.append("acceptance-state-invalid-format-version")

    try:
        makefile = project / "starter-kit/Makefile"
        version = read_assignment(makefile, "PKG_VERSION")
        release = int(read_assignment(makefile, "PKG_RELEASE"))
        if working.get("version") != version:
            errors.append(f"version-mismatch: manifest={working.get('version')} makefile={version}")
        if working.get("release") != release:
            errors.append(f"release-mismatch: manifest={working.get('release')} makefile={release}")
        version_file = (project / "starter-kit/root/usr/lib/open-hotspot/open-hotspot.version").read_text().strip()
        if version_file != f"{version}-r{release}":
            errors.append(f"version-file-mismatch: expected={version}-r{release} actual={version_file}")
        db_version = int(re.search(
            r"^DB_SCHEMA_VERSION=(\d+)$",
            (project / "starter-kit/root/usr/lib/open-hotspot/db.sh").read_text(),
            re.MULTILINE,
        ).group(1))
        if working.get("schema_version") != db_version:
            errors.append(f"schema-mismatch: manifest={working.get('schema_version')} db={db_version}")
    except (OSError, ValueError, AttributeError) as exc:
        errors.append(f"source-metadata-invalid: {exc}")

    field = state.get("field_candidate", {})
    required_document_text = {
        "README.md": f"Open-HotSpot: {working.get('version')}-r{working.get('release')}",
        "docs/project-status.md": f"Open-HotSpot {working.get('version')}-r{working.get('release')}",
        "docs/current-state.md": f"Open-HotSpot r{working.get('release')}",
        "docs/release-policy.md": f"r{working.get('release')}",
        "docs/release-gates.md": f"r{field.get('release')}",
        "docs/delivery-manifest.md": f"luci-app-open-hotspot {working.get('version')}-r{field.get('release')}",
    }
    for relative_path, expected_text in required_document_text.items():
        try:
            if expected_text not in (project / relative_path).read_text():
                errors.append(f"document-state-mismatch: {relative_path} missing {expected_text!r}")
        except OSError as exc:
            errors.append(f"document-state-unreadable: {relative_path}: {exc}")

    tasks = task_done_map(project / "specs/001-open-hotspot/tasks.md")
    known_statuses = set(state.get("status_vocabulary", []))
    for gate in REQUIRED_GATES:
        gate_state = state.get("gates", {}).get(gate)
        if not gate_state:
            errors.append(f"missing-gate: {gate}")
            continue
        status = gate_state.get("status")
        if status not in known_statuses:
            errors.append(f"invalid-gate-status: {gate}={status}")
        accepted = status == "accepted"
        if tasks.get(gate) != accepted:
            errors.append(f"task-state-mismatch: {gate} task={'done' if tasks.get(gate) else 'open'} manifest={status}")
        if release_mode and not accepted:
            errors.append(f"release-gate-open: {gate} ({status})")

    if release_mode and not state.get("production_approved"):
        errors.append("release-not-production-approved")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", action="store_true", help="also require every release gate to be accepted")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    errors = check(args.project.resolve(), args.release)
    if errors:
        print("acceptance-state-failed", file=sys.stderr)
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("acceptance-state-ok" if not args.release else "release-gates-closed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
