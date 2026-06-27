# Terminal UI (TUI)

Lumen includes a terminal-based journaling client, `lumen-cli`, for quick reading, searching, and writing without leaving the terminal.

## Building

Build the TUI binary with Cargo:

```bash
cargo build --release --bin lumen-cli
```

The binary will be at `target/release/lumen-cli`. It links against the `lumen_core` library statically (`rlib`).

## Usage

```
lumen-cli [OPTIONS] [COMMAND]
```

### Options

| Flag | Description |
|------|-------------|
| `-d`, `--database <FILE>` | Path to the lumen.db file. Defaults to `~/.local/share/lumen/lumen.db` |

### Commands

#### `list`

List entries in the vault.

```
lumen-cli list [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `-k`, `--kind <KIND>` | Filter by entry kind (journal, note, task, project) |
| `-a`, `--author <AUTHOR>` | Filter by author |
| `-l`, `--limit <N>` | Maximum entries to show (default: 20) |

Outputs a Markdown table with ID, Kind, Author, and Title.

#### `search <query>`

Search entries by metadata (kind, tags, display_title, author, ID).

```
lumen-cli search "query text"
```

#### `view <id>`

View a specific entry's details and decrypted body.

```
lumen-cli view <id> [--password <password>]
```

| Option | Description |
|--------|-------------|
| `-p`, `--password <PASSWORD>` | Password to decrypt the entry body |

Displays title, metadata, and decrypted body (requires password for encrypted entries).

#### `streak`

Show the current journaling streak (consecutive days with journal entries).

```
lumen-cli streak
```

#### `interactive`

Launch the interactive TUI mode with keyboard navigation.

```
lumen-cli interactive
```

Controls in interactive mode:

| Key | Action |
|-----|--------|
| `q` | Quit |
| `↑` / `↓` | Navigate entries |
| `Enter` | View selected entry (not yet implemented) |

## Examples

```bash
# List all journal entries
lumen-cli list --kind journal

# Search for entries about "meditation"
lumen-cli search meditation

# View a specific entry
lumen-cli view abc-123 --password mypassword

# Show journaling streak
lumen-cli streak

# Launch interactive TUI
lumen-cli
```

## Dependencies

The TUI uses:
- `clap` — argument parsing
- `ratatui` — terminal UI framework (interactive mode)
- `crossterm` — terminal backend
- `termimad` — Markdown rendering
- `lumen_core` — core engine (rlib linkage)
