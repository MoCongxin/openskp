import 'dart:typed_data';

import 'package:openskp/src/legacy.dart';
import 'package:test/test.dart';

/// Both MFC class-ref encodings the definition-tail scanner must match.
/// Mirrors packages/python/tests/test_parser.py::TestLegacyClassRef
/// (openskp#28 / #39): once a class slot passes 0x7FFF the short 16-bit
/// form 0x8000|slot can't fit, so MFC escalates to the big-tag escape
/// (0x7FFF followed by a u32 of 0x80000000|slot).
void main() {
  group('isClassRef', () {
    test('matches the short form', () {
      final data = Uint8List(2);
      ByteData.sublistView(data).setUint16(0, 0x8000 | 278, Endian.little);
      expect(isClassRef(data, 0, 278), isTrue);
      expect(isClassRef(data, 0, 279), isFalse);
    });

    test('matches the big-tag escape', () {
      // slot 65712 does not fit in 0x8000|slot: MFC writes 0x7FFF + u32
      final data = Uint8List(6);
      final view = ByteData.sublistView(data);
      view.setUint16(0, 0x7FFF, Endian.little);
      view.setUint32(2, 0x80000000 | 65712, Endian.little);
      expect(isClassRef(data, 0, 65712), isTrue);
      expect(isClassRef(data, 0, 65713), isFalse);
    });

    test('never matches a big slot via the truncated short form', () {
      // the pre-fix scanner compared a u16 read against 0x8000|65712, which
      // cannot fit in 16 bits - the truncated value must not match
      final data = Uint8List(2);
      ByteData.sublistView(data)
          .setUint16(0, (0x8000 | 65712) & 0xFFFF, Endian.little);
      expect(isClassRef(data, 0, 65712), isFalse);
    });

    test('rejects truncated data', () {
      final data = Uint8List.fromList([0xFF, 0x7F, 0xB0]);
      expect(isClassRef(data, 0, 65712), isFalse);
    });
  });
}
