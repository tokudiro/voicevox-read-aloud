# read-aloud (Rust)

A cross-platform Rust port of the [PowerShell version](../README.md) of `voicevox-read-aloud`. Same idea — read a Markdown (or plain text) draft aloud via [VOICEVOX](https://voicevox.hiroshiba.jp/) so you can proofread by ear — implemented with a portable audio backend ([rodio](https://github.com/RustAudio/rodio)) so it isn't tied to Windows.

日本語版READMEは [README-ja.md](README-ja.md) にあります。

## Status

This is an early, minimal port. It currently covers only the core pipeline: read a file (or stdin) → strip Markdown → split into sentence chunks → synthesize each chunk via VOICEVOX → play it back. The PowerShell version's other options (`-Lines`, `-PlainText`, `-Output`, `-ListSpeakers`, `-License`, ID filtering, the `*Scale` options) aren't ported yet — see the repo's [issues](https://github.com/tokudiro/voicevox-read-aloud/issues) for what's tracked.

## Prerequisites

- [Rust](https://www.rust-lang.org/tools/install) (stable toolchain)
- [VOICEVOX](https://voicevox.hiroshiba.jp/) installed and running (the app listens on `localhost:50021` while open)

## Build & run

```bash
cd rust
cargo build --release

# Run directly with cargo
cargo run --release -- path/to/draft.md

# Or use the built binary
./target/release/read-aloud path/to/draft.md
```

## Usage

```bash
read-aloud path/to/draft.md
read-aloud path/to/draft.md --speaker 8
read-aloud path/to/draft.md --engine-url http://localhost:50021
read-aloud --help
```

Piping from stdin also works (omit the file argument):

```bash
cat path/to/draft.md | read-aloud
```

## Options

| Short | Long | Description |
|---|---|---|
| — | `[FILE]` | File to read (omit to read from stdin) |
| `-s` | `--speaker` | Speaker ID (default: 3 = Zundamon, Normal) |
| `-u` | `--engine-url` | VOICEVOX engine URL (default: `http://localhost:50021`) |
| `-h` | `--help` | Show help |

## License

MIT
