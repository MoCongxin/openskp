import 'dart:convert';
import 'dart:typed_data';

import 'package:openskp/src/vff.dart';
import 'package:test/test.dart';

/// SkpModel.units - the model's unit-system string, read from
/// meta/meta.dat in VFF files. Never opened by any parser before this
/// (zero references to the filename anywhere in the codebase). Confirmed
/// plaintext payload in a real fixture (Untitled.skp): meta.dat uses the
/// same low-level TLV framing as model.dat (2-byte tag + 4-byte
/// little-endian length + payload), one flat record list wrapped in a
/// single outer record (tag 0x6400); tag 0x6D00 carries the units string
/// as plain text.

Uint8List _tlv(int tagLo, int tagHi, Uint8List payload) {
  final out = Uint8List(6 + payload.length);
  out[0] = tagLo;
  out[1] = tagHi;
  final bd = ByteData.sublistView(out);
  bd.setUint32(2, payload.length, Endian.little);
  out.setRange(6, 6 + payload.length, payload);
  return out;
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  test('extracts units from the exact real fixture bytes', () {
    // The exact 388-byte meta/meta.dat payload from a real VFF fixture
    // (Untitled.skp, SketchUp 25.0.575) - byte-for-byte, not hand-crafted.
    final hex =
        '6400' '7e010000'
        '7500' '08000000' '${_hex('25.0.575')}'
        '7600' '02000000' '1800'
        '7700' '02000000' '0200'
        '7300' '02000000' '0100'
        '7400' '02000000' '1100'
        '6600' '10000000' 'dcd4752a383d724783022fa29cda3224'
        '6700' '2e000000' '2823' '28000000' '2923' '04000000' '04000000' '2a23' '18000000'
            '${_hex('meta/model_thumbnail.png')}'
        '6800' '30000000' '2823' '2a000000' '2923' '04000000' '04000000' '2a23' '1a000000'
            '${_hex('meta/preview_thumbnail.png')}'
        '6900' '01000000' '01'
        '6a00' '00000000'
        '6b00' '00000000'
        '6c00' '00000000'
        '6e00' '00000000'
        '7100' '01000000' '00'
        '7900' '01000000' '00'
        '7200' '01000000' '00'
        '6d00' '0a000000' '${_hex('Millimeter')}'
        '7000' '01000000' '01'
        '6f00' '27000000' '${_hex("E:/Devs/TEst/Skp Test/ref2/Untitled.skp")}'
        '7800' '52000000'
            'c800' '4c000000'
            'c900' '46000000'
            'ca00' '40000000'
            'cb00' '22000000' '${_hex('SketchUp Client (Windows) 25.0.575')}'
        'cc00' '04000000' '23c5326a'
        'cd00' '08000000' 'ec443dc9b4db9877';

    final bytes = _hexToBytes(hex);

    expect(Vff.readMetaUnits(bytes), 'Millimeter');
  });

  test('extracts units from a minimal synthetic record', () {
    final inner = _tlv(0x6d, 0x00, utf8.encode('Inches'));
    final outer = _tlv(0x64, 0x00, inner);
    expect(Vff.readMetaUnits(outer), 'Inches');
  });

  test('returns null when the units tag is absent', () {
    final inner = _tlv(0x75, 0x00, utf8.encode('25.0.575'));
    final outer = _tlv(0x64, 0x00, inner);
    expect(Vff.readMetaUnits(outer), isNull);
  });

  test('returns null for empty or truncated bytes', () {
    expect(Vff.readMetaUnits(Uint8List(0)), isNull);
    expect(Vff.readMetaUnits(Uint8List.fromList([1, 2, 3])), isNull);
  });
}

String _hex(String s) {
  final buf = StringBuffer();
  for (final b in utf8.encode(s)) {
    buf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}
