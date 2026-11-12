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
| **Flatpak** | `flatpak-builder` | Flathub | Planned |
| **AppImage** | `appimagetool` | Universal | ✅ (scripts/build_linux.sh) |
| **.deb** | `dpkg-deb` | Debian/Ubuntu | ✅ (scripts/build_linux.sh) |
| **.rpm** | `rpmbuild` | Fedora/RHEL | Planned |
| **Arch/AUR** | `makepkg` | Arch Linux | ✅ (scripts/release.sh) |
| **Snap** | `snapcraft` | Ubuntu Store | Planned |

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
    sources:
      - type: dir
        path: ../build/linux/x64/release/bundle
```

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
| **Chocolatey** | `.nuspec` + `choco pack` | `choco install lumen` | Planned |
| **Scoop** | Manifest JSON | `scoop install lumen` | Planned |
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

- **Mechanism**: Check GitHub Releases API on startup (background)
- **Download**: Platform-specific artifact (.dmg, .msix, .AppImage, .deb)
- **Install**: 
  - Linux: Flatpak/Snap auto-update, or `lumen self-update` (AppImage replace)
  - macOS: Sparkle framework (standard for Mac apps)
  - Windows: MSIX auto-update (Store) or custom (download + silent install)
- **Channel**: Stable / Beta / Nightly (configurable)

### Mobile

- **iOS**: App Store / TestFlight (standard)
- **Android**: Play Store / F-Droid (standard)

---

## 6. Platform Matrix Summary

| Feature | Linux | macOS | Windows | iOS | Android |
|---------|-------|-------|---------|-----|---------|
| **Native build** | ✅ | ✅ | ✅ | Planned | Planned |
| **Packaging** | Flatpak, AppImage, .deb, AUR | .dmg, Homebrew | MSIX, Chocolatey, Inno | IPA | AAB |
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
| 1 | Flatpak manifest + Flathub submission | Linux | 2d |
| 2 | .rpm packaging + COPR/OBS | Linux | 1d |
| 3 | Snapcraft.yaml + Snap Store | Linux | 1d |
| 4 | macOS notarization pipeline + entitlements | macOS | 3d |
| 5 | Homebrew formula + tap | macOS | 1d |
| 6 | MSIX packaging + Microsoft Store | Windows | 3d |
| 7 | Chocolatey/Scoop packages | Windows | 1d |
| 8 | Windows code signing cert + pipeline | Windows | 2d |
| 9 | Rust mobile targets + flutter_rust_bridge | Mobile | 5d |
| 10 | iOS app: biometric, keychain, share ext | iOS | 5d |
| 11 | Android app: biometric, keystore, share | Android | 5d |
| 12 | Mobile UI adaptations (nav, editor, graph) | Mobile | 5d |
| 13 | Auto-update: Sparkle (Mac), custom (Linux/Win) | Desktop | 3d |
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