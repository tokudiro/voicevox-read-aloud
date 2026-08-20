param (
    [Alias("s")]
    [int]$Speaker = 3,

    [Alias("u")]
    [string]$EngineUrl = "http://localhost:50021",

    [Alias("ls")]
    [switch]$ListSpeakers,

    [Alias("o")]
    [string]$Output,

    [Alias("h")]
    [switch]$Help,

    [Parameter(ValueFromPipeline=$true)]
    [string]$Chunk
)

begin {
    $ErrorActionPreference = "Stop"

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $OutputEncoding = [System.Text.Encoding]::UTF8
    } catch {}

    if ($Help) {
        Write-Host "使い方:"
        Write-Host "  ... | Invoke-VoicevoxSpeak.ps1 [-s <話者ID>] [-u <エンジンURL>] [-o <出力先>]"
        Write-Host "  Invoke-VoicevoxSpeak.ps1 -ListSpeakers"
        Write-Host ""
        Write-Host "パイプラインでチャンク文字列を1件ずつ受け取り、VOICEVOXで音声合成して再生します。"
        Write-Host ""
        Write-Host "オプション:"
        Write-Host "  -s,  -Speaker <ID>     話者ID（既定: 3 = ずんだもん ノーマル）"
        Write-Host "  -u,  -EngineUrl <url>  VOICEVOXエンジンのURL（既定: http://localhost:50021）"
        Write-Host "  -ls, -ListSpeakers     インストール済みの話者一覧を表示して終了"
        Write-Host "  -o,  -Output <path>    再生せず、音声ファイル（.mp3等）として書き出す（要ffmpeg）"
        Write-Host "  -h,  --help            このヘルプを表示"
        exit 0
    }

    # VOICEVOXエンジンの疎通確認（アプリを起動していればlocalhost:50021で待ち受けている）
    try {
        Invoke-RestMethod -Uri "$EngineUrl/version" -Method Get -TimeoutSec 3 | Out-Null
    } catch {
        Write-Host "VOICEVOXエンジンに接続できません ($EngineUrl)。"
        Write-Host "VOICEVOXアプリを起動した状態にしてから再実行してください。"
        exit 1
    }

    if ($Output -and -not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        Write-Host "ffmpeg が見つかりません。"
        Write-Host "winget install ffmpeg 等でインストールし、PATH を通してから再実行してください。"
        exit 1
    }

    if ($ListSpeakers) {
        $speakers = Invoke-RestMethod -Uri "$EngineUrl/speakers" -Method Get
        foreach ($sp in $speakers) {
            foreach ($style in $sp.styles) {
                Write-Host ("{0,4}  {1} - {2}" -f $style.id, $sp.name, $style.name)
            }
        }
        exit 0
    }

    function Get-VoicevoxWav {
        param([string]$Text, [int]$Speaker, [string]$EngineUrl)

        $encoded = [System.Uri]::EscapeDataString($Text)
        $query = Invoke-RestMethod -Method Post -Uri "$EngineUrl/audio_query?text=$encoded&speaker=$Speaker"
        $bodyJson = $query | ConvertTo-Json -Depth 20

        $tempWav = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName() + ".wav")
        Invoke-WebRequest -Method Post -Uri "$EngineUrl/synthesis?speaker=$Speaker" -Body $bodyJson -ContentType "application/json" -OutFile $tempWav
        return $tempWav
    }

    function Start-VoicevoxSynthesizeJob {
        param([System.Management.Automation.Runspaces.Runspace]$Runspace, [string]$Text, [int]$Speaker, [string]$EngineUrl)

        $ps = [powershell]::Create()
        $ps.Runspace = $Runspace
        [void]$ps.AddScript({
            param($Text, $Speaker, $EngineUrl)
            $encoded = [System.Uri]::EscapeDataString($Text)
            $query = Invoke-RestMethod -Method Post -Uri "$EngineUrl/audio_query?text=$encoded&speaker=$Speaker"
            $bodyJson = $query | ConvertTo-Json -Depth 20
            $tempWav = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName() + ".wav")
            Invoke-WebRequest -Method Post -Uri "$EngineUrl/synthesis?speaker=$Speaker" -Body $bodyJson -ContentType "application/json" -OutFile $tempWav
            return $tempWav
        }).AddArgument($Text).AddArgument($Speaker).AddArgument($EngineUrl)
        $handle = $ps.BeginInvoke()
        return [PSCustomObject]@{ PS = $ps; Handle = $handle }
    }

    function Wait-VoicevoxSynthesizeJob {
        param($Job)

        $result = $Job.PS.EndInvoke($Job.Handle)
        $Job.PS.Dispose()
        return $result[0]
    }

    # パイプラインから届いたチャンクをここへ集約する。件数に関わらず常に配列として
    # 振る舞うList<T>を使うのは意図的：素のPowerShell配列は要素数1のとき文字列へ
    # 展開されてしまい、添字アクセスが「配列のi番目」ではなく「文字列のi番目の文字」に
    # なる事故が過去に起きたため。
    $chunks = New-Object System.Collections.Generic.List[string]
}

process {
    if ($ListSpeakers -or $Help) { return }
    if ($PSBoundParameters.ContainsKey('Chunk') -and $Chunk -ne '') {
        $chunks.Add($Chunk)
    }
}

end {
    if ($ListSpeakers -or $Help) { return }

    if ($chunks.Count -eq 0) {
        Write-Host "読み上げるテキストがありません。"
        exit 1
    }

    Write-Host "読み上げます: $($chunks.Count) 区切り、話者ID: $Speaker"
    Write-Host "中断する場合は Ctrl+C を押してください。"
    Write-Host ""

    if ($Output) {
        $wavPaths = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $chunks.Count; $i++) {
            Write-Host "[$($i + 1)/$($chunks.Count)] $($chunks[$i])"
            $wavPaths.Add((Get-VoicevoxWav -Text $chunks[$i] -Speaker $Speaker -EngineUrl $EngineUrl))
        }

        # ffmpegのconcatデマルチプレクサへ渡すリストファイル。バックスラッシュはエスケープ解釈されるため、
        # パス区切りをフォワードスラッシュへ統一しておく（Windowsパスでもffmpegはこれを受け付ける）。
        $listFile = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName() + ".txt")
        $listContent = $wavPaths | ForEach-Object { "file '$($_ -replace '\\', '/')'" }
        # Windows PowerShell 5.1の Set-Content -Encoding UTF8 はBOM付きで書き出し、
        # ffmpegのconcatデマルチプレクサがBOMをキーワードの一部と誤認して失敗するため、BOM無しで直接書き込む。
        [System.IO.File]::WriteAllLines($listFile, $listContent, (New-Object System.Text.UTF8Encoding $false))

        & ffmpeg -y -loglevel error -f concat -safe 0 -i $listFile $Output
        $ffmpegExitCode = $LASTEXITCODE

        Remove-Item $listFile -Force -ErrorAction SilentlyContinue
        foreach ($wavPath in $wavPaths) { Remove-Item $wavPath -Force -ErrorAction SilentlyContinue }

        if ($ffmpegExitCode -ne 0) {
            Write-Host "ffmpegでの書き出しに失敗しました。"
            exit 1
        }

        Write-Host ""
        Write-Host "書き出しました: $Output"
    } else {
        # 次のチャンクの音声合成を、今のチャンクの再生中に別ランスペースで先読みする
        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()

        $nextJob = Start-VoicevoxSynthesizeJob -Runspace $rs -Text $chunks[0] -Speaker $Speaker -EngineUrl $EngineUrl
        for ($i = 0; $i -lt $chunks.Count; $i++) {
            Write-Host "[$($i + 1)/$($chunks.Count)] $($chunks[$i])"
            $wavPath = Wait-VoicevoxSynthesizeJob -Job $nextJob

            if ($i + 1 -lt $chunks.Count) {
                $nextJob = Start-VoicevoxSynthesizeJob -Runspace $rs -Text $chunks[$i + 1] -Speaker $Speaker -EngineUrl $EngineUrl
            }

            $player = New-Object System.Media.SoundPlayer $wavPath
            $player.PlaySync()
            $player.Dispose()
            Remove-Item $wavPath -Force -ErrorAction SilentlyContinue
        }

        $rs.Close()
        $rs.Dispose()

        Write-Host ""
        Write-Host "読み上げ完了しました。"
    }
}
