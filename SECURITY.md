# Security policy

## Supported versions

Security fixes are applied to the current `main` branch and the latest release
tag only. The release version is the package identity declared in
`starter-kit/Makefile` and follows the policy in `docs/release-policy.md`.

## Reporting a vulnerability

Please do not open a public issue for an unpatched vulnerability. Use a private
GitHub security advisory for this repository. If private advisories are not
available, contact the repository owners through the GitHub organization before
publishing technical details.

Include:

- affected release or commit SHA;
- OpenWrt/openNDS versions and router architecture;
- exact reproduction steps and expected/actual behavior;
- impact, including whether authentication can be bypassed or secrets are
  exposed;
- a minimal fix or mitigation if available.

Do not include real PINs, FAS keys, router credentials, client identifiers, or
backup archives. Redact IP addresses and MAC addresses unless they are required
to reproduce a routing defect.

We will acknowledge a report when received, reproduce it in an isolated target,
record the decision in the release-gate register, and publish a fix or
mitigation with a clear affected-version note.

## Security boundaries

The project treats openNDS as the traffic-enforcement engine. New identity
decisions fail closed, BinAuth must not call `ndsctl`, FAS keys remain target
local, and router/IoT administration must be isolated from the captive-client
network. These are release requirements, not optional hardening.
