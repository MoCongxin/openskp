import 'dart:io';

import 'package:openskp/openskp.dart';
import 'package:test/test.dart';

/// Real-file regression test for SkpFile.buildScene() - the opt-in
/// scene-hierarchy + triangulation + GLB mesh capability, ported from the
/// TypeScript reference implementation.
///
/// Root instance count is cross-validated directly against Python's and
/// TypeScript's build_scene()/buildScene() on this exact fixture.
/// Mesh/gltfMaterials counts (21/21/13) instead match C++'s
/// independently-verified reference for this file - the correct counts
/// once faces with genuinely different front/back materials are split
/// into two single-sided primitives each, rather than the pre-fix
/// single-sided-only count (13/13/9). This fixture has 30 such faces
/// (confirmed by direct inspection), so the split isn't a rare edge case
/// here.
void main() {
  final fixturePath = '${Directory.current.path}/test/fixtures/capilla_quiroz_v17.skp';

  test('buildScene matches Python and TypeScript ground truth', () {
    final scene = SkpFile.open(fixturePath).buildScene();

    expect(scene.glbPrimitives.length, 21);
    expect(scene.meshIndex.length, 21);
    expect(scene.gltfMaterials.length, 13);

    expect(scene.sceneHierarchy.name, 'ROOT');
    expect(scene.sceneHierarchy.definitionName, 'ROOT_MODEL');
    expect(scene.sceneHierarchy.children.length, 3);
    final defNames = scene.sceneHierarchy.children.map((c) => c.definitionName).toList()..sort();
    expect(defNames, ['grada', 'grada', 'puerta']);
  });

  test('primitives have valid geometry', () {
    final scene = SkpFile.open(fixturePath).buildScene();
    for (final prim in scene.glbPrimitives) {
      expect(prim.positions.length % 3, 0);
      expect(prim.normals.length, prim.positions.length);
      final nVerts = prim.positions.length ~/ 3;
      expect(prim.uvs.length, nVerts * 2);
      for (final uv in prim.uvs) {
        expect(uv.isNaN, false);
        expect(uv.isFinite, true);
      }
      expect(prim.indices.length % 3, 0);
      for (final idx in prim.indices) {
        expect(idx, inInclusiveRange(0, nVerts - 1));
      }
      expect(prim.materialIndex, inInclusiveRange(0, scene.gltfMaterials.length - 1));
    }
  });

  test('buildScene is independent of parse', () {
    // buildScene() must not require parse() to have been called first -
    // it re-parses independently.
    final scene = SkpFile.open(fixturePath).buildScene();
    expect(scene.glbPrimitives.length, 21);
  });

  test('renders back-face materials correctly (item 14 regression)', () {
    // This fixture has 30 faces (e.g. faces 133/152 in the 'puerta'
    // definition) whose front and back materials resolve to genuinely
    // different colors. Verified directly: front material 29 is blue
    // (2, 0, 237), back material 27 is light blue (204, 235, 244).
    final scene = SkpFile.open(fixturePath).buildScene();

    bool hasColor(int r, int g, int b) {
      return scene.gltfMaterials.any((m) {
        final pbr = m['pbrMetallicRoughness'] as Map<String, dynamic>;
        final c = pbr['baseColorFactor'] as List;
        return ((c[0] as double) * 255).round() == r &&
            ((c[1] as double) * 255).round() == g &&
            ((c[2] as double) * 255).round() == b;
      });
    }

    expect(hasColor(2, 0, 237), true);
    expect(hasColor(204, 235, 244), true);

    final doubleSidedCount = scene.gltfMaterials.where((m) => m['doubleSided'] == true).length;
    expect(doubleSidedCount, 4);
  });
}
