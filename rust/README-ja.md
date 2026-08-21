# read-aloud (Rust版)

`voicevox-read-aloud`の[PowerShell版](../README-ja.md)をRustに移植した、クロスプラットフォーム版です。原稿を[VOICEVOX](https://voicevox.hiroshiba.jp/)で読み上げて耳で校正するという目的は同じですが、音声再生にクロスプラットフォームなライブラリ（[rodio](https://github.com/RustAudio/rodio)）を使っているため、Windows専用ではありません。

English README is available at [README.md](README.md).

## 現状

PowerShell版のオプションは全て移植済みです（行範囲指定、プレーンテキストモード、ファイル書き出し、話者一覧・利用規約のID絞り込み、`*Scale`系4オプション）。`clap`のshortオプションは1文字までという制約があるため、CLIの見た目はPowerShell版と一部異なります。正確なオプション名は下記の早見表を参照してください。

## ビルド済みバイナリ

タグ付きリリース時に、[GitHub Actions](https://github.com/tokudiro/voicevox-read-aloud/actions/workflows/release.yml)がWindows(x64)・macOS(x64/arm64)・Linux(x64/arm64)向けバイナリを自動ビルドします。[Releasesページ](https://github.com/tokudiro/voicevox-read-aloud/releases)から入手できます。作者が手元で動作確認しているのはWindows x64のみで、それ以外はCIでビルドが通ることのみ確認済みです（実機での動作は未検証）。うまく動かない場合は[Issue](https://github.com/tokudiro/voicevox-read-aloud/issues)で教えてください。

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

# 行番号を指定して一部だけ読ませる（1始まり・両端含む）
read-aloud path/to/draft.md -l 10:30
read-aloud path/to/draft.md -l 10
read-aloud path/to/draft.md -l 10:
read-aloud path/to/draft.md -l :30

# 長いチャンクをさらに分割（テスト再生で短く止めたい場合に）
read-aloud path/to/draft.md --chunk-length 40

# Markdown記法を解釈せず、テキストをそのまま読み上げ
read-aloud path/to/draft.md -p

# VOICEVOXを呼び出さず、チャンク分割結果だけを確認する
read-aloud path/to/draft.md --dump-chunks

# 話者一覧・利用規約を表示（-i でID絞り込み）
read-aloud --list-speakers
read-aloud --list-speakers -i 3
read-aloud --license -i 3

# 抑揚・音高・話速・音量を調整（VOICEVOXの各*Scaleフィールドに対応）
read-aloud path/to/draft.md --intonation-scale 1.3
read-aloud path/to/draft.md --pitch-scale 0.05 --speed-scale 1.2 --volume-scale 1.1

# 再生せず、音声ファイルとして書き出す（要ffmpeg）
read-aloud path/to/draft.md -o out.mp3

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
| `-l <n[:m]>` | `--lines` | 行番号指定（`-l 10` は10行目のみ、`-l 10:30` は10〜30行目、`-l 10:` は10行目以降、`-l :30` は30行目まで） |
| — | `--chunk-length <n>`（エイリアス`--cl`） | n文字を超えるチャンクをさらに分割（読点「、」→ 空白 → n文字で強制カットの順）。既定: 未指定時は追加分割しない |
| `-p` | `--plain-text` | Markdown記法を解釈せず、テキストをそのまま扱う |
| — | `--dump-chunks`（エイリアス`--dc`） | VOICEVOXを呼び出さず、チャンク分割結果のみを1行ずつ標準出力へ書き出して終了する |
| — | `--list-speakers`（エイリアス`--ls`） | 話者一覧を表示して終了。`-i`併用でその話者だけに絞り込み |
| — | `--license`（エイリアス`--lc`） | 話者ごとの利用規約を表示して終了。`-i`併用でその話者だけに絞り込み |
| `-i <ID>` | `--id` | `--list-speakers`/`--license`と併用し、指定IDの話者だけに絞り込む |
| `-o <path>` | `--output` | 再生せず、音声ファイル（.mp3等）として書き出す（要ffmpeg） |
| — | `--intonation-scale`（エイリアス`--is`） | 抑揚（`intonationScale`）。既定: エンジン既定値のまま（未指定時は変更しない）。目安0.0〜2.0 |
| — | `--pitch-scale`（エイリアス`--ps`） | 音高（`pitchScale`）。既定: エンジン既定値のまま（未指定時は変更しない）。目安-0.15〜0.15 |
| — | `--speed-scale`（エイリアス`--ss`） | 話速（`speedScale`）。既定: エンジン既定値のまま（未指定時は変更しない）。目安0.5〜2.0 |
| — | `--volume-scale`（エイリアス`--vs`） | 音量（`volumeScale`）。既定: エンジン既定値のまま（未指定時は変更しない）。目安0.0〜2.0 |
| `-u` | `--engine-url` | VOICEVOXエンジンのURL（既定: `http://localhost:50021`） |
| `-h` | `--help` | ヘルプを表示 |

PowerShell版の`-is`/`-ps`/`-ss`/`-vs`/`-ls`/`-lc`と異なり、これらのエイリアスは`--is`のようにダブルダッシュが必要です（`clap`のshortオプションは1文字までのため）。`--chunk-length`に負の値を渡す場合、`--chunk-length -5`だと`clap`が`-5`を別オプションと誤認識するため、`--chunk-length=-5`のように`=`で繋げてください。

## ライセンス

MIT
