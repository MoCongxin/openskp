import 'dart:convert';
import 'dart:io';

import 'package:openskp/openskp.dart';
import 'package:test/test.dart';

/// Real-file regression test for toJson() - openskp's canonical JSON
/// export schema, shared with the Python (to_dict) and TypeScript
/// (toJSON) ports. Cross-checked directly against both on this exact
/// fixture.
void main() {
  final fixturePath = '${Directory.current.path}/test/fixtures/capilla_quiroz_v17.skp';

  test('matches Python/TypeScript ground truth on a real file', () {
    final model = SkpFile.open(fixturePath).parse();
    final d = toJson(model);

    expect(d['format_version'], '1.0');
    expect(d['sketchup_version'], '{17.0.18899}');
    expect(d['total_definitions'], 2);
    expect(d['total_layers'], 1);
    expect(d['total_meshes'], 0);

    final root = d['root'] as Map<String, dynamic>;
    expect(root['vertex_count'], 251);
    expect(root['edge_count'], 390);
    expect(root['face_count'], 146);
    expect((root['instances'] as List).length, 3);
    expect(
      (root['instances'][0] as Map<String, dynamic>).keys.toSet(),
      {'name', 'ref_idx', 'guid', 'matrix'},
    );

    final definitions = d['definitions'] as Map<String, dynamic>;
    final puerta = definitions.values.firstWhere((v) => v['name'] == 'puerta') as Map<String, dynamic>;
    expect(puerta['id'], 40);
    expect(puerta['vertex_count'], 64);
    expect(puerta['edge_count'], 95);
    expect(puerta['face_count'], 24);
    expect((puerta['edges'] as List).length, 95);
    expect((puerta['faces'] as List).length, 24);

    final layers = d['layers'] as List;
    expect(layers[0]['color'], {'r': 255, 'g': 84, 'b': 84});

    expect(d['mesh_index'], {});
    expect(d['scene_hierarchy'], null);
  });

  test('includes scene_hierarchy/mesh_index when a scene is passed', () {
    final model = SkpFile.open(fixturePath).parse();
    final scene = SkpFile.open(fixturePath).buildScene();
    final d = toJson(model, scene);

    expect(d['total_meshes'], scene.meshIndex.length);
    final hierarchy = d['scene_hierarchy'] as Map<String, dynamic>;
    expect(hierarchy['name'], 'ROOT');
    expect(hierarchy.containsKey('definition_name'), true);
    expect(hierarchy.containsKey('position_mm'), true);

    final meshIndex = d['mesh_index'] as Map<String, dynamic>;
    final firstMesh = meshIndex.values.first as Map<String, dynamic>;
    expect(firstMesh.containsKey('definition_name'), true);
    expect(firstMesh.containsKey('position_mm'), true);
  });

  test('produces JSON-encodable output', () {
    final model = SkpFile.open(fixturePath).parse();
    final scene = SkpFile.open(fixturePath).buildScene();
    final d = toJson(model, scene);
    expect(() => jsonEncode(d), returnsNormally);
  });
}
