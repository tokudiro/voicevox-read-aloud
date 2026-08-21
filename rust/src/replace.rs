use std::fs;

/// 置換ルール: (検索語, 置換後) のペア。ファイル上の記載順を保持する。
pub type ReplaceRule = (String, String);

/// 置換ルールファイルを読み込み、パースする。
/// 各行は`検索語=置換後`の形式。`#`で始まる行はコメント、空行は無視する。
pub fn load_replacements(path: &str) -> Result<Vec<ReplaceRule>, String> {
    let content = fs::read_to_string(path)
        .map_err(|e| format!("置換ファイルが読み込めません: {} ({})", path, e))?;

    let mut rules = Vec::new();
    for (i, raw_line) in content.lines().enumerate() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (target, replacement) = line.split_once('=').ok_or_else(|| {
            format!(
                "置換ファイルの{}行目が不正です（'='が見つかりません）: {}",
                i + 1,
                raw_line
            )
        })?;
        let target = target.trim();
        if target.is_empty() {
            return Err(format!(
                "置換ファイルの{}行目が不正です（検索語が空です）: {}",
                i + 1,
                raw_line
            ));
        }
        rules.push((target.to_string(), replacement.trim().to_string()));
    }

    Ok(rules)
}

/// 置換ルールをファイル記載順に、単純文字列置換として適用する。
/// 正規表現は使わない（この原稿限りの一時的な調整用であり、単語境界の厳密な判定は
/// VOICEVOXの読み方＆アクセント辞書に任せる想定のため）。
pub fn apply_replacements(text: &str, rules: &[ReplaceRule]) -> String {
    let mut result = text.to_string();
    for (target, replacement) in rules {
        result = result.replace(target, replacement);
    }
    result
}
