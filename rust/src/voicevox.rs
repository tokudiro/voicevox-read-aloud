use serde_json::Value;
use std::time::Duration;

pub struct VoicevoxClient {
    engine_url: String,
    client: reqwest::blocking::Client,
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

    /// audio_query -> synthesis の順に呼び、合成されたWAVのバイト列を返す。
    /// reqwestのJSON処理はRFC通りUTF-8前提で、PowerShell版で踏んだ
    /// charsetなしレスポンスの文字化け問題はそもそも発生しない。
    pub fn synthesize(&self, text: &str, speaker: u32) -> Result<Vec<u8>, String> {
        let query: Value = self
            .client
            .post(format!("{}/audio_query", self.engine_url))
            .query(&[("text", text), ("speaker", &speaker.to_string())])
            .send()
            .map_err(|e| e.to_string())?
            .error_for_status()
            .map_err(|e| e.to_string())?
            .json()
            .map_err(|e| e.to_string())?;

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
