import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';
import { parseSkp } from '../src/index';
import { isLegacy } from '../src/legacy';

/**
 * Regression test for legacy (pre-2021 MFC) .skp files with fewer than two
 * materials.
 *
 * The archive's absolute slot numbering is normally bootstrapped by parsing
 * two CMaterial records with a throwaway archive and reading the second
 * one's own class-ref tag - that trick needs at least 2 materials and
 * doesn't work for a file with 0 or 1. Every fixture that predates this
 * test (capilla_quiroz_v17.skp, gondola_v20.skp, Untitled.skp) happens to
 * have several materials, so this gap went unnoticed - see openskp#158.
 *
 * Fixtures: blank_v17.skp (SketchUp 2025, 0 materials) and
 * single_material_v17.skp (SketchUp 2025, 1 material named "RedMat") -
 * both saved as legacy v17 directly via the official SketchUp SDK
 * (SUModelSaveToFileWithVersion), so their content is SketchUp's own
 * built-in empty-document boilerplate plus one synthetic material, not
 * user/client data.
 */
describe('Legacy MFC reader - fewer than 2 materials', () => {
  const blankPath = path.join(__dirname, 'fixtures', 'blank_v17.skp');
  const singleMatPath = path.join(__dirname, 'fixtures', 'single_material_v17.skp');

  function load(filePath: string) {
    const buf = fs.readFileSync(filePath);
    const data = new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
    const arrayBuffer = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) as ArrayBuffer;
    return { data, arrayBuffer };
  }

  it('detects both fixtures as legacy containers', () => {
    expect(isLegacy(load(blankPath).data)).toBe(true);
    expect(isLegacy(load(singleMatPath).data)).toBe(true);
  });

  it('parses a zero-material legacy file (no CMaterial record in the file at all)', () => {
    const model = parseSkp(load(blankPath).arrayBuffer);
    expect(model.version).toBe('{17.0.1}');
    expect(model.materials.length).toBe(0);
    expect(model.layers.map((l) => l.name)).toEqual(['Layer0']);
    expect(model.definitions.size).toBe(0);
    expect(model.root.instances.length).toBe(0);
  });

  it('parses a single-material legacy file', () => {
    const model = parseSkp(load(singleMatPath).arrayBuffer);
    expect(model.version).toBe('{17.0.1}');
    expect(model.materials.length).toBe(1);
    expect(model.materials[0].name).toBe('RedMat');
    expect(model.layers.map((l) => l.name)).toEqual(['Layer0']);
  });
});
