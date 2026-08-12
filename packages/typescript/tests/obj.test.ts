import { describe, it, expect } from 'vitest';
import { toOBJ, toMTL } from '../src/obj';
import { SkpScene } from '../src/model';

describe('Wavefront OBJ and MTL Exporter', () => {
  it('serializes a SkpScene to OBJ and MTL text format', () => {
    const scene: SkpScene = {
      sceneHierarchy: {
        name: 'Root',
        definitionName: 'RootDef',
        layer: 'Layer0',
        positionMm: [0, 0, 0],
        properties: {},
        children: [],
      },
      meshIndex: {},
      glbPrimitives: [
        {
          geomName: 'Cube',
          materialIndex: 0,
          positions: new Float32Array([0, 0, 0, 1, 0, 0, 0, 1, 0]),
          normals: new Float32Array([0, 0, 1, 0, 0, 1, 0, 0, 1]),
          uvs: new Float32Array([0, 0, 1, 0, 0, 1]),
          indices: new Uint32Array([0, 1, 2]),
        },
      ],
      gltfMaterials: [
        {
          name: 'Blue_Material',
          pbrMetallicRoughness: { baseColorFactor: [0.0, 0.0, 1.0, 1.0] },
        } as any,
      ],
    };

    const objText = toOBJ(scene, 'scene.mtl');
    expect(objText).toContain('# OpenSKP OBJ Export');
    expect(objText).toContain('mtllib scene.mtl');
    expect(objText).toContain('o Cube');
    expect(objText).toContain('v 0.000000 0.000000 0.000000');
    expect(objText).toContain('vt 0.000000 0.000000');
    expect(objText).toContain('vn 0.000000 0.000000 1.000000');
    expect(objText).toContain('usemtl Blue_Material');
    expect(objText).toContain('f 1/1/1 2/2/2 3/3/3');

    const mtlText = toMTL(scene);
    expect(mtlText).toContain('# OpenSKP MTL Material Library Export');
    expect(mtlText).toContain('newmtl Blue_Material');
    expect(mtlText).toContain('Kd 0.000000 0.000000 1.000000');
  });
});
