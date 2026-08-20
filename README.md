# voicevox-read-aloud

A Windows PowerShell CLI that reads Markdown (or plain text) drafts aloud using [VOICEVOX](https://voicevox.hiroshiba.jp/), a free Japanese text-to-speech engine.

Hearing your own writing read back to you is a fast way to catch awkward phrasing, redundant wording, or subject/predicate mismatches that are easy to miss by eye. This tool strips Markdown syntax and reads the remaining text one sentence at a time, so you can proofread by ear.

日本語版READMEは [README-ja.md](README-ja.md) にあります。

This is the original **PowerShell** implementation (Windows-only). A cross-platform **Rust** port with equivalent options is also in this repo — see [rust/README.md](rust/README.md).

## Prerequisites

- Windows PowerShell 5.1+ or PowerShell 7+
- [VOICEVOX](https://voicevox.hiroshiba.jp/) installed and running (the app listens on `localhost:50021` while open)
- (optional) [ffmpeg](https://ffmpeg.org/) on `PATH` — only needed for `-o`/`-Output` to export an audio file instead of playing it

## Usage

```cmd
:: Drag & drop a file onto read-aloud.bat, or run it from the command line
read-aloud.bat path\to\draft.md

:: Change speaker (list IDs with -ls)
read-aloud.bat path\to\draft.md -s 8
read-aloud.bat -ls

:: Look up a single speaker by ID (works for -ls and -lc)
read-aloud.bat -ls 3

:: Check each speaker's license/usage terms
read-aloud.bat -lc
read-aloud.bat -lc 3

:: Read only a line range (1-based, inclusive)
read-aloud.bat path\to\draft.md -l 10:30
read-aloud.bat path\to\draft.md -l 10
read-aloud.bat path\to\draft.md -l 10:
read-aloud.bat path\to\draft.md -l :30

:: Treat the file as plain text, skipping Markdown parsing
read-aloud.bat path\to\draft.md -p

:: Adjust intonation / pitch / speed / volume (VOICEVOX's *Scale fields)
read-aloud.bat path\to\draft.md -is 1.3
read-aloud.bat path\to\draft.md -ps 0.05 -ss 1.2 -vs 1.1

:: Full option list
read-aloud.bat --help
```

**From a pipeline (PowerShell only):**

```powershell
:: Use PowerShell's own in-process pipeline. Piping across processes via
:: the .bat wrapper corrupts the encoding, so avoid that route.
Get-Content draft.md -Encoding UTF8 | .\read-aloud.ps1
Get-Content draft.md -Encoding UTF8 -TotalCount 30 | .\read-aloud.ps1
```

## Options

| Short | Long | Description |
|---|---|---|
| `-s <ID>` | `-Speaker` | Speaker ID (default: 3 = Zundamon, Normal) |
| `-l <n[:m]>` | `-Lines` | Line range (`-l 10` = line 10 only, `-l 10:30` = lines 10-30, `-l 10:` = line 10 to end, `-l :30` = start to line 30) |
| `-p` | `-PlainText` | Treat input as plain text, skipping Markdown parsing |
| `-ls [ID]` | `-ListSpeakers` | List installed speakers and exit. With `ID`, show only that one |
| `-lc [ID]` | `-License` | Show each installed speaker's usage terms/license and exit. With `ID`, show only that speaker's |
| `-o <path>` | `-Output` | Don't play back — write audio to a file instead (requires ffmpeg) |
| `-is <value>` | `-IntonationScale` | Intonation (`intonationScale`). Default: engine default (unset unless passed). Typical range 0.0-2.0 |
| `-ps <value>` | `-PitchScale` | Pitch (`pitchScale`). Default: engine default (unset unless passed). Typical range -0.15-0.15 |
| `-ss <value>` | `-SpeedScale` | Speed (`speedScale`). Default: engine default (unset unless passed). Typical range 0.5-2.0 |
| `-vs <value>` | `-VolumeScale` | Volume (`volumeScale`). Default: engine default (unset unless passed). Typical range 0.0-2.0 |
| `-h` / `--help` | `-Help` | Show help |
| `-u <url>` | `-EngineUrl` | VOICEVOX engine URL (default: `http://localhost:50021`) |

The four `*Scale` options are passed straight through to VOICEVOX's `audio_query` response before synthesis, with no range validation on this tool's side (VOICEVOX doesn't validate them either). When not passed, the engine's own default for that field is left untouched.

## How it's built

Two scripts piped together:

- `ConvertTo-SpeechChunks.ps1` — splits Markdown/plain text into sentence-level chunks (strips headings, emphasis, links, code blocks, front matter, etc.)
- `Invoke-VoicevoxSpeak.ps1` — sends each chunk to the VOICEVOX engine and plays or exports it

`read-aloud.ps1` is a thin wrapper connecting the two; each script can also be run standalone (e.g. to inspect the chunking output without starting VOICEVOX).

## License

MIT
