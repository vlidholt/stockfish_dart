// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:stockfish_dart/src/native/library_fetcher.dart';
import 'package:stockfish_dart/src/native/native_manifest.dart';
import 'package:stockfish_dart/src/native/native_targets.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Directory cache;
  final requests = <String>[];
  final assets = <String, List<int>>{};
  var failNext = 0;

  setUp(() async {
    requests.clear();
    assets.clear();
    failNext = 0;
    cache = await Directory.systemTemp.createTemp('sfd-cache');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final name = request.uri.pathSegments.last;
      requests.add(name);
      if (failNext > 0) {
        failNext--;
        request.response.statusCode = HttpStatus.serviceUnavailable;
      } else if (assets[name] case final bytes?) {
        request.response.add(bytes);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await cache.delete(recursive: true);
  });

  LibraryFetcher fetcher() => LibraryFetcher(
    cacheDirectory: cache,
    baseUrl: Uri.parse('http://127.0.0.1:${server.port}/release/'),
    retries: 2,
  );

  ManifestFile publish(String name, List<int> content, {List<int>? served}) {
    final asset = 'linux-x64-$name.gz';
    assets[asset] = gzip.encode(served ?? content);
    return ManifestFile(
      name: name,
      asset: asset,
      sha256: sha256.convert(content).toString(),
      size: content.length,
    );
  }

  test('downloads, decompresses and verifies', () async {
    final entry = publish(
      'libstockfish.so',
      List.generate(5000, (i) => i % 251),
    );
    final files = await fetcher().fetch([entry]);
    expect(files.single.readAsBytesSync(), hasLength(5000));
    expect(await sha256OfFile(files.single), entry.sha256);
    expect(requests, ['linux-x64-libstockfish.so.gz']);
  });

  test('uses the cache on the second fetch', () async {
    final entry = publish('libstockfish.so', [1, 2, 3]);
    await fetcher().fetch([entry]);
    await fetcher().fetch([entry]);
    expect(requests, hasLength(1));
  });

  test('rejects a checksum mismatch', () async {
    final entry = publish('libstockfish.so', [1, 2, 3], served: [9, 9, 9]);
    await expectLater(
      fetcher().fetch([entry]),
      throwsA(
        isA<LibraryFetchException>().having(
          (e) => e.message,
          'message',
          contains('Checksum mismatch'),
        ),
      ),
    );
    expect(cache.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('retries transient failures', () async {
    final entry = publish('libstockfish.so', [4, 5, 6]);
    failNext = 1;
    final files = await fetcher().fetch([entry]);
    expect(files.single.readAsBytesSync(), [4, 5, 6]);
    expect(requests, hasLength(2));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('gives up with a helpful message', () async {
    const entry = ManifestFile(
      name: 'libstockfish.so',
      asset: 'missing.gz',
      sha256: '00',
      size: 1,
    );
    await expectLater(
      fetcher().fetch([entry]),
      throwsA(
        isA<LibraryFetchException>().having(
          (e) => e.message,
          'message',
          contains('library_dir'),
        ),
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  group('manifest', () {
    test('round trip', () {
      const m = NativeManifest(
        release: 'native-v1',
        baseUrl: 'https://example.com/',
        targets: {
          'linux-x64': [
            ManifestFile(
              name: 'a.so',
              asset: 'linux-x64-a.so.gz',
              sha256: 'ab',
              size: 3,
            ),
          ],
        },
      );
      final parsed = NativeManifest.parse(m.toJson());
      expect(parsed.release, 'native-v1');
      expect(parsed.targets['linux-x64']!.single.sha256, 'ab');
    });

    test('the checked-in manifest parses and names every target file', () {
      final m = NativeManifest.load(File('native/manifest.json'));
      for (final MapEntry(:key, :value) in m.targets.entries) {
        final target = NativeTarget.parse(key);
        expect(value.map((f) => f.name).toSet(), {
          target.dispatcherFileName,
          for (final v in target.variants) target.variantFileName(v),
        });
      }
    });
  });
}
