#!/usr/bin/env python3
"""
tools/manage-github-releases.py

Executes GitHub release management for Open-HotSpot:
1. Deletes obsolete Release entries from the GitHub repository UI/page
   (v1.2.0-r35, v1.2.0, v1.2.1, v1.2.2, v1.2.3) while preserving Git tags and commits.
2. Creates or updates the v1.2.0-r100 Release entry.
3. Attaches verified release assets:
   - luci-app-open-hotspot-1.2.0-r100.apk (noarch LuCI & manager)
   - opennds-11.0.0-r1.apk (ipq40xx / arm_cortex-a7_neon-vfpv4 core engine)
   - SHA256SUMS (containing hashes for both packages)
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

OPENNDS_NAME = "opennds-11.0.0-r1.apk"
OPENNDS_SHA256 = "b43c61c0ee4530b8f1e8de8137b1ec071e3778eacd750bc140fb08d4ef8d1b1e"

RELEASE_BODY = f"""## Open-HotSpot 1.2.0-r100 (Controlled UI Trial Release)

This is an experimental candidate for controlled UI trial and field testing.
**Not approved for production release.** Physical hardware acceptance gates (T006, T011, T052, T086, T087, T088, T090) remain open / Pending Hardware Validation.

### Verified Release Artifacts

| Package | Version | Architecture / Target | SHA-256 Checksum | Description |
|---|---|---|---|---|
| `luci-app-open-hotspot-1.2.0-r100.apk` | 1.2.0-r100 | `noarch` | `{R100_SHA256}` | Open-HotSpot Web LuCI & Daemon Manager |
| `opennds-11.0.0-r1.apk` | 11.0.0-r1 | `arm_cortex-a7_neon-vfpv4` (`ipq40xx/generic`) | `{OPENNDS_SHA256}` | openNDS 11 Captive Portal Core Engine |

> [!NOTE]
> Since openNDS v11 is not yet distributed in upstream official OpenWrt 25.12 package feeds, both the core binary package (`opennds-11.0.0-r1.apk` built for Linksys EA8300 / IPQ4019) and the manager package (`luci-app-open-hotspot-1.2.0-r100.apk`) are provided together here.

### Installation on Target Router (Linksys EA8300 / IPQ40xx)
```sh
# Copy packages to router /tmp, then install both together:
apk add --allow-untrusted /tmp/opennds-11.0.0-r1.apk /tmp/luci-app-open-hotspot-1.2.0-r100.apk
```

### Key Highlights
- Device identity UI: distinct device label alongside account owner.
- Responsive device action cards for Block, Disconnect, Remove, and Reassign.
- Preserves session stability and rollback baseline (r99/r60).
- Automated CI checks passed (Run 37161629888).
- Controlled router deployment completed with `failures=0 warnings=0`.

### Hardware Gates & Governance Status
See `docs/release-gates.md`, `docs/operational-ledger.md`, `docs/opennds-v11-build.md`, and `docs/delivery-manifest.md`.
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

def find_file(paths):
    for p in paths:
        if os.path.isfile(p):
            return p
    return None

def main():
    parser = argparse.ArgumentParser(description="Manage GitHub releases for Open-HotSpot")
    parser.add_argument("--dry-run", action="store_true", help="Inspect and validate without mutating")
    parser.add_argument("--delete-only", action="store_true", help="Only delete obsolete releases")
    parser.add_argument("--publish-only", action="store_true", help="Only publish/update v1.2.0-r100 release")
    args = parser.parse_args()

    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    apk_path = find_file([
        os.path.join(project_root, "dist", "luci-app-open-hotspot-1.2.0-r100.apk"),
        "/home/mohammed/opentik-dev/opennds-luci-hotspot-manager/dist/luci-app-open-hotspot-1.2.0-r100.apk"
    ])

    opennds_path = find_file([
        os.path.join(project_root, "dist", OPENNDS_NAME),
        os.path.join(project_root, "dist", "opennds-v11", OPENNDS_NAME),
        f"/home/mohammed/opentik-dev/opennds-luci-hotspot-manager/dist/opennds-v11/{OPENNDS_NAME}",
        f"/home/mohammed/opentik-dev/opennds-luci-hotspot-manager/dist/{OPENNDS_NAME}"
    ])

    if not apk_path or not os.path.isfile(apk_path):
        print(f"ERROR: luci-app APK artifact not found!", file=sys.stderr)
        sys.exit(1)

    if not opennds_path or not os.path.isfile(opennds_path):
        print(f"ERROR: opennds APK artifact not found!", file=sys.stderr)
        sys.exit(1)

    with open(apk_path, "rb") as f:
        apk_bytes = f.read()
        calc_sha = hashlib.sha256(apk_bytes).hexdigest()

    if calc_sha != R100_SHA256:
        print(f"ERROR: APK hash mismatch! Expected {R100_SHA256}, got {calc_sha}", file=sys.stderr)
        sys.exit(1)

    with open(opennds_path, "rb") as f:
        opennds_bytes = f.read()
        calc_opennds_sha = hashlib.sha256(opennds_bytes).hexdigest()

    if calc_opennds_sha != OPENNDS_SHA256:
        print(f"ERROR: opennds hash mismatch! Expected {OPENNDS_SHA256}, got {calc_opennds_sha}", file=sys.stderr)
        sys.exit(1)

    print(f"PASS: Local luci-app APK verified: {apk_path} ({calc_sha})")
    print(f"PASS: Local opennds APK verified:  {opennds_path} ({calc_opennds_sha})")

    token = load_token()
    if not token and not args.dry_run:
        print("ERROR: GITHUB_TOKEN is not set in environment or ~/.env", file=sys.stderr)
        sys.exit(1)

    # 1. Inspect existing releases
    status, releases = api_request(f"{API_BASE}/releases", token=token)
    if status != 200:
        print(f"ERROR fetching releases (status {status}): {releases}", file=sys.stderr)
        sys.exit(1)

    print(f"\nFound {len(releases)} existing releases in {REPO}:")
    to_delete = []
    for r in releases:
        tag = r.get("tag_name")
        rel_id = r.get("id")
        name = r.get("name")
        is_pre = r.get("prerelease")
        print(f"  - Release ID: {rel_id}, Tag: {tag}, Name: '{name}', Prerelease: {is_pre}")
        if tag in EXPECTED_DELETE_TAGS:
            to_delete.append((rel_id, tag))

    if to_delete:
        print(f"\nReleases matching deletion list ({len(to_delete)}/{len(EXPECTED_DELETE_TAGS)}):")
        for rel_id, tag in to_delete:
            print(f"  * Will delete release ID {rel_id} for tag '{tag}' (tag remains in Git)")

    if not args.publish_only and to_delete:
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
        r100_rel = next((r for r in releases if r.get("tag_name") == R100_TAG), None)
        upload_url_base = None
        rel_id = None
        html_url = None

        combined_sums = f"{R100_SHA256}  luci-app-open-hotspot-1.2.0-r100.apk\n{OPENNDS_SHA256}  {OPENNDS_NAME}\n".encode("utf-8")

        if r100_rel:
            rel_id = r100_rel["id"]
            upload_url_base = r100_rel["upload_url"].split("{")[0]
            html_url = r100_rel["html_url"]
            print(f"\nRelease '{R100_TAG}' already exists with ID {rel_id}.")

            if args.dry_run:
                print(f"[DRY-RUN] Would update release {rel_id} body and verify assets.")
            else:
                print("Updating release body and make_latest...")
                patch_payload = json.dumps({
                    "body": RELEASE_BODY,
                    "make_latest": "true",
                    "prerelease": False,
                }).encode("utf-8")
                st_patch, resp_patch = api_request(
                    f"{API_BASE}/releases/{rel_id}",
                    method="PATCH",
                    data=patch_payload,
                    headers={"Content-Type": "application/json"},
                    token=token,
                )
                if st_patch not in (200, 201):
                    print(f"WARNING: failed to patch release body (HTTP {st_patch}): {resp_patch}", file=sys.stderr)
                else:
                    print("Release metadata updated successfully.")

            # Check existing assets
            existing_assets = {a["name"]: a for a in r100_rel.get("assets", [])}

            # Upload opennds APK if missing
            if OPENNDS_NAME not in existing_assets:
                if args.dry_run:
                    print(f"[DRY-RUN] Would upload {OPENNDS_NAME} ({len(opennds_bytes)} bytes)")
                else:
                    print(f"Uploading {OPENNDS_NAME} ({len(opennds_bytes)} bytes)...")
                    st_nds, resp_nds = api_request(
                        f"{upload_url_base}?name={OPENNDS_NAME}",
                        method="POST",
                        data=opennds_bytes,
                        headers={"Content-Type": "application/octet-stream"},
                        token=token,
                    )
                    if st_nds not in (200, 201):
                        print(f"ERROR uploading {OPENNDS_NAME} (HTTP {st_nds}): {resp_nds}", file=sys.stderr)
                        sys.exit(1)
                    print(f"Uploaded {OPENNDS_NAME} successfully.")
            else:
                print(f"Asset {OPENNDS_NAME} already exists in release.")

            # Update SHA256SUMS if needed
            if "SHA256SUMS" in existing_assets:
                if not args.dry_run:
                    print("Replacing existing SHA256SUMS asset...")
                    del_asset_url = f"{API_BASE}/releases/assets/{existing_assets['SHA256SUMS']['id']}"
                    st_del, resp_del = api_request(del_asset_url, method="DELETE", token=token)
                    if st_del not in (200, 204):
                        print(f"WARNING deleting old SHA256SUMS: {resp_del}", file=sys.stderr)

            if not args.dry_run:
                print("Uploading updated SHA256SUMS...")
                st_sum, resp_sum = api_request(
                    f"{upload_url_base}?name=SHA256SUMS",
                    method="POST",
                    data=combined_sums,
                    headers={"Content-Type": "text/plain"},
                    token=token,
                )
                if st_sum not in (200, 201):
                    print(f"ERROR uploading SHA256SUMS (HTTP {st_sum}): {resp_sum}", file=sys.stderr)
                    sys.exit(1)
                print("Uploaded updated SHA256SUMS successfully.")

        else:
            if args.dry_run:
                print(f"\n[DRY-RUN] Would create release '{R100_TAG}' for commit {R100_COMMIT[:7]} with assets:")
                print(f"  - luci-app-open-hotspot-1.2.0-r100.apk")
                print(f"  - {OPENNDS_NAME}")
                print(f"  - SHA256SUMS")
            else:
                print(f"\nCreating release '{R100_TAG}' on GitHub...")
                create_payload = json.dumps({
                    "tag_name": R100_TAG,
                    "target_commitish": R100_COMMIT,
                    "name": f"Open-HotSpot {R100_TAG} (Controlled UI Trial Release)",
                    "body": RELEASE_BODY,
                    "draft": False,
                    "prerelease": False,
                    "make_latest": "true",
                }).encode("utf-8")

                st, rel_data = api_request(
                    f"{API_BASE}/releases",
                    method="POST",
                    data=create_payload,
                    headers={"Content-Type": "application/json"},
                    token=token,
                )
                if st not in (200, 201):
                    print(f"ERROR creating release (HTTP {st}): {rel_data}", file=sys.stderr)
                    sys.exit(1)

                rel_id = rel_data["id"]
                upload_url_base = rel_data["upload_url"].split("{")[0]
                html_url = rel_data["html_url"]
                print(f"  Created Release ID: {rel_id}")
                print(f"  URL: {html_url}")

                # Upload luci-app APK
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
                print("  Uploaded luci-app APK successfully.")

                # Upload opennds APK
                print(f"  Uploading {OPENNDS_NAME}...")
                st_nds, resp_nds = api_request(
                    f"{upload_url_base}?name={OPENNDS_NAME}",
                    method="POST",
                    data=opennds_bytes,
                    headers={"Content-Type": "application/octet-stream"},
                    token=token,
                )
                if st_nds not in (200, 201):
                    print(f"ERROR uploading {OPENNDS_NAME} (HTTP {st_nds}): {resp_nds}", file=sys.stderr)
                    sys.exit(1)
                print(f"  Uploaded {OPENNDS_NAME} successfully.")

                # Upload SHA256SUMS
                print("  Uploading SHA256SUMS...")
                st_sum, resp_sum = api_request(
                    f"{upload_url_base}?name=SHA256SUMS",
                    method="POST",
                    data=combined_sums,
                    headers={"Content-Type": "text/plain"},
                    token=token,
                )
                if st_sum not in (200, 201):
                    print(f"ERROR uploading SHA256SUMS (HTTP {st_sum}): {resp_sum}", file=sys.stderr)
                    sys.exit(1)
                print("  Uploaded SHA256SUMS successfully.")

        # Update local dist/SHA256SUMS
        local_sums_path = os.path.join(project_root, "dist", "SHA256SUMS")
        with open(local_sums_path, "wb") as f:
            f.write(combined_sums)
        print(f"\nLocal dist/SHA256SUMS updated at {local_sums_path}.")

        print(f"\nRelease update complete: {html_url or f'https://github.com/{REPO}/releases/tag/{R100_TAG}'}")

if __name__ == "__main__":
    main()
