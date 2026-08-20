# read-aloud (Rust版)

`voicevox-read-aloud`の[PowerShell版](../README-ja.md)をRustに移植した、クロスプラットフォーム版です。原稿を[VOICEVOX](https://voicevox.hiroshiba.jp/)で読み上げて耳で校正するという目的は同じですが、音声再生にクロスプラットフォームなライブラリ（[rodio](https://github.com/RustAudio/rodio)）を使っているため、Windows専用ではありません。

English README is available at [README.md](README.md).

## 現状

まだ最小限の移植です。現時点では基本パイプライン（ファイル/標準入力の取得 → Markdown除去 → 文単位のチャンク分割 → VOICEVOXでの音声合成 → 再生）のみをカバーしています。PowerShell版にある`-Lines`・`-PlainText`・`-Output`・`-ListSpeakers`・`-License`・IDによる絞り込み・各`*Scale`オプションはまだ未移植です。進捗は[Issues](https://github.com/tokudiro/voicevox-read-aloud/issues)を参照してください。

## 事前準備

- [Rust](https://www.rust-lang.org/tools/install)（stableツールチェーン）
- [VOICEVOX](https://voicevox.hiroshiba.jp/) をインストールし、アプリを起動しておくこと（起動中のみ`localhost:50021`でAPIが待ち受けます）

## ビルドと実行

```bash
cd rust
cargo build --release

# cargoから直接実行
cargo run --release -- path/to/draft.md

# ビルド済みバイナリを実行
./target/release/read-aloud path/to/draft.md
```

## 使い方

```bash
read-aloud path/to/draft.md
read-aloud path/to/draft.md --speaker 8
read-aloud path/to/draft.md --engine-url http://localhost:50021
read-aloud --help
```

標準入力からのパイプにも対応しています（ファイル引数を省略）。

```bash
cat path/to/draft.md | read-aloud
```

## オプション早見表

| 短縮形 | 完全形 | 内容 |
|---|---|---|
| — | `[FILE]` | 読み上げるファイル（省略時は標準入力から読み込み） |
| `-s` | `--speaker` | 話者ID（既定: 3 = ずんだもん ノーマル） |
| `-u` | `--engine-url` | VOICEVOXエンジンのURL（既定: `http://localhost:50021`） |
| `-h` | `--help` | ヘルプを表示 |

## ライセンス

MIT
