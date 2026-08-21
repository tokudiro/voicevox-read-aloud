param (
    [Parameter(Position=0, Mandatory=$false)]
    [Alias("f")]
    [string]$File,

    [Alias("l")]
    [string]$Lines,

    [Alias("cl")]
    [int]$ChunkLength,

    [Alias("p")]
    [switch]$PlainText,

    [Alias("rp")]
    [string]$Replace,

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
        Write-Host "  -cl, -ChunkLength <n>  n文字を超えるチャンクをさらに分割（読点→空白→強制カットの順）"
        Write-Host "  -p,  -PlainText        Markdown記法を解釈せず、テキストをそのまま扱う"
        Write-Host "  -rp, -Replace <file>   この原稿限りの一時的な読み・言い回し調整を行う置換ファイル（1行1組、検索語=置換後）"
        Write-Host "  -h,  --help            このヘルプを表示"
        exit 0
    }

    $pipedLines = New-Object System.Collections.Generic.List[string]

    if ($PSBoundParameters.ContainsKey('ChunkLength') -and $ChunkLength -le 0) {
        Write-Host "「-cl」には1以上の整数を指定してください: $ChunkLength"
        exit 1
    }

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

    function Get-ReplacementRules {
        param([string]$Path)

        if (-not (Test-Path $Path)) {
            Write-Error "置換ファイルが見つかりません: $Path"
            exit 1
        }
        $content = Get-Content -Path $Path -Raw -Encoding UTF8

        $rules = New-Object System.Collections.Generic.List[string[]]
        $lineNo = 0
        foreach ($rawLine in ($content -split "`r?`n")) {
            $lineNo++
            $line = $rawLine.Trim()
            if ($line -eq '' -or $line.StartsWith('#')) { continue }

            $parts = $line -split '=', 2
            if ($parts.Count -lt 2) {
                Write-Error "置換ファイルの${lineNo}行目が不正です（'='が見つかりません）: $rawLine"
                exit 1
            }
            $target = $parts[0].Trim()
            if ($target -eq '') {
                Write-Error "置換ファイルの${lineNo}行目が不正です（検索語が空です）: $rawLine"
                exit 1
            }
            $rules.Add(@($target, $parts[1].Trim()))
        }

        # 単項カンマでリストをラップしないと、パイプライン境界でListが1段階アンロールされ、
        # ルールが1件だけの場合に呼び出し側で string[] へ展開されてしまう
        # （$rule[0]/$rule[1]が「配列の要素」ではなく「文字列の1文字目/2文字目」になる事故）。
        return ,$rules
    }

    function Invoke-Replacements {
        param([string]$Text, $Rules)

        # 正規表現は使わない（この原稿限りの一時的な調整用であり、単語境界の厳密な判定は
        # VOICEVOXの読み方＆アクセント辞書に任せる想定のため）。
        foreach ($rule in $Rules) {
            $Text = $Text.Replace($rule[0], $rule[1])
        }
        return $Text
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

    function Split-LongChunk {
        param([string]$Text, [int]$MaxLength)

        # 句点分割"後"のチャンクのうちMaxLengthを超えるものだけを対象に、上限に近い位置から
        # 手前方向へ 読点（、）→ 半角/全角スペース → 強制カット の順で分割点を探す。
        $pieces = New-Object System.Collections.Generic.List[string]
        $remaining = $Text

        while ($remaining.Length -gt $MaxLength) {
            $window = $remaining.Substring(0, $MaxLength)

            $commaIdx = $window.LastIndexOf('、')
            if ($commaIdx -ge 0) {
                $pieces.Add($remaining.Substring(0, $commaIdx + 1))
                $remaining = $remaining.Substring($commaIdx + 1)
                continue
            }

            $spaceIdx = -1
            for ($i = $window.Length - 1; $i -ge 0; $i--) {
                if ($window[$i] -eq ' ' -or $window[$i] -eq [char]0x3000) {
                    $spaceIdx = $i
                    break
                }
            }
            if ($spaceIdx -ge 0) {
                $piece = $remaining.Substring(0, $spaceIdx).TrimEnd()
                if ($piece -ne '') { $pieces.Add($piece) }
                $remaining = $remaining.Substring($spaceIdx + 1)
                continue
            }

            # 読点・空白のどちらも見つからない場合はMaxLength文字目で強制的に切るが、
            # サロゲートペア（絵文字等）の境界には切り込まないようにする。
            $cutLength = $MaxLength
            if ([char]::IsHighSurrogate($remaining[$cutLength - 1])) {
                $cutLength -= 1
            }
            if ($cutLength -le 0) { $cutLength = $MaxLength }
            $pieces.Add($remaining.Substring(0, $cutLength))
            $remaining = $remaining.Substring($cutLength)
        }

        if ($remaining -ne '') { $pieces.Add($remaining) }

        return $pieces
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

    if ($Replace) {
        $rules = Get-ReplacementRules -Path $Replace
        $textToSpeak = Invoke-Replacements -Text $textToSpeak -Rules $rules
    }

    # チャンクは1件ずつパイプラインへ流す。$chunks = Split-IntoChunks... のように変数へ
    # まとめて受けて後から添字アクセスすると、1件しかない場合にPowerShellが配列を
    # 文字列へ展開してしまい "text"[0] が1文字だけを返す事故につながる（過去に実際に発生）。
    # 1件ずつストリームすれば、受け手は常にスカラー1件＝1チャンクとして扱えて安全。
    $hasChunkLength = $PSBoundParameters.ContainsKey('ChunkLength')
    foreach ($chunk in (Split-IntoChunks -Text $textToSpeak)) {
        if ($hasChunkLength -and $chunk.Length -gt $ChunkLength) {
            Split-LongChunk -Text $chunk -MaxLength $ChunkLength
        } else {
            $chunk
        }
    }
}
