import { describe, it, expect } from 'vitest';
import { buildSceneFromParsed, ParsedRawData } from '../src/index';
import { GeometryBuilder, GeometryBuilderInstance } from '../src/geometry';
import { SkpParseError } from '../src/errors';

/**
 * A component definition that (directly or transitively) instances itself
 * must raise, not recurse until the stack overflows. Real .skp files can't
 * easily be hand-crafted to exercise this, so these tests build a synthetic
 * ParsedRawData directly using the same GeometryBuilder shape geometry.ts
 * produces.
 */

function instance(refIdx: number | string, name = 'child'): GeometryBuilderInstance {
  return {
    offset: 0,
    refGuid: '',
    refIdx: refIdx as number,
    name,
    matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1.0],
    materialId: null,
    children: [],
  };
}

function parsed(defsDict: Map<number | string, any>): ParsedRawData {
  return {
    layerColors: new Map(),
    layerIdToName: new Map(),
    materialIdToName: new Map(),
    materialsMap: new Map(),
    materialsByFolder: new Map(),
    defsDict,
  } as ParsedRawData;
}

describe('buildSceneFromParsed recursion guard', () => {
  it('throws on a self-referencing definition', () => {
    const builder = new GeometryBuilder();
    builder.instances.push(instance(1));
    const rootBuilder = new GeometryBuilder();
    rootBuilder.instances.push(instance(1));

    const defsDict = new Map<number | string, any>([
      [1, { guid: 'g1', name: 'self_ref', isImage: false, alwaysFacesCamera: false, builder }],
      ['ROOT', { guid: 'ROOT', name: 'ROOT_MODEL', isImage: false, alwaysFacesCamera: false, builder: rootBuilder }],
    ]);

    expect(() => buildSceneFromParsed(parsed(defsDict))).toThrow('Recursive component definition');
  });

  it('throws on an indirect cycle', () => {
    const builderA = new GeometryBuilder();
    builderA.instances.push(instance(2));
    const builderB = new GeometryBuilder();
    builderB.instances.push(instance(1));
    const rootBuilder = new GeometryBuilder();
    rootBuilder.instances.push(instance(1));

    const defsDict = new Map<number | string, any>([
      [1, { guid: 'g1', name: 'a', isImage: false, alwaysFacesCamera: false, builder: builderA }],
      [2, { guid: 'g2', name: 'b', isImage: false, alwaysFacesCamera: false, builder: builderB }],
      ['ROOT', { guid: 'ROOT', name: 'ROOT_MODEL', isImage: false, alwaysFacesCamera: false, builder: rootBuilder }],
    ]);

    expect(() => buildSceneFromParsed(parsed(defsDict))).toThrow(SkpParseError);
  });

  it('does not throw on legitimate sibling reuse of the same definition', () => {
    const shared = new GeometryBuilder();
    const rootBuilder = new GeometryBuilder();
    rootBuilder.instances.push(instance(1, 'child_a'));
    rootBuilder.instances.push(instance(1, 'child_b'));

    const defsDict = new Map<number | string, any>([
      [1, { guid: 'g1', name: 'shared', isImage: false, alwaysFacesCamera: false, builder: shared }],
      ['ROOT', { guid: 'ROOT', name: 'ROOT_MODEL', isImage: false, alwaysFacesCamera: false, builder: rootBuilder }],
    ]);

    const scene = buildSceneFromParsed(parsed(defsDict));
    expect(scene.sceneHierarchy.children.length).toBe(2);
  });
});
