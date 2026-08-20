use serde::Deserialize;
use serde_json::Value;
use std::time::Duration;

pub struct VoicevoxClient {
    engine_url: String,
    client: reqwest::blocking::Client,
}

/// 抑揚・音高・話速・音量の上書き値。Noneのフィールドはエンジン既定値のまま変更しない。
#[derive(Default, Clone, Copy)]
pub struct ScaleOverrides {
    pub intonation: Option<f64>,
    pub pitch: Option<f64>,
    pub speed: Option<f64>,
    pub volume: Option<f64>,
}

#[derive(Deserialize)]
pub struct Style {
    pub id: u32,
    pub name: String,
}

#[derive(Deserialize)]
pub struct Speaker {
    pub name: String,
    pub speaker_uuid: String,
    pub styles: Vec<Style>,
}

#[derive(Deserialize)]
pub struct SpeakerInfo {
    pub policy: String,
}

impl VoicevoxClient {
    pub fn new(engine_url: String) -> Self {
        Self {
            engine_url,
            client: reqwest::blocking::Client::new(),
        }
    }

    /// VOICEVOXエンジンの疎通確認（アプリを起動していればlocalhost:50021で待ち受けている）
    pub fn check_connection(&self) -> Result<(), String> {
        self.client
            .get(format!("{}/version", self.engine_url))
            .timeout(Duration::from_secs(3))
            .send()
            .and_then(|r| r.error_for_status())
            .map(|_| ())
            .map_err(|e| format!("VOICEVOXエンジンに接続できません ({}): {}", self.engine_url, e))
    }

    /// インストール済みの話者一覧（スタイル込み）を取得する。
    pub fn list_speakers(&self) -> Result<Vec<Speaker>, String> {
        self.client
            .get(format!("{}/speakers", self.engine_url))
            .send()
            .map_err(|e| e.to_string())?
            .error_for_status()
            .map_err(|e| e.to_string())?
            .json()
            .map_err(|e| e.to_string())
    }

    /// キャラクター単位の利用規約（policy）を取得する。
    pub fn speaker_info(&self, speaker_uuid: &str) -> Result<SpeakerInfo, String> {
        self.client
            .get(format!("{}/speaker_info", self.engine_url))
            .query(&[("speaker_uuid", speaker_uuid)])
            .send()
            .map_err(|e| e.to_string())?
            .error_for_status()
            .map_err(|e| e.to_string())?
            .json()
            .map_err(|e| e.to_string())
    }

    fn audio_query(&self, text: &str, speaker: u32, scales: &ScaleOverrides) -> Result<Value, String> {
        let mut query: Value = self
            .client
            .post(format!("{}/audio_query", self.engine_url))
            .query(&[("text", text), ("speaker", &speaker.to_string())])
            .send()
            .map_err(|e| e.to_string())?
            .error_for_status()
            .map_err(|e| e.to_string())?
            .json()
            .map_err(|e| e.to_string())?;

        if let Some(v) = scales.intonation {
            query["intonationScale"] = serde_json::json!(v);
        }
        if let Some(v) = scales.pitch {
            query["pitchScale"] = serde_json::json!(v);
        }
        if let Some(v) = scales.speed {
            query["speedScale"] = serde_json::json!(v);
        }
        if let Some(v) = scales.volume {
            query["volumeScale"] = serde_json::json!(v);
        }

        Ok(query)
    }

    /// audio_query -> synthesis の順に呼び、合成されたWAVのバイト列を返す。
    /// reqwestのJSON処理はRFC通りUTF-8前提で、PowerShell版で踏んだ
    /// charsetなしレスポンスの文字化け問題はそもそも発生しない。
    pub fn synthesize(&self, text: &str, speaker: u32, scales: &ScaleOverrides) -> Result<Vec<u8>, String> {
        let query = self.audio_query(text, speaker, scales)?;

        let resp = self
            .client
            .post(format!("{}/synthesis", self.engine_url))
            .query(&[("speaker", speaker.to_string())])
            .json(&query)
            .send()
            .map_err(|e| e.to_string())?
            .error_for_status()
            .map_err(|e| e.to_string())?;

        resp.bytes().map(|b| b.to_vec()).map_err(|e| e.to_string())
    }
}
