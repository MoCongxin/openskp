import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:openskp/src/errors.dart';
import 'package:openskp/src/vff.dart';
import 'package:test/test.dart';

/// A ZIP entry's declared uncompressed size (ArchiveFile.size) is
/// untrusted central-directory metadata - it can be set independently of
/// what the compressed stream actually decompresses to, and even when
/// genuine, DEFLATE can expand highly compressible data by three orders of
/// magnitude. ArchiveFile.content decompresses (and so allocates) up to
/// that declared size with no ceiling of its own, so these tests exercise
/// Vff.validateEntrySize's compression-ratio guard against that.

ArchiveFile _buildEntry(Uint8List content) {
  final archive = Archive();
  archive.add(ArchiveFile.bytes('payload.dat', content));
  final zipBytes = ZipEncoder().encodeBytes(archive, level: DeflateLevel.bestCompression);
  final decoded = ZipDecoder().decodeBytes(zipBytes);
  return decoded.findFile('payload.dat')!;
}

void main() {
  test('rejects an implausible compression ratio', () {
    // 8 MB of zeros deflates to a few hundred bytes - a ratio well past
    // what real (binary geometry) model.dat entries show (~10x), the
    // shape of a declared-size decompression bomb: tiny real payload,
    // huge claimed size.
    final entry = _buildEntry(Uint8List(8 * 1024 * 1024));

    expect(
      () => Vff.validateEntrySize(entry),
      throwsA(isA<SkpParseException>().having(
        (e) => e.message,
        'message',
        contains('compression ratio'),
      )),
    );
  });

  test('allows a realistic compression ratio', () {
    // Pseudo-random content compresses poorly (ratio close to 1x),
    // comfortably under the safety threshold.
    final rng = Random(42);
    final random = Uint8List.fromList(List<int>.generate(64 * 1024, (_) => rng.nextInt(256)));
    final entry = _buildEntry(random);

    Vff.validateEntrySize(entry); // must not throw
  });

  test('allows a tiny entry regardless of ratio', () {
    // Below the 1 MB ratio-check threshold, even a high ratio is allowed
    // through - the absolute cost is bounded regardless.
    final entry = _buildEntry(Uint8List(1024));

    Vff.validateEntrySize(entry); // must not throw
  });

  test('allows an empty entry', () {
    final entry = _buildEntry(Uint8List(0));

    Vff.validateEntrySize(entry); // must not throw
  });
}
