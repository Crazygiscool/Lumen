// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! Blocking AT-SPI work isolated from Flutter's platform thread.
//!
//! WebKit exposes accessibility through remote D-Bus objects. Reading a
//! complete tree can perform many bounded calls, and a disappearing WebProcess
//! can fail any one of them. The public FFI therefore only discovers WPE's
//! local socket identifier and exchanges owned messages with this worker. The
//! sibling `accessibility_dbus` module owns the wire protocol; this module owns
//! scheduling, tree generations, snapshot retention, and action routing.

use super::accessibility::{AccessibilityNodeMetadata, accessibility_snapshot_json};
use super::accessibility_dbus::{AccessibilityDbusClient, AccessibilityRemoteNode};
use super::prelude::*;
use std::sync::{
    Arc, Mutex, OnceLock,
    mpsc::{self, Receiver, Sender},
};

/// Immutable result copied back to the platform thread.
pub(super) struct AccessibilityWorkerResponse {
    pub(super) request_id: u64,
    pub(super) generation: u64,
    pub(super) available: bool,
    pub(super) occupied: bool,
    pub(super) truncated: bool,
    pub(super) node_count: usize,
    pub(super) json: Vec<u8>,
    pub(super) failed: bool,
}

enum AccessibilityCommand {
    Refresh(AccessibilityRefresh),
    Action(AccessibilityAction),
    DropView(u64),
}

struct AccessibilityRefresh {
    handle: u64,
    request_id: u64,
    generation_floor: u64,
    available: bool,
    occupied: bool,
    plug_id: Vec<u8>,
    maximum_nodes: usize,
}

enum AccessibilityAction {
    DoAction {
        handle: u64,
        generation: u64,
        node_index: usize,
        action_index: u32,
    },
    GrabFocus {
        handle: u64,
        generation: u64,
        node_index: usize,
    },
    SetText {
        handle: u64,
        generation: u64,
        node_index: usize,
        text: Vec<u8>,
    },
    SetSelection {
        handle: u64,
        generation: u64,
        node_index: usize,
        start_offset: i32,
        end_offset: i32,
    },
    AdjustValue {
        handle: u64,
        generation: u64,
        node_index: usize,
        direction: i32,
    },
}

struct AccessibilityWorker {
    commands: Sender<AccessibilityCommand>,
    responses: Arc<Mutex<HashMap<u64, AccessibilityWorkerResponse>>>,
    discarded_views: Arc<Mutex<HashSet<u64>>>,
}

struct AccessibilityWorkerNode {
    metadata: AccessibilityNodeMetadata,
    object: AccessibilityRemoteNode,
}

#[derive(Default)]
struct AccessibilityWorkerView {
    generation: u64,
    previous_generation: u64,
    available: bool,
    occupied: bool,
    truncated: bool,
    plug_id: Vec<u8>,
    root: Option<AccessibilityRemoteNode>,
    nodes: Vec<AccessibilityWorkerNode>,
    previous_nodes: Vec<AccessibilityWorkerNode>,
}

static ACCESSIBILITY_WORKER: OnceLock<Option<AccessibilityWorker>> = OnceLock::new();

fn worker() -> Option<&'static AccessibilityWorker> {
    ACCESSIBILITY_WORKER
        .get_or_init(|| {
            let (command_sender, command_receiver) = mpsc::channel();
            let responses = Arc::new(Mutex::new(HashMap::new()));
            let worker_responses = Arc::clone(&responses);
            let discarded_views = Arc::new(Mutex::new(HashSet::new()));
            let worker_discarded_views = Arc::clone(&discarded_views);
            std::thread::Builder::new()
                .name("webview-atspi".to_owned())
                .spawn(move || {
                    accessibility_worker_loop(
                        command_receiver,
                        worker_responses,
                        worker_discarded_views,
                    )
                })
                .ok()?;
            Some(AccessibilityWorker {
                commands: command_sender,
                responses,
                discarded_views,
            })
        })
        .as_ref()
}

/// Queues one tree refresh without waiting for remote D-Bus work.
pub(super) fn request_accessibility_refresh(
    handle: u64,
    request_id: u64,
    generation_floor: u64,
    available: bool,
    occupied: bool,
    plug_id: Vec<u8>,
    maximum_nodes: usize,
) -> bool {
    worker().is_some_and(|worker| {
        worker
            .commands
            .send(AccessibilityCommand::Refresh(AccessibilityRefresh {
                handle,
                request_id,
                generation_floor,
                available,
                occupied,
                plug_id,
                maximum_nodes,
            }))
            .is_ok()
    })
}

/// Takes the most recent completed refresh for one native handle.
pub(super) fn take_accessibility_response(handle: u64) -> Option<AccessibilityWorkerResponse> {
    let worker = worker()?;
    worker
        .responses
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&handle)
}

/// Starts releasing worker-owned state for a disposed native view.
///
/// Returns `true` when no worker owns data for this process, so the caller may
/// release its WPE runtime immediately. `false` means `DropView` was queued and
/// the caller must retain the runtime until
/// [`take_accessibility_worker_view_discarded`] acknowledges completion.
/// The acknowledgement also prevents queued work for an old handle from being
/// confused with a subsequently created view.
pub(super) fn begin_accessibility_worker_view_discard(handle: u64) -> bool {
    let Some(worker) = ACCESSIBILITY_WORKER.get().and_then(Option::as_ref) else {
        return true;
    };
    worker
        .responses
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&handle);
    worker
        .discarded_views
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&handle);
    worker
        .commands
        .send(AccessibilityCommand::DropView(handle))
        .is_err()
}

/// Consumes the exactly-once acknowledgement for a worker-side view release.
pub(super) fn take_accessibility_worker_view_discarded(handle: u64) -> bool {
    let Some(worker) = ACCESSIBILITY_WORKER.get().and_then(Option::as_ref) else {
        return true;
    };
    take_discard_acknowledgement(&worker.discarded_views, handle)
}

fn publish_discard_acknowledgement(discarded_views: &Mutex<HashSet<u64>>, handle: u64) {
    discarded_views
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .insert(handle);
}

fn take_discard_acknowledgement(discarded_views: &Mutex<HashSet<u64>>, handle: u64) -> bool {
    discarded_views
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&handle)
}

fn queue_action(action: AccessibilityAction) -> bool {
    worker().is_some_and(|worker| {
        worker
            .commands
            .send(AccessibilityCommand::Action(action))
            .is_ok()
    })
}

pub(super) fn queue_accessibility_action(
    handle: u64,
    generation: u64,
    node_index: usize,
    action_index: u32,
) -> bool {
    queue_action(AccessibilityAction::DoAction {
        handle,
        generation,
        node_index,
        action_index,
    })
}

pub(super) fn queue_accessibility_focus(handle: u64, generation: u64, node_index: usize) -> bool {
    queue_action(AccessibilityAction::GrabFocus {
        handle,
        generation,
        node_index,
    })
}

pub(super) fn queue_accessibility_text(
    handle: u64,
    generation: u64,
    node_index: usize,
    text: Vec<u8>,
) -> bool {
    queue_action(AccessibilityAction::SetText {
        handle,
        generation,
        node_index,
        text,
    })
}

pub(super) fn queue_accessibility_selection(
    handle: u64,
    generation: u64,
    node_index: usize,
    start_offset: i32,
    end_offset: i32,
) -> bool {
    queue_action(AccessibilityAction::SetSelection {
        handle,
        generation,
        node_index,
        start_offset,
        end_offset,
    })
}

pub(super) fn queue_accessibility_value_adjustment(
    handle: u64,
    generation: u64,
    node_index: usize,
    direction: i32,
) -> bool {
    queue_action(AccessibilityAction::AdjustValue {
        handle,
        generation,
        node_index,
        direction,
    })
}

fn accessibility_worker_loop(
    commands: Receiver<AccessibilityCommand>,
    responses: Arc<Mutex<HashMap<u64, AccessibilityWorkerResponse>>>,
    discarded_views: Arc<Mutex<HashSet<u64>>>,
) {
    // Both the connection and every remote object reference remain confined to
    // this thread. Synchronous calls are safe here because each has a short
    // timeout and the Flutter platform thread only exchanges owned messages.
    let mut dbus = None;
    let mut views = HashMap::<u64, AccessibilityWorkerView>::new();
    while let Ok(command) = commands.recv() {
        match command {
            AccessibilityCommand::Refresh(refresh) => {
                let handle = refresh.handle;
                let view = views.entry(handle).or_default();
                let response = refresh_worker_view(&mut dbus, view, refresh);
                responses
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .insert(handle, response);
            }
            AccessibilityCommand::Action(action) => {
                if let Some(dbus) = dbus.as_ref() {
                    perform_accessibility_action(dbus, &mut views, action);
                }
            }
            AccessibilityCommand::DropView(handle) => {
                views.remove(&handle);
                responses
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .remove(&handle);
                publish_discard_acknowledgement(&discarded_views, handle);
            }
        }
    }
}

fn refresh_worker_view(
    dbus: &mut Option<AccessibilityDbusClient>,
    view: &mut AccessibilityWorkerView,
    refresh: AccessibilityRefresh,
) -> AccessibilityWorkerResponse {
    let AccessibilityRefresh {
        request_id,
        generation_floor,
        available,
        occupied,
        plug_id,
        maximum_nodes,
        ..
    } = refresh;
    view.generation = view.generation.max(generation_floor);
    if !available || !occupied {
        view.plug_id.clear();
        view.root = None;
        return commit_worker_snapshot(view, request_id, available, occupied, false, Vec::new());
    }

    if dbus.is_none() {
        *dbus = AccessibilityDbusClient::connect().ok();
    }
    let Some(dbus) = dbus.as_ref() else {
        return failed_worker_response(view, request_id, available, occupied);
    };

    let Some(root) = accessibility_remote_root(&plug_id, view) else {
        return failed_worker_response(view, request_id, available, occupied);
    };
    match collect_accessibility_nodes(dbus, root, maximum_nodes) {
        Ok((nodes, truncated)) => {
            commit_worker_snapshot(view, request_id, available, occupied, truncated, nodes)
        }
        Err(()) => failed_worker_response(view, request_id, available, occupied),
    }
}

fn commit_worker_snapshot(
    view: &mut AccessibilityWorkerView,
    request_id: u64,
    available: bool,
    occupied: bool,
    truncated: bool,
    nodes: Vec<AccessibilityWorkerNode>,
) -> AccessibilityWorkerResponse {
    let unchanged = view.generation != 0
        && view.available == available
        && view.occupied == occupied
        && view.truncated == truncated
        && view.nodes.len() == nodes.len()
        && view
            .nodes
            .iter()
            .zip(&nodes)
            .all(|(old, new)| old.metadata == new.metadata);
    if !unchanged {
        view.previous_generation = view.generation;
        view.previous_nodes = std::mem::take(&mut view.nodes);
        view.generation = view.generation.wrapping_add(1).max(1);
    }
    view.available = available;
    view.occupied = occupied;
    view.truncated = truncated;
    view.nodes = nodes;
    let metadata = view
        .nodes
        .iter()
        .map(|node| node.metadata.clone())
        .collect::<Vec<_>>();
    AccessibilityWorkerResponse {
        request_id,
        generation: view.generation,
        available,
        occupied,
        truncated,
        node_count: metadata.len(),
        json: accessibility_snapshot_json(
            view.generation,
            available,
            occupied,
            truncated,
            &metadata,
        ),
        failed: false,
    }
}

fn failed_worker_response(
    view: &AccessibilityWorkerView,
    request_id: u64,
    available: bool,
    occupied: bool,
) -> AccessibilityWorkerResponse {
    AccessibilityWorkerResponse {
        request_id,
        generation: view.generation,
        available,
        occupied,
        truncated: true,
        node_count: view.nodes.len(),
        json: Vec::new(),
        failed: true,
    }
}

fn accessibility_remote_root(
    plug_id: &[u8],
    view: &mut AccessibilityWorkerView,
) -> Option<AccessibilityRemoteNode> {
    if view.plug_id == plug_id {
        return view.root.clone();
    }
    let Some(root) = AccessibilityRemoteNode::from_plug_id(plug_id) else {
        view.plug_id.clear();
        view.root = None;
        return None;
    };
    view.plug_id = plug_id.to_vec();
    view.root = Some(root.clone());
    Some(root)
}

fn collect_accessibility_nodes(
    dbus: &AccessibilityDbusClient,
    root: AccessibilityRemoteNode,
    maximum_nodes: usize,
) -> Result<(Vec<AccessibilityWorkerNode>, bool), ()> {
    let mut stack = vec![(root, -1)];
    let mut visited = HashSet::<AccessibilityRemoteNode>::new();
    let mut nodes = Vec::new();
    let mut truncated = false;
    while let Some((object, parent_index)) = stack.pop() {
        if nodes.len() >= maximum_nodes {
            truncated = true;
            break;
        }
        if !visited.insert(object.clone()) {
            continue;
        }
        let snapshot = dbus.snapshot_node(&object, parent_index)?;
        let node_index = i32::try_from(nodes.len()).unwrap_or(i32::MAX);
        nodes.push(AccessibilityWorkerNode {
            metadata: snapshot.metadata,
            object: object.clone(),
        });
        for child in snapshot.children.into_iter().rev() {
            stack.push((child, node_index));
        }
    }
    if !stack.is_empty() {
        truncated = true;
    }
    Ok((nodes, truncated))
}

fn with_worker_node(
    views: &mut HashMap<u64, AccessibilityWorkerView>,
    handle: u64,
    generation: u64,
    node_index: usize,
    operation: impl FnOnce(&AccessibilityRemoteNode),
) {
    let Some(view) = views.get(&handle) else {
        return;
    };
    if generation == 0 {
        return;
    }
    let nodes = if view.generation == generation {
        &view.nodes
    } else if view.previous_generation == generation {
        &view.previous_nodes
    } else {
        return;
    };
    let Some(node) = nodes.get(node_index) else {
        return;
    };
    operation(&node.object);
}

fn perform_accessibility_action(
    dbus: &AccessibilityDbusClient,
    views: &mut HashMap<u64, AccessibilityWorkerView>,
    action: AccessibilityAction,
) {
    match action {
        AccessibilityAction::DoAction {
            handle,
            generation,
            node_index,
            action_index,
        } => with_worker_node(views, handle, generation, node_index, |object| {
            dbus.do_action(object, action_index)
        }),
        AccessibilityAction::GrabFocus {
            handle,
            generation,
            node_index,
        } => with_worker_node(views, handle, generation, node_index, |object| {
            dbus.grab_focus(object)
        }),
        AccessibilityAction::SetText {
            handle,
            generation,
            node_index,
            text,
        } => with_worker_node(views, handle, generation, node_index, |object| {
            dbus.set_text(object, &text)
        }),
        AccessibilityAction::SetSelection {
            handle,
            generation,
            node_index,
            start_offset,
            end_offset,
        } => with_worker_node(views, handle, generation, node_index, |object| {
            dbus.set_selection(object, start_offset, end_offset)
        }),
        AccessibilityAction::AdjustValue {
            handle,
            generation,
            node_index,
            direction,
        } => with_worker_node(views, handle, generation, node_index, |object| {
            dbus.adjust_value(object, direction)
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn node(name: &[u8]) -> AccessibilityWorkerNode {
        let object = AccessibilityRemoteNode::from_plug_id(b":1.1:/test/node").unwrap();
        AccessibilityWorkerNode {
            metadata: AccessibilityNodeMetadata {
                object_identity: name.to_vec(),
                parent_index: -1,
                role: b"button".to_vec(),
                name: name.to_vec(),
                description: Vec::new(),
                value: Vec::new(),
                x: 0,
                y: 0,
                width: 100,
                height: 40,
                states: 0,
                actions: vec![b"press".to_vec()],
            },
            object,
        }
    }

    #[test]
    fn retains_exactly_one_previous_generation_for_delayed_actions() {
        let mut view = AccessibilityWorkerView {
            generation: 1,
            ..AccessibilityWorkerView::default()
        };
        let first = commit_worker_snapshot(&mut view, 1, true, true, false, vec![node(b"first")]);
        assert_eq!(first.generation, 2);

        let second = commit_worker_snapshot(&mut view, 2, true, true, false, vec![node(b"second")]);
        assert_eq!(second.generation, 3);

        let mut views = HashMap::from([(7, view)]);
        let previous_called = Cell::new(false);
        with_worker_node(&mut views, 7, 2, 0, |_| previous_called.set(true));
        assert!(previous_called.get());
        let current_called = Cell::new(false);
        with_worker_node(&mut views, 7, 3, 0, |_| current_called.set(true));
        assert!(current_called.get());

        let view = views.get_mut(&7).unwrap();
        let third = commit_worker_snapshot(view, 3, true, true, false, vec![node(b"third")]);
        assert_eq!(third.generation, 4);
        let expired_called = Cell::new(false);
        with_worker_node(&mut views, 7, 2, 0, |_| expired_called.set(true));
        assert!(!expired_called.get());
    }

    #[test]
    fn consumes_each_discard_acknowledgement_exactly_once() {
        let acknowledgements = Mutex::new(HashSet::new());
        publish_discard_acknowledgement(&acknowledgements, 7);
        publish_discard_acknowledgement(&acknowledgements, 11);

        assert!(take_discard_acknowledgement(&acknowledgements, 7));
        assert!(!take_discard_acknowledgement(&acknowledgements, 7));
        assert!(take_discard_acknowledgement(&acknowledgements, 11));
        assert!(!take_discard_acknowledgement(&acknowledgements, 11));
    }
}
