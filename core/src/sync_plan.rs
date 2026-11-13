//! The three-way plan that decides what a sync does with each note.
//!
//! A sync compares three sets of notes:
//!
//!   - the **local** ones, as they are on this device right now,
//!   - the **remote** ones, as the other side says they are,
//!   - the **base**, the notes as they were the last time both sides
//!     agreed.
//!
//! The base is what makes the difference between "the other side changed
//! this note" and "both sides changed this note". Without it every note
//! that differs would look like a conflict, and a journal could never be
//! synced twice without asking the user about every note.
//!
//! The plan itself is pure: it takes the three sets and says what should
//! happen to each note. Nothing is read, written or sent here, so the
//! decisions can be worked out — and tested — on their own.

use std::collections::{BTreeMap, BTreeSet};

/// The fingerprint of a note: the hash of its encrypted bytes.
///
/// The encrypted bytes are what every device agrees on: the file is
/// encrypted once, by the device that wrote the note, and every other
/// device stores those same bytes. Hashing the plain text would not work,
/// because two devices that write the same words encrypt them differently.
pub type Manifest = BTreeMap<String, String>;

/// What the sync does with one note.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncAction {
    /// Send the local note to the other side.
    Push,
    /// Take the note from the other side.
    Pull,
    /// The note is gone locally; remove it on the other side.
    DeleteRemote,
    /// The note is gone on the other side; remove it here.
    DeleteLocal,
    /// Both sides changed the note; leave both alone and report it.
    Conflict,
    /// Nothing to do.
    None,
}

impl SyncAction {
    /// Whether the action changes something.
    pub fn is_work(&self) -> bool {
        !matches!(self, SyncAction::None)
    }
}

/// Work out what to do with every note.
///
/// The three sets hold the notes of both sides and the notes they last
/// agreed on. Every note that is in any of them gets an action, so a note
/// that is gone from one side is not forgotten.
pub fn plan(local: &Manifest, remote: &Manifest, base: &Manifest) -> BTreeMap<String, SyncAction> {
    let mut paths: BTreeSet<&str> = BTreeSet::new();
    paths.extend(local.keys().map(String::as_str));
    paths.extend(remote.keys().map(String::as_str));
    paths.extend(base.keys().map(String::as_str));

    let mut actions = BTreeMap::new();
    for path in paths {
        let action = match (local.get(path), remote.get(path), base.get(path)) {
            // Both sides have the same note.
            (Some(l), Some(r), _) if l == r => SyncAction::None,

            // The note is not on either side any more. Both sides removed
            // it, so there is nothing left to do.
            (None, None, _) => SyncAction::None,

            // The note was never synced: it is new on one side, or on both.
            (Some(_), None, None) => SyncAction::Push,
            (None, Some(_), None) => SyncAction::Pull,
            (Some(_), Some(_), None) => SyncAction::Conflict,

            // The note was synced before, and only one side changed it.
            (Some(l), Some(_), Some(b)) if l == b => SyncAction::Pull,
            (Some(_), Some(r), Some(b)) if r == b => SyncAction::Push,

            // The note was synced before, and it is gone from one side.
            // The other side did not change it, so the removal is carried
            // over; if it did change it, the two disagree and the user is
            // asked.
            (None, Some(r), Some(b)) if r == b => SyncAction::DeleteRemote,
            (Some(l), None, Some(b)) if l == b => SyncAction::DeleteLocal,

            // One side removed the note and the other changed it.
            (None, Some(_), Some(_)) => SyncAction::Conflict,
            (Some(_), None, Some(_)) => SyncAction::Conflict,

            // Both sides changed the note.
            (Some(_), Some(_), Some(_)) => SyncAction::Conflict,
        };
        actions.insert(path.to_string(), action);
    }

    actions
}

/// The notes the other side should have after the sync.
///
/// The notes that were pushed are already in it, the ones that were pulled
/// are on the other side already, and the ones that conflicted keep the
/// version the other side has: the sync does not decide which of the two
/// is the right one, the user does.
pub fn merged_remote(
    local: &Manifest,
    remote: &Manifest,
    actions: &BTreeMap<String, SyncAction>,
) -> Manifest {
    let mut merged = local.clone();
    for (path, action) in actions {
        match action {
            // The other side already has these; its version is the one that
            // stays there.
            SyncAction::Pull | SyncAction::Conflict => {
                if let Some(hash) = remote.get(path) {
                    merged.insert(path.clone(), hash.clone());
                }
            }
            // The note is gone on both sides now.
            SyncAction::DeleteRemote | SyncAction::DeleteLocal => {
                merged.remove(path);
            }
            _ => {}
        }
    }
    merged
}

/// The base the next sync starts from.
///
/// The notes that conflicted keep the base they had, so the conflict is
/// still there next time — until the user has had a look at it and made a
/// choice.
pub fn merged_base(
    previous_base: &Manifest,
    merged_remote: &Manifest,
    actions: &BTreeMap<String, SyncAction>,
) -> Manifest {
    let mut base = merged_remote.clone();
    for (path, action) in actions {
        if *action == SyncAction::Conflict {
            match previous_base.get(path) {
                Some(hash) => {
                    base.insert(path.clone(), hash.clone());
                }
                None => {
                    base.remove(path);
                }
            }
        }
    }
    base
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest(pairs: &[(&str, &str)]) -> Manifest {
        pairs
            .iter()
            .map(|(path, hash)| (path.to_string(), hash.to_string()))
            .collect()
    }

    #[test]
    fn a_note_that_is_the_same_on_both_sides_is_left_alone() {
        let notes = manifest(&[("a.md", "1")]);
        let actions = plan(&notes, &notes, &notes);
        assert_eq!(actions["a.md"], SyncAction::None);
    }

    #[test]
    fn a_new_local_note_is_pushed() {
        let actions = plan(&manifest(&[("a.md", "1")]), &manifest(&[]), &manifest(&[]));
        assert_eq!(actions["a.md"], SyncAction::Push);
    }

    #[test]
    fn a_new_remote_note_is_pulled() {
        let actions = plan(&manifest(&[]), &manifest(&[("a.md", "1")]), &manifest(&[]));
        assert_eq!(actions["a.md"], SyncAction::Pull);
    }

    #[test]
    fn a_note_only_the_local_side_changed_is_pushed() {
        let actions = plan(
            &manifest(&[("a.md", "new")]),
            &manifest(&[("a.md", "old")]),
            &manifest(&[("a.md", "old")]),
        );
        assert_eq!(actions["a.md"], SyncAction::Push);
    }

    #[test]
    fn a_note_only_the_remote_side_changed_is_pulled() {
        let actions = plan(
            &manifest(&[("a.md", "old")]),
            &manifest(&[("a.md", "new")]),
            &manifest(&[("a.md", "old")]),
        );
        assert_eq!(actions["a.md"], SyncAction::Pull);
    }

    #[test]
    fn a_note_both_sides_changed_is_a_conflict() {
        let actions = plan(
            &manifest(&[("a.md", "mine")]),
            &manifest(&[("a.md", "theirs")]),
            &manifest(&[("a.md", "old")]),
        );
        assert_eq!(actions["a.md"], SyncAction::Conflict);
    }

    #[test]
    fn a_note_both_sides_created_is_a_conflict() {
        let actions = plan(
            &manifest(&[("a.md", "mine")]),
            &manifest(&[("a.md", "theirs")]),
            &manifest(&[]),
        );
        assert_eq!(actions["a.md"], SyncAction::Conflict);
    }

    #[test]
    fn a_note_only_the_local_side_removed_is_removed_remotely() {
        let actions = plan(
            &manifest(&[]),
            &manifest(&[("a.md", "old")]),
            &manifest(&[("a.md", "old")]),
        );
        assert_eq!(actions["a.md"], SyncAction::DeleteRemote);
    }

    #[test]
    fn a_note_only_the_remote_side_removed_is_removed_locally() {
        let actions = plan(
            &manifest(&[("a.md", "old")]),
            &manifest(&[]),
            &manifest(&[("a.md", "old")]),
        );
        assert_eq!(actions["a.md"], SyncAction::DeleteLocal);
    }

    #[test]
    fn a_note_one_side_removed_and_the_other_changed_is_a_conflict() {
        let actions = plan(
            &manifest(&[("a.md", "changed")]),
            &manifest(&[]),
            &manifest(&[("a.md", "old")]),
        );
        assert_eq!(actions["a.md"], SyncAction::Conflict);

        let actions = plan(
            &manifest(&[]),
            &manifest(&[("a.md", "changed")]),
            &manifest(&[("a.md", "old")]),
        );
        assert_eq!(actions["a.md"], SyncAction::Conflict);
    }

    #[test]
    fn a_note_both_sides_removed_is_left_alone() {
        let actions = plan(
            &manifest(&[]),
            &manifest(&[]),
            &manifest(&[("a.md", "old")]),
        );
        assert_eq!(actions["a.md"], SyncAction::None);
    }

    #[test]
    fn the_merged_remote_manifest_holds_the_notes_of_both_sides() {
        let local = manifest(&[("kept.md", "1"), ("pushed.md", "2")]);
        let remote = manifest(&[("kept.md", "1"), ("pulled.md", "3")]);
        let base = manifest(&[("kept.md", "1")]);

        let actions = plan(&local, &remote, &base);
        let merged = merged_remote(&local, &remote, &actions);

        assert_eq!(merged["kept.md"], "1");
        assert_eq!(merged["pushed.md"], "2");
        assert_eq!(merged["pulled.md"], "3");
    }

    #[test]
    fn a_conflicted_note_keeps_the_version_of_the_other_side_in_the_manifest() {
        let local = manifest(&[("a.md", "mine")]);
        let remote = manifest(&[("a.md", "theirs")]);
        let base = manifest(&[("a.md", "old")]);

        let actions = plan(&local, &remote, &base);
        let merged = merged_remote(&local, &remote, &actions);
        assert_eq!(merged["a.md"], "theirs");
    }

    #[test]
    fn a_conflicted_note_keeps_its_base_so_the_conflict_stays() {
        let local = manifest(&[("a.md", "mine")]);
        let remote = manifest(&[("a.md", "theirs")]);
        let base = manifest(&[("a.md", "old")]);

        let actions = plan(&local, &remote, &base);
        let merged = merged_remote(&local, &remote, &actions);
        let next_base = merged_base(&base, &merged, &actions);

        assert_eq!(next_base["a.md"], "old");

        // The next sync sees the same conflict again.
        let actions = plan(&local, &remote, &next_base);
        assert_eq!(actions["a.md"], SyncAction::Conflict);
    }

    #[test]
    fn a_removed_note_is_gone_from_the_merged_manifest() {
        let local = manifest(&[]);
        let remote = manifest(&[("a.md", "old")]);
        let base = manifest(&[("a.md", "old")]);

        let actions = plan(&local, &remote, &base);
        let merged = merged_remote(&local, &remote, &actions);
        assert!(!merged.contains_key("a.md"));
    }
}
