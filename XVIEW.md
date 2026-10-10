# xview: project notes

xview is Xavier's custom build of RustDesk 1.5.0 (remote desktop), locked down to work only over Tailscale. This file records what has been built, why, and what is still open, so any Claude Code session can pick up from here.

## Goal

- Full remote control of Xavier's Windows laptop (cursor, keyboard, everything) from his Android phone.
- Network: Tailscale only. No RustDesk relay servers, no cloud server of our own.
- Later: let a friend use Claude Code on the laptop. The friend has their own Claude account (sharing Xavier's login is against Anthropic's terms, so never set that up). The plan for the friend is a separate Windows user plus SSH over a shared Tailscale node, not xview, because xview shows the one physical screen.

## How it fits together

```
Phone (xview Android app)  --Tailscale 100.x-->  Laptop (xview, Windows service)
                                                   direct IP access, port 21118
                                                   IP whitelist = Tailscale ranges only
```

The phone types the laptop's Tailscale IP (100.x.y.z) where it would normally type a RustDesk ID. Connecting by ID goes through RustDesk's servers, arrives from a non-Tailscale address, and is refused with "Your ip is blocked by the peer". That refusal is the lock-down working.

## Repository

- GitHub: `Xaavi99/xview`, a fork of `rustdesk/rustdesk`. Claude GitHub app is installed on this repo only.
- `master`: untouched copy of upstream. Keep it clean so GitHub's "Sync fork" button works.
- `xview`: all xview changes. Based on upstream commit `001b0e9`.
  - `67c7d75` rename, Tailscale-only direct access, no auto-update
  - `6e1bbc2` Screen X icon, Android app and build
- `xview-check`: a throwaway branch with a one-off workflow that inspects the built APK (signature, manifest, alignment). Safe to delete.

To pick up upstream updates later: Sync fork on GitHub (updates `master`), then rebase or merge `xview` onto `master` and push.

## Code changes (all on the `xview` branch)

### 1. Built-in settings: `src/common.rs`

New function `apply_xview_settings()`, called as the first line of `load_custom_client()`. That is the same hook RustDesk uses for its paid custom clients, and it runs at the start of every process (GUI via `core_main` and `flutter_ffi::initialize`, the Windows service via `service.rs`), before any config path or service name is computed.

What it sets:

| Setting | Value | Why |
|---|---|---|
| `config::APP_NAME` | `xview` | Installer, Windows service, install folder, window title and tray all take their name from this at runtime |
| `OVERWRITE_SETTINGS["direct-server"]` | `Y` | Listen for direct IP connections (port 21118), which is how Tailscale connections arrive |
| `OVERWRITE_SETTINGS["whitelist"]` | `100.64.0.0/10,fd7a:115c:a1e0::/48` | Only Tailscale's IPv4 and IPv6 ranges may connect |
| `OVERWRITE_SETTINGS["allow-auto-update"]` | `N` | An update would replace xview with stock RustDesk |
| `OVERWRITE_LOCAL_SETTINGS["enable-check-update"]` | `N` | No "new version" prompts either |

"Overwrite" settings beat whatever is saved in the config file, and the settings screen shows them greyed out as locked.

Design notes:
- Deliberately not changed in `libs/hbb_common`: it is a git submodule, and editing it would mean forking a second repo.
- The whitelist works with the dual-stack listener because `server.rs` and `server/connection.rs` normalise IPv4-mapped addresses with `hbb_common::try_into_v4` before `check_whitelist()` runs.
- Verified before pushing by compiling the exact function against `hbb_common` and `base` in a scratch crate: settings applied, saved values can't override them, Tailscale IPs allowed, LAN and public IPs blocked.

### 2. Windows file properties: `flutter/windows/runner/Runner.rc`

`ProductName` is `xview`; `FileDescription` is `xview (based on RustDesk)`.

### 3. Icon: "Screen X"

A white monitor outline with an X, on teal `#0F766E`. Chosen over two other options (cursor X, xv monogram).

- Android: `flutter/android/app/src/main/res/mipmap-*/` `ic_launcher.png`, `ic_launcher_round.png`, `ic_launcher_foreground.png` (adaptive and themed icon layer) and `ic_stat_logo.png` (notification). Background colour in `values/ic_launcher_background.xml`.
- Windows: `flutter/windows/runner/resources/app_icon.ico` (16 to 256 px), `res/icon.ico`, `res/tray-icon.ico`.
- In-app logo: `flutter/assets/icon.svg`.
- They were generated from one SVG on a 108dp adaptive canvas (glyph inside the 66dp safe circle), rendered with Playwright Chromium, and packed into .ico with ImageMagick.

### 4. Android app identity

- `flutter/android/app/build.gradle`: `applicationId "com.xaavi99.xview"`. `namespace` stays `com.carriez.flutter_hbb`, so the Kotlin code is unchanged. The separate ID lets xview install alongside the stock RustDesk app.
- `AndroidManifest.xml` labels: `xview` and `xview Input` (the accessibility service). `values/strings.xml` `app_name` is `xview`.
- Checked: every provider authority and custom permission in the merged manifest is prefixed with `com.xaavi99.xview`, so nothing clashes with stock RustDesk.

### 5. Android signing

- Keystore: `flutter/android/app/xview-release.p12` (PKCS12, alias `xview`, RSA 4096, valid 100 years). It is committed, and protected by a password.
- The password is the repo secret `XVIEW_KEY_PASSWORD`. It is not written in this repo and must never be. Xavier has it saved; if it is lost, a new key means uninstalling and reinstalling the app once.
- Certificate SHA-256: `dd8036ebaca0ef97a396bdbd61d0c13cc222123bdc6242a83ce98782c1e6f582`
- If the secret is missing, the workflow falls back to a throwaway debug key and logs a warning. Updates then won't install over the top.

## Build workflows (`.github/workflows/`)

Both are trimmed copies of the matching jobs in upstream's `flutter-build.yml`, with the same pinned tool versions (Rust 1.75, Flutter 3.24.5, LLVM 15.0.6, vcpkg commit `9e593bb1`, NDK r28c). They run on every push to `xview`, and by hand from the Actions tab. Put `[skip ci]` in a commit message to skip them (useful for docs-only commits).

| Workflow | Output artifact | Notes |
|---|---|---|
| `xview-windows.yml` | `xview-windows-x64` containing `xview-1.5.0-x86_64.exe` | Self-extracting installer. Renames `rustdesk.exe` to `xview.exe` before packing, so it unpacks into its own folder. Printer driver left out on purpose. About 55 min cold, faster with cache. |
| `xview-android.yml` | `xview-android-arm64` containing `xview-1.5.0-arm64.apk` | arm64 only. About 35 min. |

The upstream workflows (`ci.yml`, `flutter-ci.yml`) only fire on pushes to `master`, which is why the work lives on the `xview` branch.

Last good builds:
- Windows with icon: run `38000949221`
- Android, signed with the xview key: run `38001863793`. The APK was inspected and verified with apksigner (v1 and v2), aapt and zipalign. Size 30,486,664 bytes, SHA-256 `1f039cebf78efaba80f63cc508df90642cea7a8322d9b32b144e31af844c16d7`.

### Downloading builds

Artifacts need a GitHub login and expire after 90 days. From PowerShell with the GitHub CLI:

```powershell
$repo = "Xaavi99/xview"; $dest = "$HOME\Downloads\xview"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
foreach ($b in @(@{wf="Build xview for Windows"; art="xview-windows-x64"},
                 @{wf="Build xview for Android"; art="xview-android-arm64"})) {
  $id = gh run list -R $repo -w $b.wf -b xview -s success -L 1 --json databaseId -q '.[0].databaseId'
  gh run download $id -R $repo -n $b.art -D $dest
}
```

## Setup on the devices

Laptop:
1. Install `xview-1.5.0-x86_64.exe` and choose **Install**, not Run, so it becomes a Windows service that works at the login screen. SmartScreen warns because the installer is unsigned: More info, then Run anyway.
2. Settings > Security: set a permanent password and turn on 2FA. Direct IP and whitelist show as locked, which is expected.
3. Tailscale installed with **Run unattended** on. Stop the laptop sleeping while plugged in.

Phone:
1. Tailscale on, same account.
2. xview APK installed. Play Protect warns "unknown developer"; that is expected for a self-built app.
3. Connect by typing the laptop's `100.x.y.z` Tailscale IP, not the xview ID.

## Status and open issues

- Builds: Windows and Android both build cleanly.
- Honor phone: the APK installs (after the Play Protect warning).
- First connection attempt was refused with "ip is blocked by the peer". Most likely the xview ID was used instead of the Tailscale IP. Retest with the 100.x IP; if it is still blocked, investigate how the connection is being routed.
- **Mi 11X Pro (MIUI): "App not installed" with no reason given.** The APK is verified valid, so it is the phone refusing. Suspected cause: MIUI's install scanner blocking an unknown-signed app with screen capture plus accessibility input (it looks like a remote-access trojan). Next steps: temporarily turn off "Scan before installing" in the MIUI Security app and Play Protect scanning, install from Mi File Manager, then turn both back on. Otherwise try turning off MIUI optimization, or install with `adb install -r` from the laptop to get the real `INSTALL_FAILED_...` code.
- Two people can connect to xview at once, but they share the one screen and one cursor. Windows 10/11 allows only one interactive desktop. For the friend, use SSH instead (below).

## Next steps

1. Confirm phone to laptop control over the Tailscale IP.
2. Fix the Mi install (see above).
3. Friend access for Claude Code (not started):
   - `net user friend * /add` (standard user, not admin)
   - `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`, then `Start-Service sshd` and `Set-Service sshd -StartupType Automatic`
   - `Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -RemoteAddress 100.64.0.0/10`
   - Share only the laptop with the friend in the Tailscale admin console (Machines > Share). Shared nodes are quarantined and can't reach the rest of the tailnet.
   - The friend runs `ssh friend@<laptop 100.x IP>`, installs Claude Code with `irm https://claude.ai/install.ps1 | iex`, and logs in with their own account. Switch to SSH keys and turn off password login once it works.
4. Optional: publish builds to a GitHub Releases page (plain links, no zip, no expiry).
5. Optional: delete the `xview-check` branch.

## Ground rules for future changes

- Work on the `xview` branch; keep `master` identical to upstream.
- Don't edit `libs/hbb_common` (submodule). Put xview behaviour in `apply_xview_settings()` or other main-repo code.
- Never commit the signing password or any other secret.
- RustDesk is AGPL-3.0. Using a modified build personally is fine; if xview is ever given to others, its source must be available too. The public fork covers that.
- Every push to `xview` starts both builds (about an hour of runner time). Use `[skip ci]` for docs-only commits.
- The repo's `AGENTS.md` (loaded by `CLAUDE.md`) has RustDesk's own coding rules. Follow them: small additive diffs, thin hooks, no refactors.
