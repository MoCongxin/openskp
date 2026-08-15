import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { parseSkp, buildScene } from '../src/index';
import { isLegacy } from '../src/legacy';

/**
 * Real-file regression test for SketchUp 2020 (v20) classic .skp files.
 *
 * Fixture: fixtures/gondola_v20.skp - a retail gondola display authored in
 * SketchUp 2020 (v20.1.235, ~755 KB), contributed for this fix.
 *
 * Before the v20 layout fixes, this file threw
 * `implausible definition count` from walk(): v20 writes records the v17
 * layout does not have, which left the reader a few bytes short and made it
 * read garbage where a count was expected. The existing v17 fixture
 * (capilla_quiroz_v17.skp) has only one layer and never exercised any of
 * these paths, so the divergence went unnoticed.
 *
 * Every count below was read off this exact file after the fix and
 * sanity-checked for plausibility (bounding box in metres, definitions
 * carrying real geometry, instances actually placed in the scene) - a parse
 * that "succeeds" while silently dropping placements would still be a bug,
 * so the instance counts matter as much as the parse not throwing.
 */
describe('Legacy MFC reader - SketchUp 2020 (v20) layout', () => {
  const filePath = path.join(__dirname, 'fixtures', 'gondola_v20.skp');
  const buf = fs.readFileSync(filePath);
  const data = new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
  const arrayBuffer = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer;

  it('is detected as a legacy container', () => {
    expect(isLegacy(data)).toBe(true);
  });

  it('parses a real v20 file that previously threw', () => {
    const model = parseSkp(arrayBuffer);

    expect(model.version).toBe('{20.1.235}');
    // legacy files carry no meta/meta.dat, same as v17
    expect(model.units).toBeNull();

    expect(model.definitions.size).toBe(20);
    expect(model.materials.length).toBe(24);

    // v20 writes a null object-ref into the layer list, which layerCount
    // includes. It must not reach model.layers as a null entry.
    expect(model.layers.map((l) => l.name)).toEqual(['Layer0']);
    for (const layer of model.layers) {
      expect(layer).not.toBeNull();
      expect(layer.name).toBeTypeOf('string');
    }

    // real geometry, not an empty shell
    let faces = 0;
    let edges = 0;
    let vertices = 0;
    for (const d of model.definitions.values()) {
      faces += d.faces.length;
      edges += d.edges.length;
      vertices += d.vertices.length;
    }
    expect(faces).toBe(1887);
    expect(edges).toBe(9174);
    expect(vertices).toBe(6543);
  });

  it('places every root instance (a parse that drops them is still broken)', () => {
    const model = parseSkp(arrayBuffer);
    // 23 root-level placements: the definitions above are useless if the
    // instances that position them in the model are lost, which is exactly
    // what a subtly misaligned walk produces - a file that parses into an
    // almost-empty scene instead of throwing.
    expect(model.root.instances.length).toBe(23);

    const scene = buildScene(arrayBuffer);
    expect(scene.sceneHierarchy.children.length).toBe(23);
    expect(scene.glbPrimitives.length).toBe(201);
    expect(Object.keys(scene.meshIndex).length).toBe(201);
    expect(scene.gltfMaterials.length).toBe(17);
  });

  it('bakes geometry at a plausible real-world scale', () => {
    const scene = buildScene(arrayBuffer);
    let min = [Infinity, Infinity, Infinity];
    let max = [-Infinity, -Infinity, -Infinity];
    for (const prim of scene.glbPrimitives) {
      for (let i = 0; i < prim.positions.length; i += 3) {
        for (let a = 0; a < 3; a++) {
          const v = prim.positions[i + a];
          if (v < min[a]) min[a] = v;
          if (v > max[a]) max[a] = v;
        }
      }
    }
    // a shop gondola display: metres, not the 1e3-off or degenerate box a
    // misaligned read produces
    expect(max[0] - min[0]).toBeCloseTo(3.82, 1);
    expect(max[1] - min[1]).toBeCloseTo(3.14, 1);
    expect(max[2] - min[2]).toBeCloseTo(4.82, 1);
  });

  it('gives every baked primitive valid uv coordinates', () => {
    const scene = buildScene(arrayBuffer);
    expect(scene.glbPrimitives.length).toBeGreaterThan(0);
    for (const prim of scene.glbPrimitives) {
      const nVerts = prim.positions.length / 3;
      expect(prim.uvs.length).toBe(nVerts * 2);
      for (const uv of prim.uvs) {
        expect(Number.isFinite(uv)).toBe(true);
      }
    }
  });
});
