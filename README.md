# Discord Proton Launcher

An unofficial Windows launcher that keeps Discord's Proton VPN split-tunneling
application path synchronized when Discord moves to a new versioned `app-*`
directory. Both editions also support optional Roblox path synchronization after
Roblox updates.

This project is not affiliated with Proton AG, Discord, Roblox Corporation, or Equicord. It edits an
internal Proton VPN settings file, so a future Proton VPN update may require a
compatibility update. A timestamped backup is created before every settings
change.

## Which edition should I use?

### Standard — recommended for most users

Use [`Standard`](./Standard) if you:

- use regular Discord; or
- use Equicord normally but do not modify or build its source code.

Equicord already handles normal Equicord updates. Standard manages Discord's
versioned executable path and Proton VPN synchronization, with optional Roblox
support.

### Developer-Equicord — custom forks only

Use [`Developer-Equicord`](./Developer-Equicord) only if you:

- modify Equicord source code;
- maintain a personal Equicord fork;
- build and inject Equicord from source; and
- want to rebase your custom commits onto the upstream Equicord repository.

This edition adds configurable upstream fetch/rebase, dependency installation,
build, injection repair, and the same Proton VPN path synchronization.

> If you are unsure, use Standard.

## Optional Roblox support

Both editions include `RobloxVpnSync.bat`. It selects the newest
`RobloxPlayerBeta.exe` under `%LocalAppData%\Roblox\Versions` using numeric
executable version metadata and adds or updates its Proton VPN entry. Split
tunneling must be enabled in inverse mode (only listed applications use VPN).

Run it after Roblox finishes updating, before joining a game. Use
`RobloxVpnSync.bat -WhatIf` for a read-only check. It does not launch Roblox or
watch for updates in the background. When a path changes, settings are backed up
and the Proton client is restarted if it was running.

Discord launchers also refresh an existing Roblox entry in Proton. An absent
Roblox installation does not prevent Discord synchronization.

### Which file should I run?

| What you use | File | Behavior |
| --- | --- | --- |
| Discord / regular Equicord | `Standard/DiscordLauncher.bat` | Starts Discord and refreshes its VPN path; also refreshes Roblox if already listed in Proton. |
| Custom Equicord fork | `Developer-Equicord/EquicordLauncher.bat` | Runs the developer workflow with the same VPN path synchronization. |
| Roblox only | `Standard/RobloxVpnSync.bat` | Adds or refreshes the Roblox VPN path; does not require or launch Discord. |

If you do not use Roblox, keep using your existing Discord launcher. Roblox is
not required, and the Discord launcher does not add it to Proton automatically.
Keep `RobloxVpnSync.bat` and `vpn_sync.ps1` together in the same package folder.
The standalone Roblox command does not require the developer tools either.

Version folders have hashed names. Selection uses the executable's numeric file
version, then the folder modification time to break ties; folders without
`RobloxPlayerBeta.exe` are skipped.

## Discord launcher requirements

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
