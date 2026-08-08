import { describe, it, expect } from 'vitest';
import { isClassRef } from '../src/legacy';

/**
 * Both MFC class-ref encodings the definition-tail scanner must match.
 * Mirrors packages/python/tests/test_parser.py::TestLegacyClassRef
 * (openskp#28 / #39): once a class slot passes 0x7fff the short 16-bit
 * form 0x8000|slot can't fit, so MFC escalates to the big-tag escape
 * (0x7fff followed by a u32 of 0x80000000|slot).
 */
describe('isClassRef', () => {
  it('matches the short form', () => {
    const data = new Uint8Array(2);
    new DataView(data.buffer).setUint16(0, 0x8000 | 278, true);
    expect(isClassRef(data, 0, 278)).toBe(true);
    expect(isClassRef(data, 0, 279)).toBe(false);
  });

  it('matches the big-tag escape', () => {
    // slot 65712 does not fit in 0x8000|slot: MFC writes 0x7fff + u32
    const data = new Uint8Array(6);
    const view = new DataView(data.buffer);
    view.setUint16(0, 0x7fff, true);
    view.setUint32(2, (0x80000000 | 65712) >>> 0, true);
    expect(isClassRef(data, 0, 65712)).toBe(true);
    expect(isClassRef(data, 0, 65713)).toBe(false);
  });

  it('never matches a big slot via the truncated short form', () => {
    // the pre-fix scanner compared a u16 read against 0x8000|65712, which
    // cannot fit in 16 bits - the truncated value must not match
    const data = new Uint8Array(2);
    new DataView(data.buffer).setUint16(0, (0x8000 | 65712) & 0xffff, true);
    expect(isClassRef(data, 0, 65712)).toBe(false);
  });

  it('rejects truncated data', () => {
    const data = new Uint8Array([0xff, 0x7f, 0xb0]);
    expect(isClassRef(data, 0, 65712)).toBe(false);
  });
});
