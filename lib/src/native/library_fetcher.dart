// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 stockfish_dart authors

/// Downloads, verifies and caches prebuilt libraries for the build hook.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'native_manifest.dart';

/// Thrown when a library can't be obtained or fails verification.
final class LibraryFetchException implements Exception {
  /// Creates the exception.
  LibraryFetchException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => 'stockfish_dart: $message';
}

/// Fetches the files of one target into [cacheDirectory].
final class LibraryFetcher {
  /// Creates a fetcher.
  LibraryFetcher({
    required this.cacheDirectory,
    required this.baseUrl,
    this.log = _noLog,
    this.retries = 3,
    HttpClient Function()? httpClient,
  }) : _httpClient = httpClient ?? _defaultClient;

  /// Directory holding verified libraries (all files of one target side by
  /// side, as the dispatcher expects).
  final Directory cacheDirectory;

  /// URL the manifest's asset names are resolved against.
  final Uri baseUrl;

  /// Progress output.
  final void Function(String message) log;

  /// Download attempts per file.
  final int retries;

  final HttpClient Function() _httpClient;

  static void _noLog(String _) {}

  static HttpClient _defaultClient() =>
      HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;

  /// Returns verified local copies of [files], downloading what is missing.
  Future<List<File>> fetch(List<ManifestFile> files) async {
    await cacheDirectory.create(recursive: true);
    final result = <File>[];
    for (final f in files) {
      result.add(await _fetchOne(f));
    }
    return result;
  }

  Future<File> _fetchOne(ManifestFile entry) async {
    final file = File(
      '${cacheDirectory.path}${Platform.pathSeparator}${entry.name}',
    );
    final marker = File('${file.path}.sha256');
    if (await file.exists() &&
        await marker.exists() &&
        (await marker.readAsString()).trim() == entry.sha256 &&
        await file.length() == entry.size) {
      return file;
    }

    final url = baseUrl.resolve(entry.asset);
    Object? lastError;
    for (var attempt = 1; attempt <= retries; attempt++) {
      try {
        log('Downloading $url (attempt $attempt)');
        await _download(url, entry, file);
        await marker.writeAsString(entry.sha256);
        return file;
      } on LibraryFetchException {
        rethrow;
      } catch (e) {
        lastError = e;
        if (attempt < retries) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
      }
    }
    throw LibraryFetchException(
      'Could not download $url: $lastError. Set the user-define '
      'stockfish_dart.library_dir or stockfish_dart.download_base_url in your '
      'pubspec.yaml to build offline or through a mirror.',
    );
  }

  Future<void> _download(Uri url, ManifestFile entry, File target) async {
    final client = _httpClient();
    final part = File('${target.path}.$pid.part');
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      // Decompress while hashing the decompressed bytes.
      final sink = part.openWrite();
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var size = 0;
      final stream = url.path.endsWith('.gz')
          ? response.transform(gzip.decoder)
          : response;
      await for (final chunk in stream) {
        size += chunk.length;
        hasher.add(chunk);
        sink.add(chunk);
      }
      hasher.close();
      await sink.close();

      final hash = digestSink.value.toString();
      if (hash != entry.sha256 || size != entry.size) {
        await part.delete();
        throw LibraryFetchException(
          'Checksum mismatch for ${entry.name} from $url: expected '
          '${entry.sha256} (${entry.size} bytes), got $hash ($size bytes).',
        );
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } finally {
      client.close(force: true);
      if (await part.exists()) {
        try {
          await part.delete();
        } on FileSystemException {
          // Best effort.
        }
      }
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Hex SHA-256 of a file.
Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();
