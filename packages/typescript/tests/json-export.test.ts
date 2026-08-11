import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { parseSkp, buildScene, toJSON, SkpModel } from '../src/index';

/**
 * Real-file regression test for toJSON() - openskp's canonical JSON
 * export schema, shared with the Python port's to_dict(). Every
 * assertion here was cross-checked directly against Python's
 * to_dict() on this exact fixture.
 */
describe('toJSON', () => {
  const filePath = path.join(__dirname, 'fixtures', 'capilla_quiroz_v17.skp');
  const buf = fs.readFileSync(filePath);
  const arrayBuffer = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer;

  it('matches Python to_dict() ground truth on a real file', () => {
    const model = parseSkp(arrayBuffer);
    const d = toJSON(model) as any;

    expect(d.format_version).toBe('1.0');
    expect(d.sketchup_version).toBe('{17.0.18899}');
    expect(d.total_definitions).toBe(2);
    expect(d.total_layers).toBe(1);
    expect(d.total_meshes).toBe(0); // no scene passed

    expect(d.root.vertex_count).toBe(251);
    expect(d.root.edge_count).toBe(390);
    expect(d.root.face_count).toBe(146);
    expect(d.root.instances.length).toBe(3);
    // The raw (pre-bake) instance shape is flat, matching TS's own
    // Instance type - no layer/properties/children (see item 17: those
    // are dead fields at parse time in every language except C++, and
    // TS's Instance type doesn't declare them at all).
    expect(Object.keys(d.root.instances[0]).sort()).toEqual(
      ['guid', 'matrix', 'name', 'ref_idx'].sort()
    );

    const puerta = Object.values(d.definitions).find((v: any) => v.name === 'puerta') as any;
    expect(puerta.id).toBe(40);
    expect(puerta.vertex_count).toBe(64);
    expect(puerta.edge_count).toBe(95);
    expect(puerta.face_count).toBe(24);
    expect(puerta.edges.length).toBe(95);
    expect(puerta.faces.length).toBe(24);

    // Layer/material colors are nested {r,g,b[,a]} objects, not a flat
    // color_r/g/b or a positional [r,g,b,a] list.
    expect(d.layers[0].color).toEqual({ r: 255, g: 84, b: 84 });
    expect(typeof d.materials[0].color.r).toBe('number');
    expect(typeof d.materials[0].color.a).toBe('number');

    expect(d.mesh_index).toEqual({});
    expect(d.scene_hierarchy).toBeNull();
  });

  it('includes scene_hierarchy/mesh_index with snake_case keys when a scene is passed', () => {
    const model = parseSkp(arrayBuffer);
    const scene = buildScene(arrayBuffer);
    const d = toJSON(model, scene) as any;

    expect(d.total_meshes).toBe(Object.keys(scene.meshIndex).length);
    expect(d.scene_hierarchy.name).toBe('ROOT');
    // Snake_case, matching the rest of the schema - this function used
    // to emit definitionName/positionMm here instead.
    expect(d.scene_hierarchy).toHaveProperty('definition_name');
    expect(d.scene_hierarchy).toHaveProperty('position_mm');
    expect(d.scene_hierarchy).not.toHaveProperty('definitionName');

    const firstMesh = Object.values(d.mesh_index)[0] as any;
    expect(firstMesh).toHaveProperty('definition_name');
    expect(firstMesh).toHaveProperty('position_mm');
  });

  it('produces JSON-serializable output with no undefined/circular values', () => {
    const model = parseSkp(arrayBuffer);
    const scene = buildScene(arrayBuffer);
    const d = toJSON(model, scene);
    expect(() => JSON.stringify(d)).not.toThrow();
  });
});
