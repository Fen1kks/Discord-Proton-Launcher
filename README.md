# Discord Proton Launcher

An unofficial Windows launcher that keeps Discord's Proton VPN split-tunneling
application path synchronized when Discord moves to a new versioned `app-*`
directory.

This project is not affiliated with Proton AG, Discord, or Equicord. It edits an
internal Proton VPN settings file, so a future Proton VPN update may require a
compatibility update. A timestamped backup is created before every settings
change.

## Which edition should I use?

### Standard — recommended for most users

Use [`Standard`](./Standard) if you:

- use regular Discord; or
- use Equicord normally but do not modify or build its source code.

Equicord already handles normal Equicord updates. Standard only manages Discord's
versioned executable path and Proton VPN synchronization.

### Developer-Equicord — custom forks only

Use [`Developer-Equicord`](./Developer-Equicord) only if you:

- modify Equicord source code;
- maintain a personal Equicord fork;
- build and inject Equicord from source; and
- want to rebase your custom commits onto the upstream Equicord repository.

This edition adds configurable upstream fetch/rebase, dependency installation,
build, injection repair, and the same Proton VPN path synchronization.

> If you are unsure, use Standard.

## Requirements

- Windows 10 or 11
- Standard Discord desktop installation
- Proton VPN for Windows with Split Tunneling enabled in Include mode
- The current `app-*\Discord.exe` added to Proton VPN at least once

Developer-Equicord additionally requires Git, Node.js 22+, pnpm, and a local
Equicord Git fork with an upstream remote.

Turkish documentation: [`README.tr.md`](./README.tr.md)

## Privacy and safety

The scripts run locally and do not upload account data. Never attach Proton VPN
`UserSettings*.json` files or their backups to a GitHub issue: these files may
contain account and connection information. Logs can contain local Windows paths
and usernames, so redact them before sharing.
