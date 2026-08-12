import 'dart:typed_data';
import 'package:openskp/openskp.dart';
import 'package:test/test.dart';

void main() {
  group('Wavefront OBJ and MTL Exporter', () {
    test('serializes Scene to OBJ and MTL text format', () {
      final scene = Scene(
        sceneHierarchy: InstanceNode(
          name: 'Root',
          definitionName: 'RootDef',
          layer: 'Layer0',
          positionMm: (0.0, 0.0, 0.0),
          properties: {},
          children: [],
        ),
        meshIndex: {},
        glbPrimitives: [
          GlbPrimitive(
            geomName: 'Cube',
            materialIndex: 0,
            positions: Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
            normals: Float32List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1]),
            uvs: Float32List.fromList([0, 0, 1, 0, 0, 1]),
            indices: Uint32List.fromList([0, 1, 2]),
          ),
        ],
        gltfMaterials: [
          {
            'name': 'Green_Material',
            'pbrMetallicRoughness': {
              'baseColorFactor': [0.0, 1.0, 0.0, 1.0]
            }
          }
        ],
      );

      final objText = toObj(scene, mtlFilename: 'scene.mtl');
      expect(objText, contains('# OpenSKP OBJ Export'));
      expect(objText, contains('mtllib scene.mtl'));
      expect(objText, contains('o Cube'));
      expect(objText, contains('v 0.000000 0.000000 0.000000'));
      expect(objText, contains('vt 0.000000 0.000000'));
      expect(objText, contains('vn 0.000000 0.000000 1.000000'));
      expect(objText, contains('usemtl Green_Material'));
      expect(objText, contains('f 1/1/1 2/2/2 3/3/3'));

      final mtlText = toMtl(scene);
      expect(mtlText, contains('# OpenSKP MTL Material Library Export'));
      expect(mtlText, contains('newmtl Green_Material'));
      expect(mtlText, contains('Kd 0.000000 1.000000 0.000000'));
    });
  });
}
