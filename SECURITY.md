# Security

## Reporting a vulnerability

Report vulnerabilities privately with GitHub’s **Report a vulnerability** button, in the **Security** tab of this
repository. Don’t open a public issue.

Include the Macfin version, your macOS version, and the steps to reproduce. You’ll get an answer within 7 days.

## Scope

Macfin stores one secret: the Jellyfin access token, in the login keychain. The app is sandboxed and only allowed
outgoing network connections. Issues in the Jellyfin server itself belong to the
[Jellyfin project](https://github.com/jellyfin/jellyfin/security).
