param (
    [Parameter(Position=0, Mandatory=$false)]
    [Alias("f")]
    [string]$File,

    [Alias("l")]
    [string]$Lines,

    [Alias("p")]
    [switch]$PlainText,

    [Alias("h")]
    [switch]$Help,

    [Parameter(ValueFromPipeline=$true)]
    [string]$PipelineLine,

    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Rest
)

begin {
    $ErrorActionPreference = "Stop"

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
    } catch {}

    $helpRequested = $Help -or ($Rest -contains '--help') -or ($File -eq '--help')
    if ($helpRequested) {
        Write-Host "使い方:"
        Write-Host "  ConvertTo-SpeechChunks.ps1 <ファイル> [-l <行 または 開始:終了>] [-p]"
        Write-Host "  Get-Content <ファイル> -Encoding UTF8 | .\ConvertTo-SpeechChunks.ps1"
        Write-Host ""
        Write-Host "ファイル/標準入力のテキストを読み上げ用の文単位チャンクに分割し、"
        Write-Host "1チャンク1オブジェクトとしてパイプラインへ出力します。"
        Write-Host ""
        Write-Host "オプション:"
        Write-Host "  -l,  -Lines <n[:m]>    行番号を指定（-l 10 は10行目のみ、-l 10:20 は10〜20行目、-l 10: は10行目以降、-l :20 は20行目まで）"
        Write-Host "  -p,  -PlainText        Markdown記法を解釈せず、テキストをそのまま扱う"
        Write-Host "  -h,  --help            このヘルプを表示"
        exit 0
    }

    $pipedLines = New-Object System.Collections.Generic.List[string]

    $StartLine = 1
    $EndLine = 0
    if ($Lines) {
        if ($Lines -match '^(\d+):(\d+)$') {
            $StartLine = [int]$Matches[1]
            $EndLine = [int]$Matches[2]
        } elseif ($Lines -match '^(\d+):$') {
            $StartLine = [int]$Matches[1]
        } elseif ($Lines -match '^:(\d+)$') {
            $EndLine = [int]$Matches[1]
        } elseif ($Lines -match '^\d+$') {
            $StartLine = [int]$Lines
            $EndLine = [int]$Lines
        } else {
            Write-Host "「-l」の形式が不正です: $Lines （例: -l 10 または -l 10:20）"
            exit 1
        }
    }

    function Convert-MarkdownToPlainText {
        param([string]$Text)

        # front matter（文書の先頭が --- の場合のみ）/ コードブロックは読み上げ対象外
        $Text = $Text -replace '(?s)\A---\s*\r?\n.*?\r?\n---\s*\r?\n', ''
        $Text = $Text -replace '(?ms)^```.*?^```', ''

        # インラインコード・画像・リンク・強調は中身のテキストだけ残す
        $Text = $Text -replace '`([^`]+)`', '$1'
        $Text = $Text -replace '!\[([^\]]*)\]\([^\)]*\)', '$1'
        $Text = $Text -replace '\[([^\]]+)\]\([^\)]*\)', '$1'
        $Text = $Text -replace '\*\*([^\*]+)\*\*', '$1'
        $Text = $Text -replace '__([^_]+)__', '$1'
        $Text = $Text -replace '(?<!\*)\*([^\*\n]+)\*(?!\*)', '$1'
        $Text = $Text -replace '(?<!_)_([^_\n]+)_(?!_)', '$1'

        $lines = $Text -split "`r?`n"
        $out = New-Object System.Collections.Generic.List[string]
        foreach ($line in $lines) {
            $l = $line
            $l = $l -replace '^\s*#{1,6}\s*', ''
            $l = $l -replace '^\s*>\s?', ''
            $l = $l -replace '^\s*[\*\-\+]\s+', ''
            $l = $l -replace '^\s*\d+\.\s+', ''
            if ($l -match '^\s*[-\*_]{3,}\s*$') { $l = '' }
            $out.Add($l)
        }
        return ($out -join "`n")
    }

    function Split-IntoChunks {
        param([string]$Text)

        # 文単位（。！？区切り）でそのままチャンク化する（複数文を連結しない）。
        # 第2候補に $ を使うと「文字列全体の末尾」にしかマッチせず、句読点で終わらない
        # 見出し等の行が文書途中では丸ごと消えるため、改行境界で区切るだけにする。
        [regex]::Matches($Text, '[^。！？\n]*[。！？]|[^。！？\n]+') |
            ForEach-Object { $_.Value.Trim() } |
            Where-Object { $_ -ne '' }
    }
}

process {
    if (-not $helpRequested -and $PSBoundParameters.ContainsKey('PipelineLine')) {
        $pipedLines.Add($PipelineLine)
    }
}

end {
    if ($helpRequested) { return }

    if ($File) {
        if (-not (Test-Path $File)) {
            Write-Error "ファイルが見つかりません: $File"
            exit 1
        }
        $rawText = Get-Content -Path $File -Raw -Encoding UTF8
    } elseif ($pipedLines.Count -gt 0) {
        # 推奨経路：文字コードの変換が発生しないので化けない
        # （Get-Content | ConvertTo-SpeechChunks.ps1 のようなPowerShell内パイプ経由）
        $rawText = ($pipedLines -join "`n")
    } elseif ([Console]::IsInputRedirected) {
        # 別プロセス経由のOSレベル標準入力。コンソールのコードページ次第で文字化けしうるフォールバック
        # （cmd.exe等の外部パイプ経由。read-aloud.ps1からのネスト呼び出しもこの経路）
        $rawText = [Console]::In.ReadToEnd()
    } else {
        Write-Error "使い方: ConvertTo-SpeechChunks.ps1 <ファイル> [-l <行 または 開始:終了>]（詳細は --help）"
        exit 1
    }

    if ($StartLine -gt 1 -or $EndLine -gt 0) {
        $allLines = $rawText -split "`r?`n"
        $lastIdx = $allLines.Count
        $endIdx = if ($EndLine -gt 0) { [Math]::Min($EndLine, $lastIdx) } else { $lastIdx }
        $startIdx = [Math]::Max($StartLine, 1)
        if ($startIdx -le $endIdx) {
            $rawText = ($allLines[($startIdx - 1)..($endIdx - 1)]) -join "`n"
        } else {
            Write-Error "指定範囲（-l $Lines）が対象のテキスト範囲外です。"
            exit 1
        }
    }

    $textToSpeak = if ($PlainText) { $rawText } else { Convert-MarkdownToPlainText -Text $rawText }

    # チャンクは1件ずつパイプラインへ流す。$chunks = Split-IntoChunks... のように変数へ
    # まとめて受けて後から添字アクセスすると、1件しかない場合にPowerShellが配列を
    # 文字列へ展開してしまい "text"[0] が1文字だけを返す事故につながる（過去に実際に発生）。
    # 1件ずつストリームすれば、受け手は常にスカラー1件＝1チャンクとして扱えて安全。
    Split-IntoChunks -Text $textToSpeak
}
