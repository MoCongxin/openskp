import { describe, it, expect } from 'vitest';
import { zipSync } from 'fflate';
import { randomBytes } from 'node:crypto';
import { extractSkpContents } from '../src/vff';

/**
 * A ZIP entry's declared uncompressed size is untrusted central-directory
 * metadata - it can be set independently of what the compressed stream
 * actually decompresses to, and even when genuine, DEFLATE can expand
 * highly compressible data by three orders of magnitude. fflate's
 * unzipSync decompresses (and so allocates) up to that declared size with
 * no ceiling of its own, so vff.ts's `wanted` filter validates every
 * entry's size before letting unzipSync touch it.
 */

function buildSkpBytes(zipBytes: Uint8Array): Uint8Array {
  const header = new Uint8Array(16); // VFF magic + padding
  header.set([0xff, 0xfe, 0xff, 0x0e], 0);
  const combined = new Uint8Array(header.length + zipBytes.length);
  combined.set(header, 0);
  combined.set(zipBytes, header.length);
  return combined;
}

describe('extractSkpContents ZIP entry size cap', () => {
  it('rejects an implausible compression ratio in model.dat', () => {
    // 8 MB of zeros deflates to a few hundred bytes - a ratio well past
    // what real (binary geometry) model.dat entries show (~10x), the
    // shape of a declared-size decompression bomb: tiny real payload,
    // huge claimed size.
    const zeros = new Uint8Array(8 * 1024 * 1024);
    const zipBytes = zipSync({ 'model.dat': zeros }, { level: 9 });
    const skpBytes = buildSkpBytes(zipBytes);

    expect(() => extractSkpContents(skpBytes)).toThrow(/compression ratio/);
  });

  it('allows a realistic compression ratio', () => {
    // Random content compresses poorly (ratio close to 1x), comfortably
    // under the safety threshold.
    const random = new Uint8Array(randomBytes(64 * 1024));
    const zipBytes = zipSync({ 'model.dat': random }, { level: 9 });
    const skpBytes = buildSkpBytes(zipBytes);

    const contents = extractSkpContents(skpBytes);
    expect(contents.modelData.length).toBe(random.length);
  });

  it('allows a tiny entry regardless of ratio', () => {
    // Below the 1 MB ratio-check threshold, even a high ratio is allowed
    // through - the absolute cost is bounded regardless.
    const zeros = new Uint8Array(1024);
    const zipBytes = zipSync({ 'model.dat': zeros }, { level: 9 });
    const skpBytes = buildSkpBytes(zipBytes);

    const contents = extractSkpContents(skpBytes);
    expect(contents.modelData.length).toBe(zeros.length);
  });
});
