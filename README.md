# 🌟 Lumen

**Lumen** is a secure, offline‑first journaling engine built with a Rust core and a cross‑platform Flutter UI. It focuses on privacy, clarity, and long‑term durability — giving you a fast, encrypted space to write without distractions.

> *Illuminate your inner world. Write in light. Store in silence.*

---

## ✨ Features

- 🔐 **Local Encryption**  
  Entries are encrypted using AES‑256 and Argon2. Nothing leaves your device.

- 🧱 **Rust Core Engine**  
  Handles encryption, storage, entry management, and provenance metadata.

- 🖥️ **Cross‑Platform UI**  
  Flutter interface for Linux and macOS (other platforms compile but are not yet polished).

- 🧑‍💻 **Terminal UI (TUI)**  
  A functional command‑line journaling interface for quick writing and reading.

- 📁 **Import/Export**  
  Export entries to plaintext Markdown. Import from plaintext and basic JSON.

- 🗂️ **Entry Metadata**  
  Each entry includes timestamps, edit history, and structured provenance.

- 🛠️ **Cross‑Platform Build Pipeline**  
  Automated builds for Linux and macOS, including Rust FFI and Flutter bundling.

---

## 🛠️ Installation

### **Linux (Arch / Manjaro / EndeavourOS)**  

Lumen is available on the AUR:

```bash
yay -S lumen-journal
```

Or build manually:

```bash
git clone https://github.com/your-username/lumen.git
cd lumen
./scripts/build_linux.sh
```

The resulting binary and desktop files will be placed in:

```txt
build/linux/
```

### **macOS**

```bash
git clone https://github.com/your-username/lumen.git
cd lumen
./scripts/build_macos.sh
```

The macOS `.app` bundle will appear in:

```txt
build/macos/
```

### **From Source (Rust + Flutter)**

```bash
# Rust core
cargo build --release

# Flutter UI
flutter pub get
flutter run
```

### **TUI Mode**

```bash
cargo run --bin lumen-cli
```

---

## 📦 File Structure

```
lumen/
 ├─ core/          # Rust engine (encryption, storage, provenance)
 ├─ ui/            # Flutter interface
 ├─ cli/           # Terminal UI
 ├─ scripts/       # Build + packaging scripts
 ├─ LICENSE        # License file
 └─ README.md
```

---

## 📚 Documentation

- Core architecture: `docs/core.md`  
- Storage format: `docs/storage.md`  
- TUI usage: `docs/tui.md`  

---

## 🚫 License

Lumen is provided under the terms described in `LICENSE` / `LICENSE.txt`.

Personal, educational, and research use is permitted.  
Commercial use requires prior written permission.

---

## 📣 Contributing

Contributions are welcome as long as they align with the project’s non‑commercial terms.  
See `CONTRIBUTING.md` before submitting pull requests.

---

## 📬 Contact

For questions or licensing inquiries:

**Author:** Crazygiscool  
**Email:** [crazygiscool@proton.me](mailto:crazygiscool@proton.me)

---

## 🪞 Reflect Freely. Store Safely.

Lumen is a secure, expressive foundation for private journaling — built to stay fast, local, and yours.
