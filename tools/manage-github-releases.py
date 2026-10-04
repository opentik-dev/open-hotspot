#!/usr/bin/env python3
"""
tools/manage-github-releases.py

Executes GitHub release management for Open-HotSpot:
1. Deletes obsolete Release entries from the GitHub repository UI/page
   (v1.2.0-r35, v1.2.0, v1.2.1, v1.2.2, v1.2.3) while preserving Git tags and commits.
2. Creates the v1.2.0-r100 Pre-release entry marked as experimental / controlled UI trial.
3. Attaches release assets:
   - luci-app-open-hotspot-1.2.0-r100.apk
   - SHA256SUMS (with canonical SHA-256 bcc0fffff8f71d8c8d60cf27c0310e1b75b3996afead7ba3f0708a78300ccf5a)
"""

import os
import sys
import json
import hashlib
import argparse
import urllib.request
import urllib.error

REPO = "opentik-dev/open-hotspot"
API_BASE = f"https://api.github.com/repos/{REPO}"
UPLOADS_BASE = f"https://uploads.github.com/repos/{REPO}"

EXPECTED_DELETE_TAGS = {
    "v1.2.0-r35",
    "v1.2.0",
    "v1.2.1",
    "v1.2.2",
    "v1.2.3",
}

R100_TAG = "v1.2.0-r100"
R100_COMMIT = "b14b3d57732633311f7229150ac4e83d8c328232"
R100_SHA256 = "bcc0fffff8f71d8c8d60cf27c0310e1b75b3996afead7ba3f0708a78300ccf5a"

RELEASE_BODY = f"""## Open-HotSpot 1.2.0-r100 (Controlled UI Trial Pre-release)

This is an experimental pre-release candidate for controlled UI trial and field testing.
**Not approved for production release.** Physical hardware acceptance gates (T006, T011, T052, T086, T087, T088, T090) remain open / Pending Hardware Validation.

### Verified Artifacts
- **Package:** `luci-app-open-hotspot-1.2.0-r100.apk`
- **SHA-256:** `{R100_SHA256}`
- **Architecture:** `noarch` (OpenWrt 25.12.5 `ipq40xx/generic` toolchain, openNDS 11.0.0)

### Key Highlights
- Device identity UI: distinct device label alongside account owner.
- Responsive device action cards for Block, Disconnect, Remove, and Reassign.
- Preserves session stability and rollback baseline (r99/r60).
- Automated CI checks passed (Run 37161629888).
- Controlled router deployment completed with `failures=0 warnings=0`.

### Hardware Gates & Governance Status
See `docs/release-gates.md`, `docs/operational-ledger.md`, and `docs/delivery-manifest.md`.
"""

def load_token():
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        return token.strip()
    env_file = os.path.expanduser("~/.env")
    if os.path.exists(env_file):
        with open(env_file, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("GITHUB_TOKEN="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
                if line.startswith("GH_TOKEN="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None

def api_request(url, method="GET", data=None, headers=None, token=None):
    hdrs = {
        "User-Agent": "open-hotspot-release-tool",
        "Accept": "application/vnd.github+json",
    }
    if token:
        hdrs["Authorization"] = f"Bearer {token}"
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read()
            if body:
                return resp.status, json.loads(body.decode("utf-8"))
            return resp.status, None
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return e.code, body

def main():
    parser = argparse.ArgumentParser(description="Manage GitHub releases for Open-HotSpot")
    parser.add_argument("--dry-run", action="store_true", help="Inspect and validate without mutating")
    parser.add_argument("--delete-only", action="store_true", help="Only delete the 5 obsolete releases")
    parser.add_argument("--publish-only", action="store_true", help="Only publish v1.2.0-r100 pre-release")
    args = parser.parse_args()

    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    apk_path = os.path.join(project_root, "dist", "luci-app-open-hotspot-1.2.0-r100.apk")

    if not os.path.isfile(apk_path):
        print(f"ERROR: Artifact not found at {apk_path}", file=sys.stderr)
        sys.exit(1)

    with open(apk_path, "rb") as f:
        apk_bytes = f.read()
        calc_sha = hashlib.sha256(apk_bytes).hexdigest()

    if calc_sha != R100_SHA256:
        print(f"ERROR: APK hash mismatch! Expected {R100_SHA256}, got {calc_sha}", file=sys.stderr)
        sys.exit(1)

    print(f"PASS: Local APK verified: {apk_path} ({calc_sha})")

    token = load_token()
    if not token and not args.dry_run:
        print("ERROR: GITHUB_TOKEN is not set in environment or ~/.env", file=sys.stderr)
        print("Please set GITHUB_TOKEN or use --dry-run", file=sys.stderr)
        sys.exit(1)

    # 1. Inspect existing releases
    status, releases = api_request(f"{API_BASE}/releases", token=token)
    if status != 200:
        print(f"ERROR fetching releases (status {status}): {releases}", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(releases)} existing releases in {REPO}:")
    to_delete = []
    for r in releases:
        tag = r.get("tag_name")
        rel_id = r.get("id")
        name = r.get("name")
        is_pre = r.get("prerelease")
        print(f"  - Release ID: {rel_id}, Tag: {tag}, Name: '{name}', Prerelease: {is_pre}")
        if tag in EXPECTED_DELETE_TAGS:
            to_delete.append((rel_id, tag))

    print(f"\nReleases matching deletion list ({len(to_delete)}/{len(EXPECTED_DELETE_TAGS)}):")
    for rel_id, tag in to_delete:
        print(f"  * Will delete release ID {rel_id} for tag '{tag}' (tag remains in Git)")

    if not args.publish_only:
        if args.dry_run:
            print("\n[DRY-RUN] Skipping actual release deletions.")
        else:
            print("\nExecuting release deletions...")
            for rel_id, tag in to_delete:
                del_url = f"{API_BASE}/releases/{rel_id}"
                st, resp = api_request(del_url, method="DELETE", token=token)
                if st in (204, 200):
                    print(f"  DELETED release {rel_id} for tag '{tag}' (HTTP {st})")
                else:
                    print(f"  ERROR deleting release {rel_id} (HTTP {st}): {resp}", file=sys.stderr)
                    sys.exit(1)
            print("All requested release entries deleted successfully.")

    if not args.delete_only:
        # Check if v1.2.0-r100 release already exists
        r100_rel = next((r for r in releases if r.get("tag_name") == R100_TAG), None)
        if r100_rel:
            print(f"\nPre-release '{R100_TAG}' already exists with ID {r100_rel['id']}.")
        else:
            if args.dry_run:
                print(f"\n[DRY-RUN] Would create pre-release '{R100_TAG}' for commit {R100_COMMIT[:7]} with assets:")
                print("  - luci-app-open-hotspot-1.2.0-r100.apk")
                print(f"  - SHA256SUMS ({R100_SHA256})")
            else:
                print(f"\nCreating pre-release '{R100_TAG}' on GitHub...")
                create_payload = json.dumps({
                    "tag_name": R100_TAG,
                    "target_commitish": R100_COMMIT,
                    "name": f"Open-HotSpot {R100_TAG} (Controlled UI Trial Pre-release)",
                    "body": RELEASE_BODY,
                    "draft": False,
                    "prerelease": True,
                }).encode("utf-8")

                st, rel_data = api_request(
                    f"{API_BASE}/releases",
                    method="POST",
                    data=create_payload,
                    headers={"Content-Type": "application/json"},
                    token=token,
                )
                if st not in (200, 201):
                    print(f"ERROR creating pre-release (HTTP {st}): {rel_data}", file=sys.stderr)
                    sys.exit(1)

                rel_id = rel_data["id"]
                upload_url_base = rel_data["upload_url"].split("{")[0]
                html_url = rel_data["html_url"]
                print(f"  Created Pre-release ID: {rel_id}")
                print(f"  URL: {html_url}")

                # Upload APK
                print(f"  Uploading {os.path.basename(apk_path)}...")
                st_apk, resp_apk = api_request(
                    f"{upload_url_base}?name=luci-app-open-hotspot-1.2.0-r100.apk",
                    method="POST",
                    data=apk_bytes,
                    headers={"Content-Type": "application/octet-stream"},
                    token=token,
                )
                if st_apk not in (200, 201):
                    print(f"ERROR uploading APK (HTTP {st_apk}): {resp_apk}", file=sys.stderr)
                    sys.exit(1)
                print("  Uploaded APK successfully.")

                # Upload SHA256SUMS
                sums_content = f"{R100_SHA256}  luci-app-open-hotspot-1.2.0-r100.apk\n".encode("utf-8")
                print("  Uploading SHA256SUMS...")
                st_sum, resp_sum = api_request(
                    f"{upload_url_base}?name=SHA256SUMS",
                    method="POST",
                    data=sums_content,
                    headers={"Content-Type": "text/plain"},
                    token=token,
                )
                if st_sum not in (200, 201):
                    print(f"ERROR uploading SHA256SUMS (HTTP {st_sum}): {resp_sum}", file=sys.stderr)
                    sys.exit(1)
                print("  Uploaded SHA256SUMS successfully.")
                print(f"\nPre-release publication complete: {html_url}")

if __name__ == "__main__":
    main()
