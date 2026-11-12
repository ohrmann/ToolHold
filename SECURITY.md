# Security

Do not publish working credentials, private keys, personal data, internal endpoints or exploit details in issues, pull requests, screenshots or logs. Use synthetic, disposable input for reproductions.

If GitHub private vulnerability reporting is enabled for this repository, use its **Security → Report a vulnerability** form. A private reporting channel has not been verified or configured by this audit. If the form is unavailable, open only a minimal issue asking the maintainer for a private contact method; do not disclose vulnerability details there. No response time is guaranteed.

Include the affected revision/platform, impact, minimal reproduction and any safe proposed fix. If a credential was exposed, revoke or rotate it with its provider; deleting it from the current tree does not remove it from Git history or existing copies.

The app uses local, bounded processing and explicit copy/export. External preview resources require an explicit action. Clipboard, filesystem/provider retention and memory zeroization limitations are described in [README.md](README.md) and [PUBLIC_RELEASE_AUDIT.md](PUBLIC_RELEASE_AUDIT.md). A passing test suite is not an independent security certification.
