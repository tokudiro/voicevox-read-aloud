# voicevox-read-aloud

> ずんだもんに読ませてみた。

[VOICEVOX](https://voicevox.hiroshiba.jp/)（無料の日本語音声合成エンジン）を使って、Markdown（または平文）の原稿を読み上げるWindows PowerShell製CLIです。

自分で書いた文章を耳で聞くと、文章のねじれ・冗長な表現・主述の不一致など、目で読むだけでは見落としがちな違和感に気づきやすくなります。本ツールはMarkdown記法を取り除いたうえで、テキストを文単位で読み上げます。

English README is available at [README.md](README.md).

これは元々の**PowerShell版**（Windows専用）です。同じリポジトリ内に、オプション面では同等になったクロスプラットフォームな**Rust版**もあります。詳細は[rust/README-ja.md](rust/README-ja.md)を参照してください。

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

:: IDを指定して1件だけ調べる（-ls/-lcどちらでも可）
read-aloud.bat -ls 3

:: 話者ごとの利用規約を確認する
read-aloud.bat -lc
read-aloud.bat -lc 3

:: 行番号を指定して一部だけ読ませる（1始まり・両端含む）
read-aloud.bat path\to\draft.md -l 10:30
read-aloud.bat path\to\draft.md -l 10
read-aloud.bat path\to\draft.md -l 10:
read-aloud.bat path\to\draft.md -l :30

:: Markdown記法を解釈せず、テキストをそのまま読み上げ
read-aloud.bat path\to\draft.md -p

:: 抑揚・音高・話速・音量を調整（VOICEVOXの各*Scaleフィールドに対応）
read-aloud.bat path\to\draft.md -is 1.3
read-aloud.bat path\to\draft.md -ps 0.05 -ss 1.2 -vs 1.1

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
| `-l <n[:m]>` | `-Lines` | 行番号指定（`-l 10` は10行目のみ、`-l 10:30` は10〜30行目、`-l 10:` は10行目以降、`-l :30` は30行目まで） |
| `-p` | `-PlainText` | Markdown記法を解釈せず、テキストをそのまま扱う |
| `-ls [ID]` | `-ListSpeakers` | 話者一覧を表示して終了。`ID`指定でその話者だけに絞り込み |
| `-lc [ID]` | `-License` | 話者ごとの利用規約を表示して終了。`ID`指定でその話者だけに絞り込み |
| `-o <path>` | `-Output` | 再生せず、音声ファイル（.mp3等）として書き出す（要ffmpeg） |
| `-is <値>` | `-IntonationScale` | 抑揚（`intonationScale`）。既定: エンジン既定値のまま（未指定時は変更しない）。目安0.0〜2.0 |
| `-ps <値>` | `-PitchScale` | 音高（`pitchScale`）。既定: エンジン既定値のまま（未指定時は変更しない）。目安-0.15〜0.15 |
| `-ss <値>` | `-SpeedScale` | 話速（`speedScale`）。既定: エンジン既定値のまま（未指定時は変更しない）。目安0.5〜2.0 |
| `-vs <値>` | `-VolumeScale` | 音量（`volumeScale`）。既定: エンジン既定値のまま（未指定時は変更しない）。目安0.0〜2.0 |
| `-h` / `--help` | `-Help` | ヘルプを表示して終了 |
| `-u <url>` | `-EngineUrl` | VOICEVOXエンジンのURL（既定: `http://localhost:50021`） |

`*Scale`系の4オプションは、`audio_query`のレスポンスに対してそのまま値を上書きしたうえで合成に渡しており、本ツール側での値の範囲チェックは行いません（VOICEVOX側もチェックしません）。未指定の場合は、そのフィールドのエンジン既定値がそのまま使われます。

## 構成

以下の2つのスクリプトをパイプでつないでいます。

- `ConvertTo-SpeechChunks.ps1` — Markdown/平文テキストを読み上げ用の文単位チャンクに分割（見出し・強調・リンク・コードブロック・フロントマター等を除去）
- `Invoke-VoicevoxSpeak.ps1` — 各チャンクをVOICEVOXエンジンへ送って音声合成・再生（または書き出し）

`read-aloud.ps1` はこの2つをつなぐ薄いラッパーです。各スクリプトは単体でも実行できます（例: VOICEVOXを起動せずにチャンク分割結果だけを確認する）。

## ライセンス

MIT
