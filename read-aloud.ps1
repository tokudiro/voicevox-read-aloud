param (
    [Parameter(Position=0, Mandatory=$false)]
    [Alias("f")]
    [string]$File,

    [Alias("s")]
    [int]$Speaker = 3,

    [Alias("l")]
    [string]$Lines,

    [Alias("u")]
    [string]$EngineUrl = "http://localhost:50021",

    [Alias("ls")]
    [switch]$ListSpeakers,

    [Alias("h")]
    [switch]$Help,

    [Alias("p")]
    [switch]$PlainText,

    [Alias("o")]
    [string]$Output,

    [Parameter(ValueFromPipeline=$true)]
    [string]$PipelineLine,

    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Rest
)

# read-aloud.ps1 は、テキスト分割（ConvertTo-SpeechChunks.ps1）と音声合成・再生
# （Invoke-VoicevoxSpeak.ps1）をパイプでつなぐだけの薄いラッパー。
# 分割した理由: 以前、分割前の1本のスクリプトで「音声合成に渡る直前のテキストが
# 何か」を確認するためだけに本体を書き換えてデバッグ出力を仕込む必要があった。
# 2つに分けておけば `ConvertTo-SpeechChunks.ps1 <file>` を単体実行するだけで
# VOICEVOXを起動せずにテキスト処理だけを検証できる。

begin {
    $ErrorActionPreference = "Stop"

    $helpRequested = $Help -or ($Rest -contains '--help') -or ($File -eq '--help')
    if ($helpRequested) {
        Write-Host "使い方:"
        Write-Host "  read-aloud.ps1 <ファイル> [-s <話者ID>] [-l <行 または 開始:終了>]"
        Write-Host "  read-aloud.ps1 -ls                  話者一覧を表示"
        Write-Host "  read-aloud.ps1 --help                このヘルプを表示"
        Write-Host "  Get-Content <ファイル> -Encoding UTF8 | .\read-aloud.ps1   標準入力から読み上げ"
        Write-Host ""
        Write-Host "オプション:"
        Write-Host "  -s,  -Speaker <ID>     話者ID（既定: 3 = ずんだもん ノーマル）"
        Write-Host "  -l,  -Lines <n[:m]>    行番号を指定（-l 10 は10行目のみ、-l 10:20 は10〜20行目）"
        Write-Host "  -u,  -EngineUrl <url>  VOICEVOXエンジンのURL（既定: http://localhost:50021）"
        Write-Host "  -ls, -ListSpeakers     インストール済みの話者一覧を表示して終了"
        Write-Host "  -p,  -PlainText        Markdown記法を解釈せず、テキストをそのまま読み上げ"
        Write-Host "  -o,  -Output <path>    再生せず、音声ファイル（.mp3等）として書き出す（要ffmpeg）"
        Write-Host "  -h,  --help            このヘルプを表示"
        Write-Host ""
        Write-Host "内部的には次の2つのコマンドをパイプでつないでいます。単体でも使えます。"
        Write-Host "  ConvertTo-SpeechChunks.ps1   テキスト → 読み上げ用チャンクへの分割"
        Write-Host "  Invoke-VoicevoxSpeak.ps1     チャンク → VOICEVOXで音声合成・再生"
        exit 0
    }

    if ($ListSpeakers) {
        & "$PSScriptRoot\Invoke-VoicevoxSpeak.ps1" -ListSpeakers -EngineUrl $EngineUrl
        exit $LASTEXITCODE
    }

    $pipedLines = New-Object System.Collections.Generic.List[string]
}

process {
    if (-not $helpRequested -and -not $ListSpeakers -and $PSBoundParameters.ContainsKey('PipelineLine')) {
        $pipedLines.Add($PipelineLine)
    }
}

end {
    if ($helpRequested -or $ListSpeakers) { return }

    $chunksScript = "$PSScriptRoot\ConvertTo-SpeechChunks.ps1"
    $speakScript = "$PSScriptRoot\Invoke-VoicevoxSpeak.ps1"

    # 配列スプラッティング（@array）は各要素を単なる位置引数として渡すだけで、
    # "-s" のような文字列要素をフラグとして再解釈してくれない。名前付き引数として
    # 渡すにはハッシュテーブルでスプラッティングする必要がある。
    $chunkParams = @{}
    if ($File) { $chunkParams['File'] = $File }
    if ($Lines) { $chunkParams['Lines'] = $Lines }
    if ($PlainText) { $chunkParams['PlainText'] = $true }

    $speakParams = @{
        Speaker   = $Speaker
        EngineUrl = $EngineUrl
    }
    if ($Output) { $speakParams['Output'] = $Output }

    if ($pipedLines.Count -gt 0) {
        # PowerShell内の実パイプライン経由（例: Get-Content file | read-aloud.ps1）。
        # 受け取った行をそのままConvertTo-SpeechChunks.ps1のパイプライン入力へ転送する。
        $pipedLines | & $chunksScript @chunkParams | & $speakScript @speakParams
    } else {
        # ファイル指定、またはcmd.exe等の外部OSパイプ経由の標準入力。
        # 後者の場合、ConvertTo-SpeechChunks.ps1は[Console]::Inから直接読み取る
        # （同一プロセス内のネスト呼び出しなので、外部から渡された標準入力はそのまま見える）。
        & $chunksScript @chunkParams | & $speakScript @speakParams
    }
}
