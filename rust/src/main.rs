mod markdown;
mod voicevox;

use clap::Parser;
use std::fs;
use std::io::{self, Read};
use std::path::PathBuf;
use std::process::{Command, ExitCode, Stdio};
use voicevox::{ScaleOverrides, Speaker, VoicevoxClient};

/// VOICEVOXでMarkdown/平文の原稿を読み上げるCLI（PowerShell版のRust移植）
#[derive(Parser)]
#[command(name = "read-aloud")]
struct Args {
    /// 読み上げるファイル（省略時は標準入力から読み込み）
    file: Option<String>,

    /// 話者ID（既定: 3 = ずんだもん ノーマル）
    #[arg(short = 's', long = "speaker", default_value_t = 3)]
    speaker: u32,

    /// VOICEVOXエンジンのURL
    #[arg(short = 'u', long = "engine-url", default_value = "http://localhost:50021")]
    engine_url: String,

    /// 行番号を指定（n / n:m / n: / :m）
    #[arg(short = 'l', long = "lines")]
    lines: Option<String>,

    /// Markdown記法を解釈せず、テキストをそのまま扱う
    #[arg(short = 'p', long = "plain-text")]
    plain_text: bool,

    /// 話者一覧を表示して終了（--idで絞り込み）
    #[arg(long = "list-speakers", alias = "ls")]
    list_speakers: bool,

    /// 話者ごとの利用規約を表示して終了（--idで絞り込み）
    #[arg(long = "license", alias = "lc")]
    license: bool,

    /// --list-speakers/--licenseと併用し、指定IDの話者だけに絞り込む
    #[arg(short = 'i', long = "id")]
    id: Option<u32>,

    /// 再生せず、音声ファイル（.mp3等）として書き出す（要ffmpeg）
    #[arg(short = 'o', long = "output")]
    output: Option<String>,

    /// 抑揚（intonationScale）。未指定時はエンジン既定値のまま
    #[arg(long = "intonation-scale", alias = "is")]
    intonation_scale: Option<f64>,

    /// 音高（pitchScale）。未指定時はエンジン既定値のまま
    #[arg(long = "pitch-scale", alias = "ps")]
    pitch_scale: Option<f64>,

    /// 話速（speedScale）。未指定時はエンジン既定値のまま
    #[arg(long = "speed-scale", alias = "ss")]
    speed_scale: Option<f64>,

    /// 音量（volumeScale）。未指定時はエンジン既定値のまま
    #[arg(long = "volume-scale", alias = "vs")]
    volume_scale: Option<f64>,
}

fn main() -> ExitCode {
    let args = Args::parse();

    let scales = ScaleOverrides {
        intonation: args.intonation_scale,
        pitch: args.pitch_scale,
        speed: args.speed_scale,
        volume: args.volume_scale,
    };

    let client = VoicevoxClient::new(args.engine_url.clone());
    if let Err(e) = client.check_connection() {
        eprintln!("{}", e);
        eprintln!("VOICEVOXアプリを起動した状態にしてから再実行してください。");
        return ExitCode::FAILURE;
    }

    if args.list_speakers {
        return run_list_speakers(&client, args.id);
    }

    if args.license {
        return run_license(&client, args.id);
    }

    if args.output.is_some() && !ffmpeg_available() {
        eprintln!("ffmpeg が見つかりません。");
        eprintln!("winget install ffmpeg 等でインストールし、PATH を通してから再実行してください。");
        return ExitCode::FAILURE;
    }

    let raw_text = match &args.file {
        Some(path) => match fs::read_to_string(path) {
            Ok(text) => text,
            Err(e) => {
                eprintln!("ファイルが読み込めません: {} ({})", path, e);
                return ExitCode::FAILURE;
            }
        },
        None => {
            let mut buf = String::new();
            if let Err(e) = io::stdin().read_to_string(&mut buf) {
                eprintln!("標準入力の読み込みに失敗しました: {}", e);
                return ExitCode::FAILURE;
            }
            buf
        }
    };

    let raw_text = match &args.lines {
        Some(lines) => {
            let (start, end) = match markdown::parse_line_range(lines) {
                Ok(v) => v,
                Err(e) => {
                    eprintln!("{}", e);
                    return ExitCode::FAILURE;
                }
            };
            match markdown::apply_line_range(&raw_text, start, end, lines) {
                Ok(t) => t,
                Err(e) => {
                    eprintln!("{}", e);
                    return ExitCode::FAILURE;
                }
            }
        }
        None => raw_text,
    };

    let plain_text = if args.plain_text {
        raw_text
    } else {
        markdown::strip_markdown(&raw_text)
    };
    let chunks = markdown::split_into_chunks(&plain_text);

    if chunks.is_empty() {
        eprintln!("読み上げるテキストがありません。");
        return ExitCode::FAILURE;
    }

    println!("読み上げます: {} 区切り、話者ID: {}", chunks.len(), args.speaker);
    println!("中断する場合は Ctrl+C を押してください。\n");

    if let Some(output) = &args.output {
        run_output(&client, &chunks, args.speaker, &scales, output)
    } else {
        run_playback(&client, &chunks, args.speaker, &scales)
    }
}

fn run_list_speakers(client: &VoicevoxClient, id: Option<u32>) -> ExitCode {
    let speakers = match client.list_speakers() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("話者一覧の取得に失敗しました: {}", e);
            return ExitCode::FAILURE;
        }
    };

    let mut found = false;
    for sp in &speakers {
        for style in &sp.styles {
            if let Some(target) = id {
                if style.id != target {
                    continue;
                }
            }
            println!("{:>4}  {} - {}", style.id, sp.name, style.name);
            found = true;
        }
    }
    if let Some(target) = id {
        if !found {
            println!("話者ID {} は見つかりませんでした。", target);
        }
    }
    ExitCode::SUCCESS
}

fn run_license(client: &VoicevoxClient, id: Option<u32>) -> ExitCode {
    let speakers = match client.list_speakers() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("話者一覧の取得に失敗しました: {}", e);
            return ExitCode::FAILURE;
        }
    };

    let targets: Vec<&Speaker> = match id {
        Some(target) => {
            match speakers.iter().find(|sp| sp.styles.iter().any(|st| st.id == target)) {
                Some(sp) => vec![sp],
                None => {
                    println!("話者ID {} は見つかりませんでした。", target);
                    return ExitCode::SUCCESS;
                }
            }
        }
        None => speakers.iter().collect(),
    };

    for sp in targets {
        match client.speaker_info(&sp.speaker_uuid) {
            Ok(info) => {
                println!("=== {} ===", sp.name);
                println!("{}", info.policy);
                println!();
            }
            Err(e) => {
                eprintln!("利用規約の取得に失敗しました（{}）: {}", sp.name, e);
                return ExitCode::FAILURE;
            }
        }
    }
    ExitCode::SUCCESS
}

fn ffmpeg_available() -> bool {
    Command::new("ffmpeg")
        .arg("-version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn cleanup_files(paths: &[PathBuf]) {
    for p in paths {
        let _ = fs::remove_file(p);
    }
}

fn run_output(
    client: &VoicevoxClient,
    chunks: &[String],
    speaker: u32,
    scales: &ScaleOverrides,
    output: &str,
) -> ExitCode {
    let temp_dir = std::env::temp_dir();
    let pid = std::process::id();
    let mut wav_paths: Vec<PathBuf> = Vec::new();

    for (i, chunk) in chunks.iter().enumerate() {
        println!("[{}/{}] {}", i + 1, chunks.len(), chunk);

        let wav_bytes = match client.synthesize(chunk, speaker, scales) {
            Ok(b) => b,
            Err(e) => {
                eprintln!("音声合成に失敗しました: {}", e);
                cleanup_files(&wav_paths);
                return ExitCode::FAILURE;
            }
        };

        let path = temp_dir.join(format!("read-aloud-{}-{}.wav", pid, i));
        if let Err(e) = fs::write(&path, &wav_bytes) {
            eprintln!("一時ファイルの書き込みに失敗しました: {}", e);
            cleanup_files(&wav_paths);
            return ExitCode::FAILURE;
        }
        wav_paths.push(path);
    }

    // ffmpegのconcatデマルチプレクサへ渡すリストファイル。バックスラッシュはエスケープ解釈されるため、
    // パス区切りをフォワードスラッシュへ統一しておく（Windowsパスでもffmpegはこれを受け付ける）。
    let list_path = temp_dir.join(format!("read-aloud-{}-list.txt", pid));
    let list_content: String = wav_paths
        .iter()
        .map(|p| format!("file '{}'\n", p.to_string_lossy().replace('\\', "/")))
        .collect();
    if let Err(e) = fs::write(&list_path, list_content) {
        eprintln!("一時ファイルの書き込みに失敗しました: {}", e);
        cleanup_files(&wav_paths);
        return ExitCode::FAILURE;
    }

    let status = Command::new("ffmpeg")
        .args(["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i"])
        .arg(&list_path)
        .arg(output)
        .status();

    let _ = fs::remove_file(&list_path);
    cleanup_files(&wav_paths);

    match status {
        Ok(s) if s.success() => {
            println!("\n書き出しました: {}", output);
            ExitCode::SUCCESS
        }
        _ => {
            eprintln!("ffmpegでの書き出しに失敗しました。");
            ExitCode::FAILURE
        }
    }
}

fn run_playback(client: &VoicevoxClient, chunks: &[String], speaker: u32, scales: &ScaleOverrides) -> ExitCode {
    let mut device_sink = match rodio::DeviceSinkBuilder::open_default_sink() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("音声出力デバイスを初期化できません: {}", e);
            return ExitCode::FAILURE;
        }
    };
    device_sink.log_on_drop(false);

    for (i, chunk) in chunks.iter().enumerate() {
        println!("[{}/{}] {}", i + 1, chunks.len(), chunk);

        let wav_bytes = match client.synthesize(chunk, speaker, scales) {
            Ok(bytes) => bytes,
            Err(e) => {
                eprintln!("音声合成に失敗しました: {}", e);
                return ExitCode::FAILURE;
            }
        };

        let cursor = io::Cursor::new(wav_bytes);
        let source = match rodio::Decoder::new(cursor) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("音声データのデコードに失敗しました: {}", e);
                return ExitCode::FAILURE;
            }
        };

        let player = rodio::Player::connect_new(device_sink.mixer());
        player.append(source);
        player.sleep_until_end();
    }

    println!("\n読み上げ完了しました。");
    ExitCode::SUCCESS
}
