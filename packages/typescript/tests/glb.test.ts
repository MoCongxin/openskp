import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { toGLB, buildScene, SkpScene, GlbPrimitive } from '../src/index';

function triangleScene(): SkpScene {
  return {
    sceneHierarchy: { name: '', definitionName: '', layer: '', positionMm: [0, 0, 0], properties: {}, children: [] },
    meshIndex: {},
    gltfMaterials: [
      {
        pbrMetallicRoughness: {
          baseColorFactor: [0.25, 0.5, 0.75, 1.0],
          metallicFactor: 0.1,
          roughnessFactor: 0.9,
        },
      },
    ],
    glbPrimitives: [
      {
        positions: new Float32Array([1, 2, 3, -4, 5, 0, 2, -1, 7]),
        normals: new Float32Array([0, 0, 1, 0, 0, 1, 0, 0, 1]),
        uvs: new Float32Array([0, 0, 1, 0, 0, 1]),
        indices: new Uint32Array([0, 1, 2]),
        materialIndex: 0,
        geomName: 'triangle',
      } as GlbPrimitive,
    ],
  };
}

function parseGlb(bytes: Uint8Array): { json: any; binary: Uint8Array } {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const jsonChunkLen = view.getUint32(12, true);
  const jsonStr = new TextDecoder().decode(bytes.subarray(20, 20 + jsonChunkLen));
  const json = JSON.parse(jsonStr);

  const binHeaderOffset = 20 + jsonChunkLen;
  let binary = new Uint8Array(0);
  if (binHeaderOffset < bytes.length) {
    const binChunkLen = view.getUint32(binHeaderOffset, true);
    binary = bytes.subarray(binHeaderOffset + 8, binHeaderOffset + 8 + binChunkLen);
  }
  return { json, binary };
}

describe('toGLB', () => {
  it('serializes scene and binary data, including TEXCOORD_0', () => {
    const bytes = toGLB(triangleScene());
    expect(bytes.length).toBeGreaterThanOrEqual(12);
    expect(new TextDecoder().decode(bytes.subarray(0, 4))).toBe('glTF');

    const { json, binary } = parseGlb(bytes);
    expect(json.asset.version).toBe('2.0');

    expect(json.meshes.length).toBe(1);
    const prim = json.meshes[0].primitives[0];
    expect(prim.attributes.POSITION).toBeDefined();
    expect(prim.attributes.NORMAL).toBeDefined();
    expect(prim.attributes.TEXCOORD_0).toBeDefined();
    expect(prim.material).toBe(0);

    const posAccessor = json.accessors[prim.attributes.POSITION];
    expect(posAccessor.componentType).toBe(5126);
    expect(posAccessor.type).toBe('VEC3');
    expect(posAccessor.count).toBe(3);
    expect(posAccessor.min).toEqual([-4, -1, 0]);
    expect(posAccessor.max).toEqual([2, 5, 7]);

    const uvAccessor = json.accessors[prim.attributes.TEXCOORD_0];
    expect(uvAccessor.componentType).toBe(5126);
    expect(uvAccessor.type).toBe('VEC2');
    expect(uvAccessor.count).toBe(3);
    const uvBufferView = json.bufferViews[uvAccessor.bufferView];
    const uvView = new DataView(binary.buffer, binary.byteOffset + uvBufferView.byteOffset);
    expect(uvView.getFloat32(2 * 4, true)).toBe(1);

    const pbr = json.materials[0].pbrMetallicRoughness;
    expect(pbr.baseColorFactor[0]).toBe(0.25);
    expect(pbr.metallicFactor).toBe(0.1);
    expect(pbr.roughnessFactor).toBe(0.9);
  });

  it('serializes an empty scene', () => {
    const scene: SkpScene = {
      sceneHierarchy: { name: '', definitionName: '', layer: '', positionMm: [0, 0, 0], properties: {}, children: [] },
      meshIndex: {},
      gltfMaterials: [],
      glbPrimitives: [],
    };
    const { json } = parseGlb(toGLB(scene));
    expect(json.meshes.length).toBe(0);
    expect(json.nodes.length).toBe(0);
  });

  it('exports the real fixture with real UV data matching the source GlbPrimitive.uvs', () => {
    const filePath = path.join(__dirname, 'fixtures', 'capilla_quiroz_v17.skp');
    const buf = fs.readFileSync(filePath);
    const arrayBuffer = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer;
    const scene = buildScene(arrayBuffer);

    const bytes = toGLB(scene);
    const { json, binary } = parseGlb(bytes);

    const meshPrimitives = json.meshes[0].primitives;
    expect(meshPrimitives.length).toBe(scene.glbPrimitives.length);

    // Every primitive must carry TEXCOORD_0, and the decoded values must
    // exactly match the source GlbPrimitive.uvs that fed the writer - a
    // real round-trip check, not just "some accessor exists."
    for (let i = 0; i < scene.glbPrimitives.length; i++) {
      const prim = scene.glbPrimitives[i];
      const attrs = meshPrimitives[i].attributes;
      expect(attrs.TEXCOORD_0).toBeDefined();
      const uvAccessor = json.accessors[attrs.TEXCOORD_0];
      const uvBufferView = json.bufferViews[uvAccessor.bufferView];
      const uvCount = uvAccessor.count;
      expect(prim.uvs.length).toBe(uvCount * 2);
      const uvView = new DataView(binary.buffer, binary.byteOffset + uvBufferView.byteOffset);
      for (let j = 0; j < prim.uvs.length; j++) {
        expect(uvView.getFloat32(j * 4, true)).toBeCloseTo(prim.uvs[j], 5);
      }
    }
  });
});
