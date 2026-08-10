import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:openskp/openskp.dart';
import 'package:test/test.dart';

Scene _triangleScene() {
  return Scene(
    sceneHierarchy: InstanceNode(),
    meshIndex: {},
    gltfMaterials: [
      {
        'pbrMetallicRoughness': {
          'baseColorFactor': [0.25, 0.5, 0.75, 1.0],
          'metallicFactor': 0.1,
          'roughnessFactor': 0.9,
        },
      },
    ],
    glbPrimitives: [
      GlbPrimitive(
        positions: [1, 2, 3, -4, 5, 0, 2, -1, 7],
        normals: [0, 0, 1, 0, 0, 1, 0, 0, 1],
        uvs: [0, 0, 1, 0, 0, 1],
        indices: [0, 1, 2],
        materialIndex: 0,
        geomName: 'triangle',
      ),
    ],
  );
}

({Map<String, dynamic> json, Uint8List binary}) _parseGlb(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final jsonChunkLen = bd.getUint32(12, Endian.little);
  final jsonStr = utf8.decode(bytes.sublist(20, 20 + jsonChunkLen));
  final json = jsonDecode(jsonStr) as Map<String, dynamic>;

  final binHeaderOffset = 20 + jsonChunkLen;
  var binary = Uint8List(0);
  if (binHeaderOffset < bytes.length) {
    final binChunkLen = bd.getUint32(binHeaderOffset, Endian.little);
    binary = bytes.sublist(binHeaderOffset + 8, binHeaderOffset + 8 + binChunkLen);
  }
  return (json: json, binary: binary);
}

void main() {
  group('GLB export', () {
    test('serializes scene and binary data', () {
      final bytes = toGlb(_triangleScene());
      expect(bytes.length, greaterThanOrEqualTo(12));
      expect(utf8.decode(bytes.sublist(0, 4)), 'glTF');

      final parsed = _parseGlb(bytes);
      final json = parsed.json;
      expect(json['asset']['version'], '2.0');

      final meshes = json['meshes'] as List;
      expect(meshes.length, 1);
      final prim = (meshes[0]['primitives'] as List)[0] as Map<String, dynamic>;
      final attrs = prim['attributes'] as Map<String, dynamic>;
      expect(attrs.containsKey('POSITION'), true);
      expect(attrs.containsKey('NORMAL'), true);
      expect(attrs.containsKey('TEXCOORD_0'), true);
      expect(prim['material'], 0);

      final accessors = json['accessors'] as List;
      final posAccessor = accessors[attrs['POSITION'] as int] as Map<String, dynamic>;
      expect(posAccessor['componentType'], 5126);
      expect(posAccessor['type'], 'VEC3');
      expect(posAccessor['count'], 3);
      expect(posAccessor['min'], [-4.0, -1.0, 0.0]);
      expect(posAccessor['max'], [2.0, 5.0, 7.0]);

      final uvAccessor = accessors[attrs['TEXCOORD_0'] as int] as Map<String, dynamic>;
      expect(uvAccessor['componentType'], 5126);
      expect(uvAccessor['type'], 'VEC2');
      expect(uvAccessor['count'], 3);
      final uvBufferView = (json['bufferViews'] as List)[uvAccessor['bufferView'] as int] as Map<String, dynamic>;
      final uvOffset = uvBufferView['byteOffset'] as int;
      final bd = ByteData.sublistView(parsed.binary);
      expect(bd.getFloat32(uvOffset + 2 * 4, Endian.little), 1.0);

      final materials = json['materials'] as List;
      final pbr = materials[0]['pbrMetallicRoughness'] as Map<String, dynamic>;
      expect(pbr['baseColorFactor'][0], 0.25);
      expect(pbr['metallicFactor'], 0.1);
      expect(pbr['roughnessFactor'], 0.9);
    });

    test('serializes an empty scene', () {
      final bytes = toGlb(Scene(
        sceneHierarchy: InstanceNode(),
        meshIndex: {},
        gltfMaterials: [],
        glbPrimitives: [],
      ));
      final json = _parseGlb(bytes).json;
      expect((json['meshes'] as List).length, 0);
      expect((json['nodes'] as List).length, 0);
    });

    test('rejects malformed geometry', () {
      var scene = _triangleScene();
      scene.glbPrimitives[0].positions.removeLast();
      expect(() => toGlb(scene), throwsArgumentError);

      scene = _triangleScene();
      scene.glbPrimitives[0].normals.clear();
      expect(() => toGlb(scene), throwsArgumentError);

      scene = _triangleScene();
      scene.glbPrimitives[0].uvs.removeLast();
      expect(() => toGlb(scene), throwsArgumentError);

      scene = _triangleScene();
      scene.glbPrimitives[0].indices.clear();
      expect(() => toGlb(scene), throwsArgumentError);

      scene = _triangleScene();
      scene.glbPrimitives[0].indices[2] = 5;
      expect(() => toGlb(scene), throwsArgumentError);

      scene = _triangleScene();
      scene.glbPrimitives[0] = GlbPrimitive(
        positions: scene.glbPrimitives[0].positions,
        normals: scene.glbPrimitives[0].normals,
        uvs: scene.glbPrimitives[0].uvs,
        indices: scene.glbPrimitives[0].indices,
        materialIndex: 1,
        geomName: scene.glbPrimitives[0].geomName,
      );
      expect(() => toGlb(scene), throwsArgumentError);
    });

    test('rejects non-finite values', () {
      var scene = _triangleScene();
      scene.glbPrimitives[0].positions[0] = double.nan;
      expect(() => toGlb(scene), throwsArgumentError);

      scene = _triangleScene();
      scene.glbPrimitives[0].normals[0] = double.infinity;
      expect(() => toGlb(scene), throwsArgumentError);

      scene = _triangleScene();
      scene.glbPrimitives[0].uvs[0] = double.negativeInfinity;
      expect(() => toGlb(scene), throwsArgumentError);
    });

    test('exports real fixture matching toGlb and buildScene', () {
      final fixturePath = '${Directory.current.path}/test/fixtures/capilla_quiroz_v17.skp';
      final scene = SkpFile.open(fixturePath).buildScene();
      final expected = toGlb(scene);

      final output = '${Directory.systemTemp.path}/openskp-dart-glb-test-${DateTime.now().microsecondsSinceEpoch}.glb';
      exportGlb(scene, output);
      final file = File(output);
      try {
        final actual = file.readAsBytesSync();
        expect(actual, expected);

        final parsed = _parseGlb(Uint8List.fromList(actual));
        final meshes = (parsed.json['meshes'] as List)[0]['primitives'] as List;
        expect(meshes.length, scene.glbPrimitives.length);

        // Every primitive must carry TEXCOORD_0, and the decoded values
        // must exactly match the source GlbPrimitive.uvs that fed the
        // writer - a real round-trip check, not just "some accessor
        // exists."
        final bd = ByteData.sublistView(parsed.binary);
        for (var i = 0; i < scene.glbPrimitives.length; i++) {
          final prim = scene.glbPrimitives[i];
          final attrs = (meshes[i] as Map<String, dynamic>)['attributes'] as Map<String, dynamic>;
          expect(attrs.containsKey('TEXCOORD_0'), true);
          final uvAccessor = (parsed.json['accessors'] as List)[attrs['TEXCOORD_0'] as int] as Map<String, dynamic>;
          final uvBufferView = (parsed.json['bufferViews'] as List)[uvAccessor['bufferView'] as int] as Map<String, dynamic>;
          final uvOffset = uvBufferView['byteOffset'] as int;
          final uvCount = uvAccessor['count'] as int;
          expect(prim.uvs.length, uvCount * 2);
          for (var j = 0; j < prim.uvs.length; j++) {
            final decoded = bd.getFloat32(uvOffset + j * 4, Endian.little);
            // prim.uvs is double (64-bit); the accessor stores float32,
            // so compare against the same round-trip precision.
            final expectedRounded = (ByteData(4)
                  ..setFloat32(0, prim.uvs[j], Endian.little))
                .getFloat32(0, Endian.little);
            expect(decoded, expectedRounded);
          }
        }
      } finally {
        if (file.existsSync()) file.deleteSync();
      }
    });

    test('reports file failures without creating directories', () {
      final output = '${Directory.systemTemp.path}/openskp-missing-parent-${DateTime.now().microsecondsSinceEpoch}/asset.glb';
      expect(() => exportGlb(_triangleScene(), output), throwsA(anything));
      expect(Directory(output).parent.existsSync(), false);
    });
  });
}
