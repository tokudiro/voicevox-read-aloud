# read-aloud (Rust)

A cross-platform Rust port of the [PowerShell version](../README.md) of `voicevox-read-aloud`. Same idea — read a Markdown (or plain text) draft aloud via [VOICEVOX](https://voicevox.hiroshiba.jp/) so you can proofread by ear — implemented with a portable audio backend ([rodio](https://github.com/RustAudio/rodio)) so it isn't tied to Windows.

日本語版READMEは [README-ja.md](README-ja.md) にあります。

## Status

All options from the PowerShell version are now ported: line ranges, plain-text mode, file export, speaker/license listing with ID filtering, and the four `*Scale` options. The CLI surface differs slightly from the PowerShell version because `clap` short flags are limited to a single character — see the options table below for the exact names.

## Prebuilt binaries

[GitHub Actions](https://github.com/tokudiro/voicevox-read-aloud/actions/workflows/release.yml) builds binaries for Windows (x64), macOS (x64/arm64), and Linux (x64/arm64) on every tagged release — see the [Releases page](https://github.com/tokudiro/voicevox-read-aloud/releases). Only the Windows x64 build is manually verified by the maintainer; the others are built by CI but not hand-tested on real hardware. If one doesn't work, please [open an issue](https://github.com/tokudiro/voicevox-read-aloud/issues).

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

# Read only a line range (1-based, inclusive)
read-aloud path/to/draft.md -l 10:30
read-aloud path/to/draft.md -l 10
read-aloud path/to/draft.md -l 10:
read-aloud path/to/draft.md -l :30

# Split long chunks further (handy for shorter stops during test playback)
read-aloud path/to/draft.md --chunk-length 40

# Treat the file as plain text, skipping Markdown parsing
read-aloud path/to/draft.md -p

# Check the chunking result only, without calling VOICEVOX
read-aloud path/to/draft.md --dump-chunks

# List installed speakers / show each speaker's license, optionally filtered by ID
read-aloud --list-speakers
read-aloud --list-speakers -i 3
read-aloud --license -i 3

# Adjust intonation / pitch / speed / volume (VOICEVOX's *Scale fields)
read-aloud path/to/draft.md --intonation-scale 1.3
read-aloud path/to/draft.md --pitch-scale 0.05 --speed-scale 1.2 --volume-scale 1.1

# Export to an audio file instead of playing it back (requires ffmpeg)
read-aloud path/to/draft.md -o out.mp3

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
| `-l <n[:m]>` | `--lines` | Line range (`-l 10` = line 10 only, `-l 10:30` = lines 10-30, `-l 10:` = line 10 to end, `-l :30` = start to line 30) |
| — | `--chunk-length <n>` (alias `--cl`) | Further split chunks longer than n characters (tries a comma `、`, then whitespace, then a hard cut at n characters, in that order). Default: no extra splitting unless passed |
| `-p` | `--plain-text` | Treat input as plain text, skipping Markdown parsing |
| — | `--dump-chunks` (alias `--dc`) | Skip VOICEVOX entirely and write the chunking result to stdout, one chunk per line, then exit |
| — | `--list-speakers` (alias `--ls`) | List installed speakers and exit. Combine with `-i` to show only one |
| — | `--license` (alias `--lc`) | Show each installed speaker's usage terms/license and exit. Combine with `-i` to show only one |
| `-i <ID>` | `--id` | Used with `--list-speakers`/`--license` to filter to a single speaker ID |
| `-o <path>` | `--output` | Don't play back — write audio to a file instead (requires ffmpeg) |
| — | `--intonation-scale` (alias `--is`) | Intonation (`intonationScale`). Default: engine default (unset unless passed). Typical range 0.0-2.0 |
| — | `--pitch-scale` (alias `--ps`) | Pitch (`pitchScale`). Default: engine default (unset unless passed). Typical range -0.15-0.15 |
| — | `--speed-scale` (alias `--ss`) | Speed (`speedScale`). Default: engine default (unset unless passed). Typical range 0.5-2.0 |
| — | `--volume-scale` (alias `--vs`) | Volume (`volumeScale`). Default: engine default (unset unless passed). Typical range 0.0-2.0 |
| `-u` | `--engine-url` | VOICEVOX engine URL (default: `http://localhost:50021`) |
| `-h` | `--help` | Show help |

Unlike the PowerShell version's `-is`/`-ps`/`-ss`/`-vs`/`-ls`/`-lc`, these aliases need a double dash (`--is`, not `-is`) because `clap` short flags are limited to one character. For negative `--chunk-length` values, use `--chunk-length=-5` instead of `--chunk-length -5` — otherwise `clap` mistakes `-5` for a separate flag.

## License

MIT
