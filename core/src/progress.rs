use std::sync::atomic::{AtomicUsize, Ordering};

static CURRENT_PROGRESS: AtomicUsize = AtomicUsize::new(0);
static TOTAL_PROGRESS: AtomicUsize = AtomicUsize::new(0);

pub fn set_total(total: usize) {
    TOTAL_PROGRESS.store(total, Ordering::SeqCst);
    CURRENT_PROGRESS.store(0, Ordering::SeqCst);
}

pub fn increment() {
    CURRENT_PROGRESS.fetch_add(1, Ordering::SeqCst);
}

pub fn reset() {
    TOTAL_PROGRESS.store(0, Ordering::SeqCst);
    CURRENT_PROGRESS.store(0, Ordering::SeqCst);
}

pub fn get_progress() -> (usize, usize) {
    (
        CURRENT_PROGRESS.load(Ordering::SeqCst),
        TOTAL_PROGRESS.load(Ordering::SeqCst),
    )
}
