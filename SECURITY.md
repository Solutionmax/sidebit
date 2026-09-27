# Security

Do not publish access tokens or local agent configuration files in an issue.
For a security issue, use GitHub's private vulnerability reporting when enabled on the hosting repository.

Sidebit reads existing file-based CLI credentials only to request usage from the matching provider. It rejects redirects and does not log or persist credentials or responses. Session hooks persist only limited metadata; see README and docs/usage-sources.md. The journal stores counts, times and project folder names only.

This development build is ad-hoc signed, not notarized. Review source and build locally when evaluating an untrusted binary.
