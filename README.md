# Lumen

A private, offline-first journal. Write Markdown notes in an encrypted store,
import writing you already have, and keep everything on your own machine.

> *Illuminate your inner world. Write in light. Store in silence.*

## Features

- **Encrypted journal** — notes are Markdown files encrypted with AES-256-GCM;
  the per-store key is derived with Argon2id and a passphrase you choose.
- **Editor with Markdown preview** — list, create, edit, save, and delete notes
  in the desktop app.
- **Imports** — bring in a Stoic iOS export (folder or `.zip`), a Lumen JSON
  export, or a folder of Markdown files. Imports are re-encrypted on disk.
- **Plugins** — built-in word count/summary plugins run when you save; on-disk
  plugins can be installed and toggled from the Plugins screen.
- **Terminal UI** — browse, search, read, and edit the same encrypted journal
  without leaving the terminal.
- **No accounts, no network, no telemetry.**

## Install / build

Dependencies: Rust (stable), Flutter with Dart 3.9+, and the usual Linux desktop build
packages. The Makefile works on Linux, macOS, and Windows (Windows needs GNU
Make from Git Bash, MSYS2, or WSL).

```bash
make           # Build the Rust core + Flutter app, then run it
make dev       # Hot-reload dev mode
make tui       # Run the terminal UI
make build-linux / build-macos / build-windows
make help      # List all targets
```

On Linux, Lumen is also packaged on the AUR as `lumen-journal`.

## Using the app

1. Open **Journal** and choose a folder for the encrypted store (for example
   `~/Documents/lumen-journal`). Use **Create journal** the first time and
   **Unlock** afterwards.
2. Create a note or open today's entry; write Markdown and press **Save**.
3. Use **Import** to bring in an existing journal. The journal must be unlocked
   first; imported files land in the encrypted store and are never written in
   plaintext.
4. Manage built-in and on-disk plugins in **Plugins**.

The journal is a normal folder containing a `.lumen/journal.json` passphrase
container and encrypted `.md` files. Back it up like any other folder.

## Terminal UI

```bash
lumen --vault ~/Documents/lumen-journal            # interactive browser
lumen --vault ~/Documents/lumen-journal init       # create the journal
lumen --vault ~/Documents/lumen-journal list
lumen --vault ~/Documents/lumen-journal search tea
lumen --vault ~/Documents/lumen-journal today      # edit in $EDITOR
lumen --vault ~/Documents/lumen-journal streak
```

The passphrase can be supplied with `--password` or `LUMEN_PASSWORD`; otherwise
the TUI prompts for it. The vault path can also be set with `LUMEN_JOURNAL`.

## File structure

```
lumen/
 ├─ core/      # Rust library: vault encryption, importers, plugins, FFI
 ├─ tui/       # Rust terminal client (binary: lumen)
 ├─ ui/        # Flutter desktop app
 ├─ plugins/   # Example on-disk plugin
 ├─ scripts/   # Build + packaging scripts
 └─ docs/      # Plugin and Stoic export format notes
```

## Documentation

- Plugin manifests, hooks, and the C ABI: `docs/plugins.md`
- Stoic export layout used by the importer: `docs/stoic-export-format.md`

## License

Lumen is provided under the terms described in `LICENSE` / `LICENSE.txt`.
Personal, educational, and research use is permitted. Commercial use requires
prior written permission.

## Contributing

Contributions are welcome as long as they align with the project's
non-commercial terms. See `CONTRIBUTING.md` before submitting pull requests.

## Contact

**Author:** Crazygiscool
**Email:** [crazygiscool@proton.me](mailto:crazygiscool@proton.me)

## Reflect freely. Store safely.

Lumen is a secure, expressive foundation for private journaling — built to stay
fast, local, and yours.
