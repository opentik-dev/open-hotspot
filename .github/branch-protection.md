# `main` branch protection

GitHub repository settings must enforce these rules. Git cannot configure them
through an SSH remote, so an organization owner must apply them in **Settings →
Branches → Add branch protection rule** for `main`:

- require a pull request before merging;
- require at least one approving review;
- dismiss stale approvals when new commits are pushed;
- require status checks before merging;
- require these checks: `Contract and unit checks` and `Build APK from source`;
- require branches to be up to date before merging;
- block force pushes and branch deletion;
- do not allow bypassing the rules for ordinary maintainers.

The equivalent GitHub CLI shape is shown for an authorized repository owner:

```sh
gh api --method PUT repos/opentik-dev/open-hotspot/branches/main/protection \
  -f required_status_checks='{"strict":true,"contexts":["Contract and unit checks","Build APK from source"]}' \
  -f enforce_admins=true \
  -f required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true}' \
  -f restrictions='null'
```

Verify the resulting rule from GitHub after applying it. This file is a
runbook, not a substitute for the server-side setting.
