# voicevox-read-aloud

> ずんだもんに読ませてみた。

[VOICEVOX](https://voicevox.hiroshiba.jp/)（無料の日本語音声合成エンジン）を使って、Markdown（または平文）の原稿を読み上げるWindows PowerShell製CLIです。

自分で書いた文章を耳で聞くと、文章のねじれ・冗長な表現・主述の不一致など、目で読むだけでは見落としがちな違和感に気づきやすくなります。本ツールはMarkdown記法を取り除いたうえで、テキストを文単位で読み上げます。

English README is available at [README.md](README.md).

## 事前準備

- Windows PowerShell 5.1以降、またはPowerShell 7以降
- [VOICEVOX](https://voicevox.hiroshiba.jp/) をインストールし、アプリを起動しておくこと（起動中のみ `localhost:50021` でAPIが待ち受けます）
- （任意）[ffmpeg](https://ffmpeg.org/) を `PATH` に通しておくこと。再生ではなく `-o`/`-Output` で音声ファイルへ書き出す場合にのみ必要です

## 実行方法

```cmd
:: エクスプローラーからのドラッグ&ドロップ、またはコマンドラインで
read-aloud.bat path\to\draft.md

:: 話者を変える場合（IDは -ls で一覧表示）
read-aloud.bat path\to\draft.md -s 8
read-aloud.bat -ls

:: 行番号を指定して一部だけ読ませる（1始まり・両端含む）
read-aloud.bat path\to\draft.md -l 10:30
read-aloud.bat path\to\draft.md -l 10

:: 次のチャンクの音声合成を先読みして待ち時間を短縮（体感で気になったときだけ）
read-aloud.bat path\to\draft.md -p

:: オプション一覧
read-aloud.bat --help
```

**標準入力（パイプライン）から読ませる場合:**

```powershell
:: PowerShellの同一セッション内パイプラインを使うこと
:: （.bat経由の別プロセスパイプは文字コードで化けるため非推奨）
Get-Content draft.md -Encoding UTF8 | .\read-aloud.ps1
Get-Content draft.md -Encoding UTF8 -TotalCount 30 | .\read-aloud.ps1
```

## オプション早見表

| 短縮形 | 完全形 | 内容 |
|---|---|---|
| `-s <ID>` | `-Speaker` | 話者ID（既定: 3 = ずんだもん ノーマル） |
| `-l <n[:m]>` | `-Lines` | 行番号指定（`-l 10` は10行目のみ、`-l 10:30` は10〜30行目） |
| `-p` | `-Prefetch` | 次チャンクの音声合成を先読み（既定オフ、実測で体感2割程度短縮） |
| `-ls` | `-ListSpeakers` | 話者一覧を表示して終了 |
| `-o <path>` | `-Output` | 再生せず、音声ファイル（.mp3等）として書き出す（要ffmpeg） |
| `-h` / `--help` | `-Help` | ヘルプを表示して終了 |
| `-u <url>` | `-EngineUrl` | VOICEVOXエンジンのURL（既定: `http://localhost:50021`） |

## 構成

以下の2つのスクリプトをパイプでつないでいます。

- `ConvertTo-SpeechChunks.ps1` — Markdown/平文テキストを読み上げ用の文単位チャンクに分割（見出し・強調・リンク・コードブロック・フロントマター等を除去）
- `Invoke-VoicevoxSpeak.ps1` — 各チャンクをVOICEVOXエンジンへ送って音声合成・再生（または書き出し）

`read-aloud.ps1` はこの2つをつなぐ薄いラッパーです。各スクリプトは単体でも実行できます（例: VOICEVOXを起動せずにチャンク分割結果だけを確認する）。

## ライセンス

MIT
