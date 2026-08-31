// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_linux/src/native_frame_renderer.dart';

void main() {
  test('keeps the CSS viewport logical while sizing a HiDPI buffer', () {
    final geometry = normalizeWpeSurfaceGeometry(
      logicalWidth: 400.2,
      logicalHeight: 300.1,
      deviceScaleFactor: 2,
    );

    expect(geometry.logicalWidth, 401);
    expect(geometry.logicalHeight, 301);
    expect(geometry.scale, 2);
    expect(geometry.physicalWidth, 802);
    expect(geometry.physicalHeight, 602);
  });

  test('bounds scale and physical render-buffer dimensions', () {
    final geometry = normalizeWpeSurfaceGeometry(
      logicalWidth: 20000,
      logicalHeight: 9000,
      deviceScaleFactor: 10,
    );

    expect(geometry.scale, 4);
    expect(geometry.logicalWidth, 4096);
    expect(geometry.logicalHeight, 4096);
    expect(geometry.physicalWidth, 16384);
    expect(geometry.physicalHeight, 16384);
  });

  test('retains a valid fractional Linux display scale', () {
    final geometry = normalizeWpeSurfaceGeometry(
      logicalWidth: 800,
      logicalHeight: 600,
      deviceScaleFactor: 1.25,
    );

    expect(geometry.logicalWidth, 800);
    expect(geometry.logicalHeight, 600);
    expect(geometry.scale, 1.25);
    expect(geometry.physicalWidth, 1000);
    expect(geometry.physicalHeight, 750);
  });

  test('rejects non-finite, negative, and invalid scale values', () {
    expect(
      () => normalizeWpeSurfaceGeometry(
        logicalWidth: double.nan,
        logicalHeight: 1,
        deviceScaleFactor: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => normalizeWpeSurfaceGeometry(
        logicalWidth: 1,
        logicalHeight: -1,
        deviceScaleFactor: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => normalizeWpeSurfaceGeometry(
        logicalWidth: 1,
        logicalHeight: 1,
        deviceScaleFactor: 0,
      ),
      throwsArgumentError,
    );
  });
}
