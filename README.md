# 🌟 Lumen

**Lumen** is a modular, offline-first journaling engine designed for clarity, privacy, and expressive self-reflection. Built with a secure Rust core and a cross-platform Flutter UI, Lumen empowers users to write, reflect, and extend their journaling experience through plugins, templates, and encrypted provenance.

> *Illuminate your inner world. Write in light. Store in silence.*

---

## ✨ Features

- 🔐 **Encrypted by Default**  
  All entries are locally encrypted using AES-256 and Argon2. Your thoughts stay yours.

- 🧱 **Modular Architecture**  
  Core journaling logic is written in Rust, with clean separation from UI and plugins.

- 🧩 **Plugin Support**  
  Extend Lumen with templates, sync adapters, AI feedback, multi-author modes, and more.

- 🖥️ **Cross-Platform UI**  
  Flutter-powered interface for iOS, Android, macOS, Linux, Windows, and Web.

- 🧑‍💻 **Terminal UI (TUI)**  
  A fallback journaling interface with expressive feedback and clean CLI design.

- 🔄 **Import/Export Adapters**  
  Compatible with Day One, Obsidian, Journey, Diaro, and plaintext Markdown.

- 🐳 **Future Sync Support**  
  Optional Docker-hosted sync server with plugin-based adapters (GitHub, WebDAV, IPFS, etc.)

---

## 🧠 Philosophy

Lumen is designed for single-user journaling with deep customization, emotional intelligence, and provenance tracking. Plugins are treated as lenses—modular extensions that shape how your thoughts are captured, interpreted, and stored.

---

## 🚫 License

Lumen is licensed under the **Lumen Non-Commercial Software License v1.0**.

> This software is free for personal, educational, and research use only.  
> **Commercial use is strictly prohibited** without prior written consent.

See [`LICENSE.txt`](./LICENSE.txt) for full terms.

---

## 🛠️ Getting Started

```bash
# Clone the repo
git clone https://github.com/your-username/lumen.git
cd lumen

# Build the Rust core
cargo build --release

# Run the Flutter UI
flutter run
```

For TUI mode:
```bash
cargo run --bin lumen-cli
```

---

## 🔌 Plugin Development

Plugins are registered via manifest files and can extend Lumen’s capabilities.  
See [`docs/plugins.md`](./docs/plugins.md) for plugin API and lifecycle hooks.

---

## 📣 Contributing

We welcome contributions that align with Lumen’s non-commercial philosophy.  
Please read [`CONTRIBUTING.md`](./CONTRIBUTING.md) before submitting PRs.

---

## 📬 Contact

For commercial licensing inquiries or collaboration proposals:  
**Author**: Crazygiscool  
**Email**: [crazygiscool@proton.me](mailto:crazygiscool@proton.me)

---

## 🧭 Roadmap Highlights

- [x] Encrypted local storage with per-entry provenance  
- [x] Plugin registry and template engine  
- [ ] Docker sync server with CRDT support  
- [ ] GEORGE plugin for branded AI feedback  
- [ ] GitHub integration for commit journaling  
- [ ] Multi-author journaling plugin

---

## 🪞 Reflect Freely. Store Safely. Extend Endlessly.

Lumen isn’t just a journaling app—it’s a framework for expressive, secure, and modular thought.  
Let your ideas shine, and let your tools stay out of the way.
