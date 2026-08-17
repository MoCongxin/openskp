import 'dart:io';

import 'package:openskp/openskp.dart';
import 'package:openskp/src/legacy.dart';
import 'package:test/test.dart';

/// Regression test for legacy (pre-2021 MFC) .skp files with fewer than two
/// materials.
///
/// The archive's absolute slot numbering is normally bootstrapped by
/// parsing two CMaterial records with a throwaway archive and reading the
/// second one's own class-ref tag - that trick needs at least 2 materials
/// and doesn't work for a file with 0 or 1. Every fixture that predates
/// this test (capilla_quiroz_v17.skp, gondola_v20.skp, Untitled.skp)
/// happens to have several materials, so this gap went unnoticed - see
/// openskp#158.
///
/// Fixtures: blank_v17.skp (0 materials) and single_material_v17.skp (1
/// material named "RedMat") - both saved as legacy v17 directly via the
/// official SketchUp SDK (SUModelSaveToFileWithVersion), so their content
/// is SketchUp's own built-in empty-document boilerplate plus one
/// synthetic material, not user/client data.
void main() {
  final blankPath = '${Directory.current.path}/test/fixtures/blank_v17.skp';
  final singleMatPath =
      '${Directory.current.path}/test/fixtures/single_material_v17.skp';

  test('detects both fixtures as legacy containers', () {
    expect(Legacy.isLegacy(File(blankPath).readAsBytesSync()), isTrue);
    expect(Legacy.isLegacy(File(singleMatPath).readAsBytesSync()), isTrue);
  });

  test(
      'parses a zero-material legacy file (no CMaterial record in the file at all)',
      () {
    final model = SkpFile.open(blankPath).parse();
    expect(model.version, '{17.0.1}');
    expect(model.materials.length, 0);
    expect(model.layers.map((l) => l.name).toList(), ['Layer0']);
    expect(model.definitions.length, 0);
    expect(model.root.instances.length, 0);
  });

  test('parses a single-material legacy file', () {
    final model = SkpFile.open(singleMatPath).parse();
    expect(model.version, '{17.0.1}');
    expect(model.materials.length, 1);
    expect(model.materials[0].name, 'RedMat');
    expect(model.layers.map((l) => l.name).toList(), ['Layer0']);
  });
}
