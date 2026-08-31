// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_prebuilt/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

/// Resolves and registers the Rust WebView bridge as a Dart code asset.
///
/// A checksummed prebuilt from [NativeProjectBuilder] takes precedence when the
/// manifest supports the requested target. Otherwise [RustBuilder] compiles
/// the bundled source. The hook tracks the Cargo inputs so fallback rebuilds
/// follow Rust changes. When an unpacked development WPE SDK exists under
/// `third_party`, its pkg-config metadata and libraries take precedence;
/// release consumers otherwise resolve WPE from their system toolchain.
void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final rustDirectory = Directory.fromUri(input.packageRoot.resolve('rust/'));
    output.dependencies.addAll([
      input.packageRoot.resolve('native_prebuilt.yaml'),
      input.packageRoot.resolve('rust/build.rs'),
      input.packageRoot.resolve('rust/Cargo.toml'),
      input.packageRoot.resolve('rust/Cargo.lock'),
      input.packageRoot.resolve('rust/rust-toolchain.toml'),
      ...rustDirectory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.rs'))
          .map((file) => file.uri),
    ]);

    final localWpeSdkDirectory = Directory.fromUri(
      input.packageRoot.resolve('third_party/wpe-sdk/usr/'),
    );

    var project = detect(Directory.fromUri(input.packageRoot));
    if (project == null) {
      throw StateError(
        'Could not load native_prebuilt.yaml from ${input.packageRoot}.',
      );
    }
    // Published applications prefer the verified release artifact. A Git
    // checkout must compile its local Rust tree, otherwise an edited package
    // can silently keep running the previous release binary. Source archives
    // without Git metadata can opt into the same behavior explicitly.
    final checkoutMarker = input.packageRoot.resolve('.git').toFilePath();
    final isGitCheckout =
        FileSystemEntity.typeSync(checkoutMarker, followLinks: false) !=
        FileSystemEntityType.notFound;
    if (isGitCheckout ||
        Platform.environment['WEBVIEW_FLUTTER_LINUX_FORCE_SOURCE_BUILD'] ==
            '1') {
      project = project.copyWith(
        prebuiltPolicy: PrebuiltPolicy.forceSourceBuild,
      );
    }

    final rustBuilder = RustBuilder(
      assetName: 'src/native_frame_bindings.dart',
      features: const ['wpe-runtime'],
      extraCargoEnvironmentVariables: localWpeSdkDirectory.existsSync()
          ? {
              'PKG_CONFIG_PATH': Directory.fromUri(
                localWpeSdkDirectory.uri.resolve('lib/pkgconfig/'),
              ).path,
              'LIBRARY_PATH': Directory.fromUri(
                localWpeSdkDirectory.uri.resolve('lib/'),
              ).path,
            }
          : const {},
    );

    await NativeProjectBuilder(
      project: project,
      sourceFallback: SourceFallback(
        sources: const [
          LocalSource(paths: ['.']),
        ],
        builder: HookBuilderSourceBuilder.static(rustBuilder),
      ),
    ).run(input: input, output: output, logger: null);
  });
}
