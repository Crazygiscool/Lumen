# Phase 3: Cross-Platform Polish

**Goal**: First-class native experience on Linux, macOS, Windows, and mobile (iOS/Android) with proper packaging, distribution, and platform integration.

**Status**: 📋 Planned. Phases 1 and 2 are done; see
[Phase 3](phase3-cross-platform.md) for the plan and
[ROADMAP.md](ROADMAP.md) for where it starts.

---

## 1. Linux

### Packaging & Distribution

| Format | Tool | Target | Status |
|--------|------|--------|--------|
| **Flatpak** | `flatpak-builder` | Flathub | ✅ (packaging/flatpak/) |
| **AppImage** | `appimagetool` | Universal | ✅ (scripts/build_linux.sh) |
| **.deb** | `dpkg-deb` | Debian/Ubuntu | ✅ (scripts/build_linux.sh) |
| **.rpm** | `rpmbuild` | Fedora/RHEL | ✅ (scripts/build_linux.sh) |
| **Arch/AUR** | `makepkg` | Arch Linux | ✅ (scripts/release.sh) |
| **Snap** | `snapcraft` | Ubuntu Store | ✅ (packaging/snapcraft.yaml) |

### Flatpak Manifest (`packaging/flatpak/io.github.Crazygiscool.Lumen.yml`)

```yaml
app-id: io.github.Crazygiscool.Lumen
runtime: org.freedesktop.Platform
runtime-version: '23.08'
sdk: org.freedesktop.Sdk
command: lumen
finish-args:
  - --share=network          # Syncthing
  - --filesystem=home        # Journal access
  - --filesystem=xdg-config/lumen:rw
  - --filesystem=xdg-data/lumen:rw
  - --device=all             # Hardware keys (YubiKey)
  - --talk-name=org.freedesktop.secrets  # Keyring
modules:
  - name: lumen
    buildsystem: simple
    build-commands:
      - cp -r bundle/* /app/
      - install -Dm755 lumen /app/bin/lumen
      - install -Dm755 lumen-cli /app/bin/lumen-cli
      - install -Dm644 lumen.desktop /app/share/applications/lumen.desktop
      - install -Dm644 lumen.png /app/share/icons/hicolor/1024x1024/apps/lumen.png
    sources:
      - type: dir
        path: ../build/linux/x64/release/bundle
      - type: file
        path: scripts/lumen.desktop
        dest: lumen.desktop
      - type: file
        path: ui/lib/assets/lumen_logo.png
        dest: lumen.png
```

Build locally:
```
flatpak-builder --user --install --repo=flatpak-repo \
  packaging/flatpak/io.github.Crazygiscool.Lumen.yml
```

### Flathub Submission

1. Fork the [flathub](https://github.com/flathub/flathub) repository
2. Add `packaging/flatpak/io.github.Crazygiscool.Lumen.yml` as a new app manifest
3. Add the app metadata file `io.github.Crazygiscool.Lumen.metainfo.xml`
4. Submit a pull request to flathub/flathub
5. Once merged, new Lumen releases are built automatically on Flathub's CI

The manifest uses the `org.freedesktop.Platform` 23.08 runtime with the
finishing arguments needed for Syncthing networking, journal file access,
and libsecret keyring integration.

### COPR / OBS Build Services

RPMs can be built automatically for Fedora (COPR) and openSUSE (OBS)
without maintaining build infrastructure:

**COPR** (`copr.fedoraproject.org`):
1. Create a COPR project at copr.fedoraproject.org
2. Enable the `lumen-core` and `lumen` chroots (e.g. `epel-9-x86_64`,
   `fedora-40-x86_64`, `fedora-rawhide-x86_64`)
3. Upload `packaging/lumen.spec` and the source tarball produced by
   `scripts/build_linux.sh` (`lumen-<version>.tar.gz`)
4. COPR builds the SRPM and RPMs for each enabled chroot

**OBS** (Open Build Service, `build.opensuse.org`):
1. Create an OBS project for Lumen
2. Add `packaging/lumen.spec` and the source files (`lumen.desktop`,
   `lumen_logo.png`, `LICENSE`, and the prebuilt bundle tarball)
3. OBS builds RPMs for openSUSE Leap, Tumbleweed, and SLE targets

Both services rebuild on every source change, so new Lumen releases are
automatically packaged for Fedora and openSUSE users.

### Snap Store

Snaps are built automatically for Ubuntu and other snap-enabled distros
without maintaining build infrastructure:

**Snap Store** (`snapcraft.io`):
1. Create a snap name at snapcraft.io (the name `lumen` is reserved on first
   push)
2. Push `packaging/snapcraft.yaml` and build the snap:
   ```
   snapcraft login
   snapcraft
   snapcraft upload --release=edge lumen_*.snap
   ```
3. The snap builds on Snapcraft's build farm for `amd64`, `arm64`,
   `armhf`, and `i386`
4. Promote to the `stable` channel once tested:
   ```
   snapcraft release lumen <revision> stable
   ```

The snap uses strict confinement with the `home`, `network`, `wayland`,
`x11`, `unity7`, `desktop`, `desktop-legacy`, `gsettings`, and `libsecret`
plugs. The Rust FFI library (`liblumen_core.so`) and the TUI binary
(`lumen-cli`) are packaged alongside the Flutter bundle.

Both COPR/OBS and the Snap Store rebuild on every source change, so new
Lumen releases are automatically packaged for Fedora, openSUSE, and Ubuntu
users.

### Wayland Support

- Flutter 3.19+ has native Wayland backend
- Set `GDK_BACKEND=wayland` in Flatpak finish-args
- Test: fractional scaling, touchpad gestures, IME

### System Integration

- **Desktop entry**: `scripts/lumen.desktop` (already exists)
- **MIME type**: `application/x-lumen-journal` for `.lumen` folders
- **File association**: Right-click `.lumen` folder → "Open with Lumen"
- **System keyring**: `libsecret` for WebDAV passwords
- **Hardware keys**: `pcscd` for YubiKey/PIV support

---

## 2. macOS

### Packaging & Distribution

| Format | Tool | Target | Status |
|--------|------|--------|--------|
| **Notarized .dmg** | `create-dmg` + `codesign` + `notarytool` | Direct download | Planned |
| **Homebrew** | `brew tap` + formula | `brew install lumen` | Planned |
| **Mac App Store** | Xcode + App Store Connect | MAS | Not planned (sandbox conflicts) |

### Build Pipeline (`scripts/build_macos.sh`)

```bash
#!/usr/bin/env bash
# Steps:
# 1. cargo build --release --locked
# 2. cp target/release/liblumen_core.dylib ui/macos/Frameworks/
# 3. cd ui && flutter build macos --release
# 4. codesign --deep --force --verify --verbose \
#      --sign "Developer ID Application: Crazygiscool (TEAM_ID)" \
#      --options runtime \
#      --entitlements Lumen.entitlements \
#      build/macos/Build/Products/Release/Lumen.app
# 5. create-dmg --identity "Developer ID Application: ..." \
#      --notarize --staple Lumen.dmg build/macos/Build/Products/Release/Lumen.app
# 6. xcrun notarytool submit Lumen.dmg --apple-id ... --team-id ... --wait
# 7. xcrun stapler staple Lumen.dmg
```

### Entitlements (`ui/macos/Runner/Lumen.entitlements`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>  <!-- Syncthing -->
    <key>com.apple.security.device.usb</key>
    <true/>  <!-- YubiKey -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>  <!-- Keychain access -->
</dict>
</dict>
</plist>
```

### macOS-Specific Features

- **Keychain integration**: Store WebDAV creds in Keychain (via `security` CLI / `keyring` crate)
- **Touch Bar**: Quick actions (new note, search, today) — optional
- **Menu bar app**: Optional menubar-only mode for quick capture
- **Universal binary**: Build both `x86_64` + `arm64` (Flutter supports this)

---

## 3. Windows

### Packaging & Distribution

| Format | Tool | Target | Status |
|--------|------|--------|--------|
| **MSIX** | `msix-packaging-tool` / `make-msix` | Microsoft Store / winget | Planned |
| **Chocolatey** | `.nuspec` + `choco pack` | `choco install lumen` | ✅ (packaging/chocolatey/) |
| **Scoop** | Manifest JSON | `scoop install lumen` | ✅ (packaging/scoop/) |
| **Installer** | `Inno Setup` (`scripts/lumen.iss`) | Direct download | ✅ (scripts/build_windows.sh) |

### Build Pipeline (`scripts/build_windows.sh`)

```bash
#!/usr/bin/env bash
# Run in Git Bash / MSYS2 / WSL
# 1. cargo build --release --locked --target x86_64-pc-windows-gnu
# 2. cp target/x86_64-pc-windows-gnu/release/lumen_core.dll ui/windows/
# 3. cd ui && flutter build windows --release
# 4. ./scripts/lumen.iss (Inno Setup compiler) → Lumen-Setup.exe
# 5. Sign with signtool (if cert available)
```

### MSIX Manifest (`packaging/msix/AppxManifest.xml`)

```xml
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities">
  <Identity Name="Crazygiscool.Lumen" Publisher="CN=Crazygiscool" Version="3.2.1.0" />
  <Properties>
    <DisplayName>Lumen</DisplayName>
    <PublisherDisplayName>Crazygiscool</PublisherDisplayName>
    <Description>Private encrypted journal</Description>
    <Logo>Assets/StoreLogo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="en-us" />
  </Resources>
  <Applications>
    <Application Id="Lumen" Executable="Lumen.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="Lumen" Square150x150Logo="Assets/Square150x150Logo.png"
                          Square44x44Logo="Assets/Square44x44Logo.png" BackgroundColor="#1a1a1a">
        <uap:DefaultTile Wide310x150Logo="Assets/Wide310x150Logo.png" />
      </uap:VisualElements>
      <Extensions>
        <uap:Extension Category="windows.fileTypeAssociation">
          <uap:FileTypeAssociation Name="lumen-journal">
            <uap:SupportedFileTypes>
              <uap:FileType>.lumen</uap:FileType>
            </uap:SupportedFileTypes>
          </uap:FileTypeAssociation>
        </uap:Extension>
      </Extensions>
    </Application>
  </Applications>
  <Capabilities>
    <Capability Name="internetClient" />          <!-- Syncthing -->
    <Capability Name="documentsLibrary" />        <!-- Journal access -->
    <rescap:Capability Name="runFullTrust" />     <!-- Rust binary -->
    <rescap:Capability Name="packageManagement" /> <!-- Self-update -->
  </Capabilities>
</Package>
```

### Microsoft Store Submission

1. Create a developer account at partner.microsoft.com
2. Package the Inno Setup installer (`scripts/build_windows.sh` produces `Lumen-windows-vX.Y.Z-setup.exe`)
3. Create an MSIX package using `make-msix` or `msix-packaging-tool` with `packaging/msix/AppxManifest.xml`
4. Submit to the Microsoft Store for certification
5. Once published, `msix` and `winget install lumen` are available

The manifest requests `internetClient` (Syncthing), `documentsLibrary` (journal access), `runFullTrust` (Rust binary), and `packageManagement` (self-update) capabilities.

### Chocolatey (`packaging/chocolatey/`)

```xml
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
  <metadata>
    <id>lumen</id>
    <title>Lumen</title>
    <version>3.2.3</version>
    <authors>Crazygiscool</authors>
    <projectUrl>https://github.com/Crazygiscool/Lumen</projectUrl>
    <license type="expression">LicenseRef-LumenNC</license>
    <tags>journal markdown encrypted notes privacy sync webdav syncthing</tags>
    <summary>Private, encrypted Markdown journal</summary>
    <description>
      Lumen is an offline-first, encrypted personal journal with Markdown editing,
      Wikilinks, backlinks, full-text search, and a terminal client. Notes are
      encrypted with AES-256-GCM and synced peer-to-peer via Syncthing or WebDAV.
    </description>
  </metadata>
  <files>
    <file src="tools\**" target="tools" />
  </files>
</package>
```

1. Create a Chocolatey account at chocolatey.org
2. Submit `packaging/chocolatey/lumen.nuspec` and `tools/chocolateyInstall.ps1`
3. Once approved, `choco install lumen` installs the Inno Setup installer

### Scoop (`packaging/scoop/`)

```json
{
  "version": "3.2.3",
  "description": "Private, encrypted Markdown journal",
  "homepage": "https://github.com/Crazygiscool/Lumen",
  "license": "Lumen Non-Commercial License v1.0",
  "architecture": {
    "64bit": {
      "url": "https://github.com/Crazygiscool/Lumen/releases/download/v3.2.3/Lumen-windows-v3.2.3-portable.zip",
      "hash": "REPLACE_WITH_ACTUAL_HASH"
    }
  },
  "bin": ["lumen.exe", "lumen-cli.exe"],
  "shortcuts": [["lumen.exe", "Lumen"]],
  "checkver": { "github": "https://github.com/Crazygiscool/Lumen" },
  "autoupdate": {
    "architecture": {
      "64bit": {
        "url": "https://github.com/Crazygiscool/Lumen/releases/download/v$version/Lumen-windows-v$version-portable.zip",
        "hash": { "url": "...$version...portable.zip.sha256" }
      }
    }
  }
}
```

1. Fork a Scoop bucket (or create `lumen-bucket`)
2. Add `packaging/scoop/lumen.json` as the app manifest
3. Once merged, `scoop install lumen` installs the portable zip

### Windows-Specific Features

- **Credential Manager**: Store WebDAV passwords via `cmdkey` / Windows Credential Manager
- **Windows Hello**: Biometric unlock (face/fingerprint/PIN) via `windows-rs`
- **WSL integration**: `lumen` CLI works in WSL, accesses same journal
- **Portable mode**: Run from USB without install (AppImage equivalent)
- **Auto-start**: Optional background sync service

---

## 4. Mobile (iOS / Android)

### Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Flutter Mobile App                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ UI (Dart)   │──│ FFI (Dart)  │──│ lumen_core  │         │
│  │ Reuse 85%   │  │ ffi.dart    │  │ (Rust cdylib)         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                             │
│  Platform Channels for:                                     │
│  - Biometric auth (FaceID / Fingerprint / Windows Hello)   │
│  - Background sync (WorkManager / BGAppRefresh)            │
│  - Share extension (Save to Lumen)                         │
│  - File picker (iOS: UIDocumentPicker / Android: SAF)      │
└────────────────────────────────────────────────────────────┘
```

### Rust for Mobile

- **Target**: `aarch64-apple-ios`, `x86_64-apple-ios` (simulator), `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`
- **Build**: `cargo lipo` (iOS) / `cargo ndk` (Android) via `flutter_rust_bridge` or manual
- **FFL**: `flutter_rust_bridge` generates Dart bindings from Rust — cleaner than manual `dart:ffi`

### iOS Specifics

| Feature | Implementation |
|---------|----------------|
| **Biometric unlock** | `LocalAuthentication` framework → platform channel |
| **Background sync** | `BGAppRefreshTask` + Syncthing iOS (limited) / WebDAV |
| **Share extension** | "Save to Lumen" from Safari, Notes, etc. |
| **File import** | `UIDocumentPickerViewController` for .zip/.json/.md |
| **Keychain** | Store passphrase (optional) + WebDAV creds |
| **App Sandbox** | Journal in `Application Support/Lumen/` |

### Android Specifics

| Feature | Implementation |
|---------|----------------|
| **Biometric unlock** | `BiometricPrompt` API → platform channel |
| **Background sync** | `WorkManager` + Syncthing-Fork (foreground service) |
| **Share target** | `<intent-filter>` for `text/plain`, `text/markdown` |
| **File import** | Storage Access Framework (SAF) for .zip/.json/.md |
| **Keystore** | Android Keystore for passphrase + WebDAV creds |
| **Scoped storage** | Journal in app-specific dir or user-picked via SAF |

### Flutter Mobile UI Adaptations

- **Navigation**: Bottom navigation bar (Journal, Search, Graph, Plugins, Settings)
- **Editor**: Full-screen, toolbar bottom, swipe gestures
- **Graph**: Touch-optimized (pinch zoom, drag pan)
- **Sync**: Pull-to-refresh, background indicator
- **Themes**: System dark/light follow, AMOLED black

### Build & Distribution

| Platform | Tool | Output |
|----------|------|--------|
| **iOS** | `flutter build ipa` + `xcodebuild` | `.ipa` → TestFlight / App Store |
| **Android** | `flutter build appbundle` | `.aab` → Play Store |
| **F-Droid** | `fdroidserver` | Open source repo |

**Note**: App Store review may flag encryption — prepare export compliance docs (CCATS / self-classification).

---

## 5. Auto-Update

### Desktop (All Platforms)

- **Mechanism**: Check GitHub Releases API via `kb.auto_update.check` FFI method
- **Download**: Platform-specific artifact via `kb.auto_update.download` FFI method
- **Install**: Apply via `kb.auto_update.apply` FFI method, replacing the running executable
- **CLI**: `lumen auto-update` checks for updates; `lumen auto-update apply` downloads and installs
- **Channel**: Stable / Beta / Nightly (configurable via GitHub releases)

Implementation: `core/src/auto_update.rs` with FFI methods `kb.auto_update.check`, `kb.auto_update.download`, `kb.auto_update.apply`.

The update flow queries `https://api.github.com/repos/Crazygiscool/Lumen/releases/latest`, finds the platform-specific asset, downloads it to a temp file, verifies the byte count, and replaces the running executable (Windows stages the update next to the executable due to file locking).

### Mobile

- **iOS**: App Store / TestFlight (standard)
- **Android**: Play Store / F-Droid (standard)

---

## 6. Platform Matrix Summary

| Feature | Linux | macOS | Windows | iOS | Android |
|---------|-------|-------|---------|-----|---------|
| **Native build** | ✅ | ✅ | ✅ | Planned | Planned |
| **Packaging** | Flatpak, AppImage, .deb, .rpm, Snap, AUR | .dmg, Homebrew | MSIX, Chocolatey, Inno | IPA | AAB |
| **Wayland** | ✅ | N/A | N/A | N/A | N/A |
| **Notarized** | N/A | ✅ | N/A | N/A | N/A |
| **Code signed** | N/A | ✅ | Planned | ✅ | ✅ |
| **Keyring/Keystore** | libsecret | Keychain | Credential Manager | Keychain | Android Keystore |
| **Hardware keys** | pcscd/CCID | CryptoTokenKit | Windows Hello | Secure Enclave | StrongBox/TEE |
| **Biometric unlock** | N/A | Touch ID | Windows Hello | Face ID/Touch ID | Fingerprint/Face |
| **Background sync** | systemd/user | launchd | Task Scheduler | BGAppRefresh | WorkManager |
| **Share extension** | N/A | Services | Share contract | Share Extension | Intent Filter |
| **Auto-update** | Flatpak/Snap | Sparkle | MSIX / custom | App Store | Play Store |

---

## Task Breakdown

| # | Task | Platform | Est. |
|---|------|----------|------|
| 1 | ✅ Flatpak manifest + Flathub submission | Linux | 2d |
| 2 | ✅ .rpm packaging + COPR/OBS | Linux | 1d |
| 3 | ✅ Snapcraft.yaml + Snap Store | Linux | 1d |
| 4 | macOS notarization pipeline + entitlements | macOS | 3d |
| 5 | Homebrew formula + tap | macOS | 1d |
| 6 | ✅ MSIX packaging + Microsoft Store | Windows | 3d |
| 7 | ✅ Chocolatey/Scoop packages | Windows | 1d |
| 8 | Windows code signing cert + pipeline | Windows | 2d |
| 9 | ✅ Rust mobile targets in CI | Mobile | 5d |
| 10 | iOS app: biometric, keychain, share ext | iOS | 5d |
| 11 | Android app: biometric, keystore, share | Android | 5d |
| 12 | Mobile UI adaptations (nav, editor, graph) | Mobile | 5d |
| 13 | ✅ Auto-update: GitHub Releases API + FFI + TUI | Desktop | 3d |
| 14 | CI/CD: GitHub Actions for all platforms | All | 3d |

**Total**: ~40 days (highly parallelizable by platform)

---

## Definition of Done

- [ ] Flatpak on Flathub, .deb/.rpm in repos, AppImage on GitHub Releases
- [ ] Notarized .dmg + Homebrew formula for macOS
- [ ] MSIX in Microsoft Store, Chocolatey/Scoop packages for Windows
- [ ] iOS app on TestFlight with biometric unlock, share extension
- [ ] Android app on Play Store (internal) with biometric unlock, share target
- [ ] Auto-update works on all desktop platforms
- [ ] GitHub Actions builds all 5 platforms on tag push
- [ ] Same journal opens on all 5 platforms (cross-platform compatibility)