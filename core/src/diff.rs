//! A line-by-line difference between two texts.
//!
//! The sync needs it to show what changed between two versions of a note,
//! and the terminal client shows the same difference.

use serde::{Deserialize, Serialize};

/// The most lines a difference is worked out for in full.
///
/// Beyond this the lines are compared one against one, which is quicker
/// and says less, but a note of a thousand lines does not need better.
const MAX_LINES: usize = 2000;

/// What happened to a line.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum DiffKind {
    /// The line is in both texts.
    Same,
    /// The line is only in the newer text.
    Added,
    /// The line is only in the older text.
    Removed,
}

/// A line of a difference.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DiffLine {
    /// What happened to the line.
    pub kind: DiffKind,
    /// The text of the line.
    pub text: String,
}

/// The difference between two texts, line by line.
///
/// The lines that are the same are kept, so the difference can be shown in
/// place rather than as two separate texts.
pub fn diff(old: &str, new: &str) -> Vec<DiffLine> {
    let old_lines: Vec<&str> = old.lines().collect();
    let new_lines: Vec<&str> = new.lines().collect();

    if old_lines.len() > MAX_LINES || new_lines.len() > MAX_LINES {
        return diff_by_position(&old_lines, &new_lines);
    }
    diff_by_common_lines(&old_lines, &new_lines)
}

/// The difference worked out from the lines the two texts have in common.
fn diff_by_common_lines(old: &[&str], new: &[&str]) -> Vec<DiffLine> {
    let n = old.len();
    let m = new.len();

    // `lengths[i][j]` holds the number of lines the two texts have in
    // common from `old[i]` and `new[j]` onwards.
    let mut lengths = vec![vec![0u32; m + 1]; n + 1];
    for i in (0..n).rev() {
        for j in (0..m).rev() {
            lengths[i][j] = if old[i] == new[j] {
                lengths[i + 1][j + 1] + 1
            } else {
                lengths[i + 1][j].max(lengths[i][j + 1])
            };
        }
    }

    let mut lines = Vec::new();
    let (mut i, mut j) = (0usize, 0usize);

    while i < n && j < m {
        if old[i] == new[j] {
            lines.push(DiffLine {
                kind: DiffKind::Same,
                text: old[i].to_string(),
            });
            i += 1;
            j += 1;
        } else if lengths[i + 1][j] >= lengths[i][j + 1] {
            lines.push(DiffLine {
                kind: DiffKind::Removed,
                text: old[i].to_string(),
            });
            i += 1;
        } else {
            lines.push(DiffLine {
                kind: DiffKind::Added,
                text: new[j].to_string(),
            });
            j += 1;
        }
    }

    while i < n {
        lines.push(DiffLine {
            kind: DiffKind::Removed,
            text: old[i].to_string(),
        });
        i += 1;
    }
    while j < m {
        lines.push(DiffLine {
            kind: DiffKind::Added,
            text: new[j].to_string(),
        });
        j += 1;
    }

    lines
}

/// The difference worked out by comparing the lines one against one.
///
/// This is the fallback for texts too long to work out properly: it says
/// which lines differ, not where the change was made.
fn diff_by_position(old: &[&str], new: &[&str]) -> Vec<DiffLine> {
    let mut lines = Vec::new();
    let shared = old.len().min(new.len());

    for i in 0..shared {
        if old[i] == new[i] {
            lines.push(DiffLine {
                kind: DiffKind::Same,
                text: old[i].to_string(),
            });
        } else {
            lines.push(DiffLine {
                kind: DiffKind::Removed,
                text: old[i].to_string(),
            });
            lines.push(DiffLine {
                kind: DiffKind::Added,
                text: new[i].to_string(),
            });
        }
    }

    for line in &old[shared..] {
        lines.push(DiffLine {
            kind: DiffKind::Removed,
            text: line.to_string(),
        });
    }
    for line in &new[shared..] {
        lines.push(DiffLine {
            kind: DiffKind::Added,
            text: line.to_string(),
        });
    }

    lines
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(lines: &[DiffLine]) -> Vec<DiffKind> {
        lines.iter().map(|line| line.kind).collect()
    }

    #[test]
    fn test_texts_that_are_the_same() {
        let lines = diff("one\ntwo\n", "one\ntwo\n");

        assert_eq!(kinds(&lines), vec![DiffKind::Same, DiffKind::Same]);
        assert_eq!(lines[0].text, "one");
    }

    #[test]
    fn test_a_changed_line() {
        let lines = diff("one\ntwo\n", "one\nthree\n");

        assert_eq!(
            kinds(&lines),
            vec![DiffKind::Same, DiffKind::Removed, DiffKind::Added]
        );
        assert_eq!(lines[1].text, "two");
        assert_eq!(lines[2].text, "three");
    }

    #[test]
    fn test_an_added_line() {
        let lines = diff("one\n", "one\ntwo\n");

        assert_eq!(kinds(&lines), vec![DiffKind::Same, DiffKind::Added]);
    }

    #[test]
    fn test_a_removed_line() {
        let lines = diff("one\ntwo\n", "one\n");

        assert_eq!(kinds(&lines), vec![DiffKind::Same, DiffKind::Removed]);
    }

    #[test]
    fn test_a_line_moved_down_is_shown_as_removed_and_added() {
        let lines = diff("one\ntwo\nthree\n", "two\none\nthree\n");

        // The line that moved cannot be "the same" in place, so it is shown
        // as removed and added; the line that stayed is kept.
        assert_eq!(lines[0].kind, DiffKind::Removed);
        assert_eq!(lines[0].text, "one");
        assert_eq!(lines[1].kind, DiffKind::Same);
        assert_eq!(lines[1].text, "two");
        assert_eq!(lines[2].kind, DiffKind::Added);
        assert_eq!(lines[2].text, "one");
        assert_eq!(lines[3].kind, DiffKind::Same);
        assert_eq!(lines[3].text, "three");
    }

    #[test]
    fn test_an_empty_text() {
        let lines = diff("", "one\n");

        assert_eq!(kinds(&lines), vec![DiffKind::Added]);
    }

    #[test]
    fn test_a_text_too_long_is_compared_line_by_line() {
        let old: String = (0..MAX_LINES + 10).map(|i| format!("line {i}\n")).collect();
        let new = old.replace("line 5\n", "line five\n");

        let lines = diff(&old, &new);

        assert!(lines
            .iter()
            .any(|line| line.kind == DiffKind::Added && line.text == "line five"));
    }
}
