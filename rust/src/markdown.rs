use fancy_regex::Regex;

/// Markdown記法を取り除き、読み上げ用の平文にする。
/// PowerShell版のConvert-MarkdownToPlainTextと同じ変換順序・同じ正規表現パターンに揃えてある。
pub fn strip_markdown(text: &str) -> String {
    let mut text = text.to_string();

    // front matter（文書の先頭が --- の場合のみ）/ コードブロックは読み上げ対象外
    let front_matter = Regex::new(r"(?s)\A---\s*\r?\n.*?\r?\n---\s*\r?\n").unwrap();
    text = front_matter.replace(&text, "").to_string();

    let code_block = Regex::new(r"(?ms)^```.*?^```").unwrap();
    text = code_block.replace_all(&text, "").to_string();

    // インラインコード・画像・リンク・強調は中身のテキストだけ残す
    let inline_code = Regex::new(r"`([^`]+)`").unwrap();
    text = inline_code.replace_all(&text, "$1").to_string();

    let image = Regex::new(r"!\[([^\]]*)\]\([^)]*\)").unwrap();
    text = image.replace_all(&text, "$1").to_string();

    let link = Regex::new(r"\[([^\]]+)\]\([^)]*\)").unwrap();
    text = link.replace_all(&text, "$1").to_string();

    let bold_star = Regex::new(r"\*\*([^*]+)\*\*").unwrap();
    text = bold_star.replace_all(&text, "$1").to_string();

    let bold_underscore = Regex::new(r"__([^_]+)__").unwrap();
    text = bold_underscore.replace_all(&text, "$1").to_string();

    let italic_star = Regex::new(r"(?<!\*)\*([^*\n]+)\*(?!\*)").unwrap();
    text = italic_star.replace_all(&text, "$1").to_string();

    let italic_underscore = Regex::new(r"(?<!_)_([^_\n]+)_(?!_)").unwrap();
    text = italic_underscore.replace_all(&text, "$1").to_string();

    let heading = Regex::new(r"^\s*#{1,6}\s*").unwrap();
    let blockquote = Regex::new(r"^\s*>\s?").unwrap();
    let bullet = Regex::new(r"^\s*[*\-+]\s+").unwrap();
    let ordered = Regex::new(r"^\s*\d+\.\s+").unwrap();
    let hr = Regex::new(r"^\s*[-*_]{3,}\s*$").unwrap();

    let lines: Vec<String> = text
        .split('\n')
        .map(|raw_line| {
            let line = raw_line.trim_end_matches('\r');
            let mut l = heading.replace(line, "").to_string();
            l = blockquote.replace(&l, "").to_string();
            l = bullet.replace(&l, "").to_string();
            l = ordered.replace(&l, "").to_string();
            if hr.is_match(&l).unwrap_or(false) {
                l = String::new();
            }
            l
        })
        .collect();

    lines.join("\n")
}

/// 文単位（。！？区切り）でチャンク化する。複数文を連結しない。
pub fn split_into_chunks(text: &str) -> Vec<String> {
    let re = Regex::new(r"[^。！？\n]*[。！？]|[^。！？\n]+").unwrap();
    re.find_iter(text)
        .filter_map(|m| m.ok())
        .map(|m| m.as_str().trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}
