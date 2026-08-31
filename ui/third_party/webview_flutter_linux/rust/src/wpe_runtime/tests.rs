// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! State-only tests for WPE runtime helpers and queue invariants.

use super::{navigation, prelude::*, requests, settings, storage};

#[test]
fn validates_android_compatible_text_zoom_percentages() {
    assert_eq!(settings::text_zoom_factor(10), Some(0.1));
    assert_eq!(settings::text_zoom_factor(100), Some(1.0));
    assert_eq!(settings::text_zoom_factor(250), Some(2.5));
    assert_eq!(settings::text_zoom_factor(1_000), Some(10.0));
    assert_eq!(settings::text_zoom_factor(9), None);
    assert_eq!(settings::text_zoom_factor(1_001), None);
}

#[test]
fn accepts_only_public_wpe_cookie_policy_values() {
    assert!(storage::cookie_accept_policy_is_valid(0));
    assert!(storage::cookie_accept_policy_is_valid(1));
    assert!(storage::cookie_accept_policy_is_valid(2));
    assert!(!storage::cookie_accept_policy_is_valid(-1));
    assert!(!storage::cookie_accept_policy_is_valid(3));
}

#[test]
fn blocks_only_geolocation_requests_when_the_per_view_gate_is_disabled() {
    assert!(geolocation_permission_blocked(1 << 3, false));
    assert!(geolocation_permission_blocked((1 << 3) | (1 << 4), false));
    assert!(!geolocation_permission_blocked(1 << 3, true));
    assert!(!geolocation_permission_blocked(1 << 0, false));
    assert!(!geolocation_permission_blocked(0, false));
}

#[test]
fn maps_only_permission_names_with_host_decision_paths() {
    assert_eq!(
        requests::permission_query_resource_type(b"camera"),
        Some(1 << 0)
    );
    assert_eq!(
        requests::permission_query_resource_type(b"microphone"),
        Some(1 << 1)
    );
    assert_eq!(
        requests::permission_query_resource_type(b"display-capture"),
        Some(1 << 2)
    );
    assert_eq!(
        requests::permission_query_resource_type(b"geolocation"),
        Some(1 << 3)
    );
    assert_eq!(
        requests::permission_query_resource_type(b"notifications"),
        Some(1 << 4)
    );
    assert_eq!(
        requests::permission_query_resource_type(b"persistent-storage"),
        None
    );
}

#[test]
fn validates_and_bounds_navigation_frame_hints() {
    let main = navigation::navigation_frame_hint(b"M\nhttps://example.test/main")
        .expect("main-frame hint");
    assert!(main.is_main_frame);
    assert_eq!(main.url, b"https://example.test/main");

    let subframe =
        navigation::navigation_frame_hint(b"S\nhttps://example.test/frame").expect("subframe hint");
    assert!(!subframe.is_main_frame);
    assert_eq!(subframe.url, b"https://example.test/frame");
    assert!(navigation::navigation_frame_hint(b"X\ninvalid").is_none());
    assert!(navigation::navigation_frame_hint(b"Mmissing-separator").is_none());

    let mut hints = VecDeque::new();
    for index in 0..65 {
        navigation::enqueue_navigation_frame_hint(
            &mut hints,
            navigation::NavigationFrameHint {
                url: index.to_string().into_bytes(),
                is_main_frame: index % 2 == 0,
            },
        );
    }
    assert_eq!(hints.len(), 64);
    assert_eq!(
        hints.front().map(|hint| hint.url.as_slice()),
        Some(b"1".as_slice())
    );
    assert_eq!(
        hints.back().map(|hint| hint.url.as_slice()),
        Some(b"64".as_slice())
    );
}

#[test]
fn permission_decisions_are_origin_scoped_and_split_combined_requests() {
    let mut states = HashMap::new();
    let first_origin = b"https://first.example";
    let second_origin = b"https://second.example";

    requests::remember_permission_decision(&mut states, first_origin, (1 << 0) | (1 << 1), true);

    assert_eq!(
        requests::remembered_permission_state(&states, first_origin, Some(1 << 0)),
        0
    );
    assert_eq!(
        requests::remembered_permission_state(&states, first_origin, Some(1 << 1)),
        0
    );
    assert_eq!(
        requests::remembered_permission_state(&states, second_origin, Some(1 << 0)),
        2
    );
    assert_eq!(
        requests::remembered_permission_state(&states, first_origin, None),
        2
    );

    requests::remember_permission_decision(&mut states, first_origin, 1 << 1, false);
    assert_eq!(
        requests::remembered_permission_state(&states, first_origin, Some(1 << 0)),
        0
    );
    assert_eq!(
        requests::remembered_permission_state(&states, first_origin, Some(1 << 1)),
        1
    );
}

#[test]
fn builds_the_public_webkit_post_history_variant_with_binary_body() {
    let body = b"alpha\0beta\xff";
    let item = post_history_item_variant(
        "https://example.com/submit",
        body,
        "application/octet-stream",
    );
    assert_eq!(item.type_().as_str(), BACK_FORWARD_LIST_ITEM_TYPE_V2);

    let frame = item.child_value(1);
    let optional_body = frame.child_value(10);
    assert_eq!(optional_body.n_children(), 1);
    let http_body = optional_body.child_value(0);
    assert_eq!(
        http_body.try_child_get::<String>(0).unwrap(),
        Some("application/octet-stream".to_string())
    );
    let elements = http_body.child_value(1);
    assert_eq!(elements.n_children(), 1);
    assert_eq!(
        elements.child_value(0).try_child_get::<Vec<u8>>(1).unwrap(),
        Some(body.to_vec())
    );

    let item_type = glib::VariantTy::new(BACK_FORWARD_LIST_ITEM_TYPE_V2).unwrap();
    let items = glib::Variant::array_from_iter_with_type(item_type, [item]);
    let session = glib::Variant::tuple_from_iter([
        2_u16.to_variant(),
        items,
        glib::Variant::from_some(&0_u32.to_variant()),
    ]);
    assert_eq!(session.type_().as_str(), SESSION_STATE_TYPE_V2);
    assert!(session.is_normal_form());
}

#[test]
fn registers_and_instantiates_the_toolkit_free_input_context() {
    let type_ = flutter_input_method_context_get_type();
    assert_ne!(type_, glib::gobject_ffi::G_TYPE_INVALID);

    let object = unsafe { glib::gobject_ffi::g_object_new(type_, std::ptr::null::<c_char>()) };
    assert!(!object.is_null());
    let context = object.cast::<WebKitInputMethodContext>();
    let adapter = unsafe { flutter_input_method_context(context) };
    assert!(adapter.owner.is_null());
    assert_eq!(adapter.preedit_enabled, 1);

    let mut text = std::ptr::null_mut();
    let mut underlines = std::ptr::null_mut();
    let mut cursor = u32::MAX;
    unsafe {
        flutter_input_method_get_preedit(context, &mut text, &mut underlines, &mut cursor);
    }
    assert!(!text.is_null());
    assert_eq!(unsafe { CStr::from_ptr(text) }.to_bytes(), b"");
    assert!(underlines.is_null());
    assert_eq!(cursor, 0);
    unsafe {
        glib::ffi::g_free(text.cast());
        glib::gobject_ffi::g_object_unref(object);
    }
}

#[test]
fn translates_flutter_usb_hid_to_webkit_xkb_keycode() {
    assert_eq!(xkb_keycode_from_usb_hid(0x0007_0004), 0x26);
    assert_eq!(xkb_keycode_from_usb_hid(0x0007_0028), 0x24);
}

#[test]
fn translates_ctrl_a_logical_key_without_text() {
    assert_eq!(xkb_keyval(0x41, 0x0007_0004, 0), u32::from(b'a'));
}

#[test]
fn encodes_non_latin_unicode_keyvals() {
    assert_eq!(unicode_to_xkb_keyval(0x1f642), 0x0101_f642);
}

#[test]
fn coalesces_only_adjacent_progress_events() {
    let mut events = VecDeque::new();
    enqueue_navigation_event(
        &mut events,
        NavigationEventSnapshot {
            kind: NAVIGATION_EVENT_STARTED,
            url: b"https://example.com".to_vec(),
            progress: 0,
            code: 0,
            detail: Vec::new(),
            is_main_frame: 1,
        },
    );
    enqueue_navigation_event(
        &mut events,
        NavigationEventSnapshot {
            kind: NAVIGATION_EVENT_PROGRESS,
            url: b"https://example.com".to_vec(),
            progress: 10,
            code: 0,
            detail: Vec::new(),
            is_main_frame: 1,
        },
    );
    enqueue_navigation_event(
        &mut events,
        NavigationEventSnapshot {
            kind: NAVIGATION_EVENT_PROGRESS,
            url: b"https://example.com".to_vec(),
            progress: 45,
            code: 0,
            detail: Vec::new(),
            is_main_frame: 1,
        },
    );
    enqueue_navigation_event(
        &mut events,
        NavigationEventSnapshot {
            kind: NAVIGATION_EVENT_FINISHED,
            url: b"https://example.com".to_vec(),
            progress: 100,
            code: 0,
            detail: Vec::new(),
            is_main_frame: 1,
        },
    );

    assert_eq!(events.len(), 3);
    assert_eq!(events[1].kind, NAVIGATION_EVENT_PROGRESS);
    assert_eq!(events[1].progress, 45);
    assert_eq!(events[2].kind, NAVIGATION_EVENT_FINISHED);
}

#[test]
fn suppresses_finished_once_after_a_main_frame_failure() {
    let failed = Cell::new(false);
    assert!(should_enqueue_main_frame_lifecycle(
        NAVIGATION_EVENT_STARTED,
        &failed,
    ));
    failed.set(true);
    assert!(!should_enqueue_main_frame_lifecycle(
        NAVIGATION_EVENT_FINISHED,
        &failed,
    ));
    assert!(!failed.get());

    assert!(should_enqueue_main_frame_lifecycle(
        NAVIGATION_EVENT_STARTED,
        &failed,
    ));
    assert!(should_enqueue_main_frame_lifecycle(
        NAVIGATION_EVENT_FINISHED,
        &failed,
    ));
}

#[test]
fn classifies_only_redirects_during_a_provisional_main_frame_load() {
    assert!(navigation::is_provisional_main_frame_redirect(true, true));
    assert!(!navigation::is_provisional_main_frame_redirect(false, true));
    assert!(!navigation::is_provisional_main_frame_redirect(true, false));
}

#[test]
fn bounds_the_navigation_queue() {
    let mut events = VecDeque::new();
    for index in 0..=MAX_NAVIGATION_EVENTS {
        enqueue_navigation_event(
            &mut events,
            NavigationEventSnapshot {
                kind: NAVIGATION_EVENT_COMMITTED,
                url: index.to_string().into_bytes(),
                progress: 0,
                code: 0,
                detail: Vec::new(),
                is_main_frame: 1,
            },
        );
    }

    assert_eq!(events.len(), MAX_NAVIGATION_EVENTS);
    assert_eq!(
        events.front().map(|event| event.url.as_slice()),
        Some(b"1".as_slice())
    );
}

#[test]
fn queues_only_owned_popup_children_once_and_within_the_bound() {
    let owned_handles: HashSet<u64> = (1..=(MAX_POPUP_REQUESTS as u64 + 1)).collect();
    let mut requests = VecDeque::new();

    assert!(!enqueue_popup_snapshot(
        &owned_handles,
        &mut requests,
        999,
        b"https://not-owned.invalid",
    ));
    assert!(enqueue_popup_snapshot(
        &owned_handles,
        &mut requests,
        1,
        b"https://first.example",
    ));
    assert!(!enqueue_popup_snapshot(
        &owned_handles,
        &mut requests,
        1,
        b"https://duplicate.example",
    ));
    for handle in 2..=MAX_POPUP_REQUESTS as u64 {
        assert!(enqueue_popup_snapshot(
            &owned_handles,
            &mut requests,
            handle,
            handle.to_string().as_bytes(),
        ));
    }
    assert!(!enqueue_popup_snapshot(
        &owned_handles,
        &mut requests,
        MAX_POPUP_REQUESTS as u64 + 1,
        b"https://over-cap.example",
    ));

    assert_eq!(requests.len(), MAX_POPUP_REQUESTS);
    assert_eq!(
        requests.front().map(|request| request.child_handle),
        Some(1)
    );
    assert_eq!(
        requests.front().map(|request| request.url.as_slice()),
        Some(b"https://first.example".as_slice()),
    );
}

#[test]
fn preserves_bounded_effective_fullscreen_transitions() {
    let mut events = VecDeque::new();
    enqueue_fullscreen_snapshot(&mut events, true);
    enqueue_fullscreen_snapshot(&mut events, true);
    enqueue_fullscreen_snapshot(&mut events, false);
    assert_eq!(events, VecDeque::from([true, false]));

    for index in 0..=(MAX_FULLSCREEN_EVENTS * 2) {
        enqueue_fullscreen_snapshot(&mut events, index.is_multiple_of(2));
    }
    assert_eq!(events.len(), MAX_FULLSCREEN_EVENTS);
    assert_eq!(events.back().copied(), Some(true));
}

#[test]
fn coalesces_only_adjacent_progress_for_the_same_download() {
    let event = |id, kind, received_bytes| DownloadEventSnapshot {
        id,
        kind,
        received_bytes,
        content_length: 100,
        error_code: 0,
        destination: b"/tmp/file".to_vec(),
        detail: Vec::new(),
    };
    let mut events = VecDeque::new();
    enqueue_download_event(&mut events, event(1, DOWNLOAD_EVENT_CREATED_DESTINATION, 0));
    enqueue_download_event(&mut events, event(1, DOWNLOAD_EVENT_PROGRESS, 10));
    enqueue_download_event(&mut events, event(1, DOWNLOAD_EVENT_PROGRESS, 50));
    enqueue_download_event(&mut events, event(2, DOWNLOAD_EVENT_PROGRESS, 20));
    enqueue_download_event(&mut events, event(1, DOWNLOAD_EVENT_FINISHED, 100));

    assert_eq!(events.len(), 4);
    assert_eq!(events[1].id, 1);
    assert_eq!(events[1].received_bytes, 50);
    assert_eq!(events[2].id, 2);
    assert_eq!(events[3].kind, DOWNLOAD_EVENT_FINISHED);
}

#[test]
fn describes_every_web_process_termination_reason() {
    assert_eq!(
        web_process_termination_description(0),
        b"WPE WebKit web process crashed."
    );
    assert_eq!(
        web_process_termination_description(1),
        b"WPE WebKit web process exceeded its memory limit."
    );
    assert_eq!(
        web_process_termination_description(2),
        b"WPE WebKit web process was terminated by an API request."
    );
    assert_eq!(
        web_process_termination_description(99),
        b"WPE WebKit web process terminated for an unknown reason."
    );
}

#[test]
fn preserves_every_javascript_completion_and_request_id() {
    let mut results = VecDeque::new();
    enqueue_javascript_result(
        &mut results,
        JavaScriptResultSnapshot {
            request_id: 41,
            status: JAVASCRIPT_RESULT_SUCCESS,
            payload: b"42".to_vec(),
        },
    );
    enqueue_javascript_result(
        &mut results,
        JavaScriptResultSnapshot {
            request_id: 42,
            status: JAVASCRIPT_RESULT_ERROR,
            payload: b"boom".to_vec(),
        },
    );

    assert_eq!(results.len(), 2);
    assert_eq!(results[0].request_id, 41);
    assert_eq!(results[0].payload, b"42");
    assert_eq!(results[1].request_id, 42);
    assert_eq!(results[1].status, JAVASCRIPT_RESULT_ERROR);
}

#[test]
fn preserves_cookie_completion_metadata_and_fields() {
    COOKIE_RESULTS.with_borrow_mut(|results| {
        results.clear();
        results.push_back(CookieResultSnapshot {
            request_id: 73,
            status: COOKIE_RESULT_SUCCESS,
            had_cookies: 1,
            accept_policy: 2,
            error: Vec::new(),
            cookies: vec![CookieSnapshot {
                name: b"session".to_vec(),
                value: b"active".to_vec(),
                domain: b"example.com".to_vec(),
                path: b"/account".to_vec(),
            }],
        });
    });

    assert_eq!(webview_flutter_linux_cookie_result_count(), 1);
    assert_eq!(webview_flutter_linux_cookie_result_request_id(), 73);
    assert_eq!(webview_flutter_linux_cookie_result_had_cookies(), 1);
    assert_eq!(webview_flutter_linux_cookie_result_accept_policy(), 2);
    assert_eq!(webview_flutter_linux_cookie_result_cookie_count(), 1);
    assert_eq!(
        with_cookie_field(0, 0, 0, |bytes| bytes.len()),
        b"session".len()
    );
    assert_eq!(webview_flutter_linux_cookie_result_pop(), 0);
    assert_eq!(webview_flutter_linux_cookie_result_count(), 0);
}

#[test]
fn preserves_website_data_completion_ids_and_errors() {
    WEBSITE_DATA_RESULTS.with_borrow_mut(|results| {
        results.clear();
        results.push_back(WebsiteDataResultSnapshot {
            request_id: 81,
            status: WEBSITE_DATA_RESULT_ERROR,
            error: b"clear failed".to_vec(),
        });
        results.push_back(WebsiteDataResultSnapshot {
            request_id: 82,
            status: WEBSITE_DATA_RESULT_SUCCESS,
            error: Vec::new(),
        });
    });

    assert_eq!(webview_flutter_linux_website_data_result_count(), 2);
    assert_eq!(webview_flutter_linux_website_data_result_request_id(), 81);
    assert_eq!(
        webview_flutter_linux_website_data_result_error_length(),
        b"clear failed".len()
    );
    assert_eq!(webview_flutter_linux_website_data_result_pop(), 0);
    assert_eq!(webview_flutter_linux_website_data_result_request_id(), 82);
    assert_eq!(webview_flutter_linux_website_data_result_status(), 0);
    assert_eq!(webview_flutter_linux_website_data_result_pop(), 0);
}

#[test]
fn escapes_arbitrary_javascript_channel_names() {
    assert_eq!(javascript_string_literal("Echo"), "\"Echo\"");
    assert_eq!(
        javascript_string_literal("odd\"\\\n\u{2028}name"),
        "\"odd\\\"\\\\\\n\\u2028name\""
    );
    assert_eq!(
        javascript_channel_wrapper("dash-channel"),
        "Object.defineProperty(window,\"dash-channel\",{configurable:true,value:window.webkit.messageHandlers[\"dash-channel\"]});"
    );
}

#[test]
fn preserves_every_javascript_channel_message() {
    let mut messages = VecDeque::new();
    messages.push_back(JavaScriptMessageSnapshot {
        channel: b"Echo".to_vec(),
        message: b"first".to_vec(),
    });
    messages.push_back(JavaScriptMessageSnapshot {
        channel: b"Echo".to_vec(),
        message: b"second".to_vec(),
    });

    assert_eq!(messages.len(), 2);
    assert_eq!(
        messages.pop_front().map(|message| message.message),
        Some(b"first".to_vec())
    );
    assert_eq!(
        messages.pop_front().map(|message| message.message),
        Some(b"second".to_vec())
    );
}

#[test]
fn copies_null_terminated_file_chooser_string_arrays() {
    let mime_type = std::ffi::CString::new("text/plain").unwrap();
    let extension = std::ffi::CString::new(".md").unwrap();
    let values = [mime_type.as_ptr(), extension.as_ptr(), std::ptr::null()];

    let copied = unsafe { foreign_string_array(values.as_ptr()) };

    assert_eq!(copied, vec![b"text/plain".to_vec(), b".md".to_vec()]);
    assert!(unsafe { foreign_string_array(std::ptr::null()) }.is_empty());
}

#[test]
fn builds_page_presentation_css_for_independent_axes_and_overscroll() {
    assert!(page_presentation_style(true, true, 1).is_empty());

    let style = page_presentation_style(false, true, 2);
    assert!(style.contains("scrollbar:vertical"));
    assert!(!style.contains("scrollbar:horizontal"));
    assert!(style.contains("overscroll-behavior:none"));

    let style = page_presentation_style(true, false, 0);
    assert!(!style.contains("scrollbar:vertical"));
    assert!(style.contains("scrollbar:horizontal"));
    assert!(!style.contains("overscroll-behavior:none"));
}

#[test]
fn advances_cursor_generation_only_for_effective_changes() {
    let mut cursor = CursorSnapshot::default();
    assert_eq!(cursor.generation, 1);
    assert!(!cursor.update(CursorData::Named(b"default".to_vec())));
    assert_eq!(cursor.generation, 1);

    assert!(cursor.update(CursorData::Named(b"pointer".to_vec())));
    assert_eq!(cursor.generation, 2);
    assert!(!cursor.update(CursorData::Named(b"pointer".to_vec())));
    assert_eq!(cursor.generation, 2);
}

#[test]
fn strips_custom_cursor_stride_padding() {
    let source = [
        1, 2, 3, 4, 5, 6, 7, 8, 99, 98, 97, 96, 9, 10, 11, 12, 13, 14, 15, 16, 95, 94, 93, 92,
    ];
    let cursor = custom_cursor_data(&source, 2, 2, 12, 1, 0);
    let Some(CursorData::Custom {
        width,
        height,
        hotspot_x,
        hotspot_y,
        pixels,
    }) = cursor
    else {
        panic!("expected a valid custom cursor");
    };
    assert_eq!((width, height), (2, 2));
    assert_eq!((hotspot_x, hotspot_y), (1, 0));
    assert_eq!(
        pixels,
        vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
    );
}

#[test]
fn rejects_invalid_custom_cursor_shapes() {
    let bytes = vec![0; 16];
    assert!(custom_cursor_data(&bytes, 0, 1, 4, 0, 0).is_none());
    assert!(custom_cursor_data(&bytes, 2, 2, 4, 0, 0).is_none());
    assert!(custom_cursor_data(&bytes, 1, 1, 4, 1, 0).is_none());
    assert!(custom_cursor_data(&bytes, MAX_CURSOR_DIMENSION + 1, 1, 4, 0, 0).is_none());
}

#[test]
fn maps_every_dart_touch_transition_to_wpe() {
    assert_eq!(wpe_touch_event_type(0), Some(WPE_EVENT_TOUCH_DOWN));
    assert_eq!(wpe_touch_event_type(1), Some(WPE_EVENT_TOUCH_MOVE));
    assert_eq!(wpe_touch_event_type(2), Some(WPE_EVENT_TOUCH_UP));
    assert_eq!(wpe_touch_event_type(3), Some(WPE_EVENT_TOUCH_CANCEL));
    assert_eq!(wpe_touch_event_type(4), None);
}

#[test]
fn maps_pointer_exit_to_wpe_leave() {
    assert_eq!(wpe_pointer_move_event_type(0), Some(WPE_EVENT_POINTER_MOVE));
    assert_eq!(
        wpe_pointer_move_event_type(1),
        Some(WPE_EVENT_POINTER_LEAVE)
    );
    assert_eq!(
        wpe_pointer_move_event_type(2),
        Some(WPE_EVENT_POINTER_ENTER)
    );
    assert_eq!(wpe_pointer_move_event_type(3), None);
}

#[test]
fn converts_monotonic_microseconds_to_wrapping_wpe_milliseconds() {
    assert_eq!(wpe_event_time_from_monotonic_micros(-1), 0);
    assert_eq!(wpe_event_time_from_monotonic_micros(999), 0);
    assert_eq!(wpe_event_time_from_monotonic_micros(1_234_999), 1_234);
    assert_eq!(
        wpe_event_time_from_monotonic_micros((u32::MAX as i64 + 1) * 1_000),
        0,
    );
}

#[test]
fn bounds_scroll_lifecycle_settling_to_recent_input() {
    assert_eq!(settings::scroll_lifecycle_settle_delay_micros(0, 1), 0);
    assert_eq!(
        settings::scroll_lifecycle_settle_delay_micros(1_000_000, 1_000_000),
        250_000,
    );
    assert_eq!(
        settings::scroll_lifecycle_settle_delay_micros(1_000_000, 1_100_000),
        150_000,
    );
    assert_eq!(
        settings::scroll_lifecycle_settle_delay_micros(1_000_000, 1_250_000),
        0,
    );
    assert_eq!(
        settings::scroll_lifecycle_settle_delay_micros(1_000_000, 999_000),
        250_000,
    );
}

#[test]
fn excludes_certificate_challenges_from_http_username_password_flow() {
    for scheme in [1, 2, 3, 4, 5, 6, 100, 101] {
        assert!(supports_username_password_authentication(scheme));
    }
    for scheme in 7..=9 {
        assert!(!supports_username_password_authentication(scheme));
    }
}

#[test]
fn extracts_tls_exception_hosts_without_ports_or_ipv6_brackets() {
    assert_eq!(
        host_from_https_uri("https://example.com:9443/path"),
        Some(b"example.com".to_vec())
    );
    assert_eq!(
        host_from_https_uri("https://[::1]:9443/path"),
        Some(b"::1".to_vec())
    );
    assert_eq!(host_from_https_uri("http://example.com"), None);
    assert_eq!(host_from_https_uri("https:///missing-host"), None);
}

#[test]
fn validates_logical_surface_size_and_physical_scale_product() {
    assert!(valid_surface_geometry(800, 600, 2.0));
    assert!(valid_surface_geometry(13_107, 600, 1.25));
    assert!(!valid_surface_geometry(0, 600, 1.0));
    assert!(!valid_surface_geometry(800, 600, f64::NAN));
    assert!(!valid_surface_geometry(800, 600, 0.0));
    assert!(!valid_surface_geometry(8193, 600, 2.0));
    assert!(!valid_surface_geometry(16_385, 600, 0.5));
}
