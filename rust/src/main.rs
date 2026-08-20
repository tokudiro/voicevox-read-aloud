mod markdown;
mod voicevox;

use clap::Parser;
use std::fs;
use std::io::{self, Read};
use std::process::ExitCode;

/// VOICEVOXでMarkdown/平文の原稿を読み上げるCLI（PowerShell版のRust移植・基本機能のみ）
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
}

fn main() -> ExitCode {
    let args = Args::parse();

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

    let plain_text = markdown::strip_markdown(&raw_text);
    let chunks = markdown::split_into_chunks(&plain_text);

    if chunks.is_empty() {
        eprintln!("読み上げるテキストがありません。");
        return ExitCode::FAILURE;
    }

    let client = voicevox::VoicevoxClient::new(args.engine_url.clone());
    if let Err(e) = client.check_connection() {
        eprintln!("{}", e);
        eprintln!("VOICEVOXアプリを起動した状態にしてから再実行してください。");
        return ExitCode::FAILURE;
    }

    println!("読み上げます: {} 区切り、話者ID: {}", chunks.len(), args.speaker);
    println!("中断する場合は Ctrl+C を押してください。\n");

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

        let wav_bytes = match client.synthesize(chunk, args.speaker) {
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
