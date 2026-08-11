import { unzipSync, UnzipFileInfo } from 'fflate';

export interface SkpContents {
  version: string;
  modelData: Uint8Array;
  materialFiles: Record<string, Uint8Array>;
}

const VFF_MAGIC = [0xFF, 0xFE, 0xFF, 0x0E];
const ZIP_LOCAL_HEADER = [0x50, 0x4B, 0x03, 0x04]; // PK\x03\x04

function findSequence(data: Uint8Array, sequence: number[], startOffset: number = 0): number {
  const seqLen = sequence.length;
  if (seqLen === 0) return -1;
  const limit = data.length - seqLen;
  for (let i = startOffset; i <= limit; i++) {
    let match = true;
    for (let j = 0; j < seqLen; j++) {
      if (data[i + j] !== sequence[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}

export function validateHeader(data: Uint8Array): boolean {
  if (data.length < 4) return false;
  return (
    data[0] === VFF_MAGIC[0] &&
    data[1] === VFF_MAGIC[1] &&
    data[2] === VFF_MAGIC[2] &&
    data[3] === VFF_MAGIC[3]
  );
}

export function readVersion(data: Uint8Array): string {
  if (data.length < 16) return 'unknown';

  // Find second FF FE FF marker after the initial one at offset 0
  const secondMarker = findSequence(data, [0xFF, 0xFE, 0xFF], 4);
  if (secondMarker > 0) {
    const verStart = secondMarker + 4;
    const verBytes = data.subarray(verStart, Math.min(verStart + 200, data.length));
    try {
      const decoder = new TextDecoder('utf-16le');
      const verText = decoder.decode(verBytes);
      const braceStart = verText.indexOf('{');
      if (braceStart >= 0) {
        const braceEnd = verText.indexOf('}', braceStart);
        if (braceEnd > braceStart) {
          return verText.slice(braceStart, braceEnd + 1);
        }
      }
    } catch (e) {
      // Ignore decoder errors
    }
  }

  return 'unknown';
}

function findZipOffset(data: Uint8Array): number {
  const offset = findSequence(data, ZIP_LOCAL_HEADER);
  if (offset < 0) {
    throw new Error('No embedded ZIP archive found in the file');
  }
  return offset;
}

// A ZIP entry's declared uncompressed size (UnzipFileInfo.originalSize) is
// untrusted central-directory metadata - it can be set independently of
// what the compressed stream actually decompresses to, and even when
// genuine, DEFLATE can expand highly compressible data by three orders of
// magnitude. fflate's unzipSync decompresses (and so allocates) up to that
// declared size with no ceiling of its own. Real production model.dat
// entries are observed at ~10x compression, so both limits below leave
// generous headroom for legitimate files while rejecting the kind of
// declared-size lie or extreme ratio a genuine file would never need.
const MAX_UNCOMPRESSED_ENTRY_BYTES = 16 * 1024 * 1024 * 1024; // 16 GB
const MAX_COMPRESSION_RATIO = 1000;
const RATIO_CHECK_THRESHOLD_BYTES = 1024 * 1024; // 1 MB

/** Reject a ZIP entry whose declared uncompressed size is implausible,
 * before unzipSync decompresses (and so allocates for) it. */
function validateEntrySize(file: UnzipFileInfo): void {
  const declared = file.originalSize;
  if (declared <= 0) return;

  if (declared > MAX_UNCOMPRESSED_ENTRY_BYTES) {
    throw new Error(
      `ZIP entry '${file.name}' declares ${declared} bytes uncompressed, exceeding the ${MAX_UNCOMPRESSED_ENTRY_BYTES}-byte safety ceiling`
    );
  }

  if (declared >= RATIO_CHECK_THRESHOLD_BYTES) {
    const compressed = file.size;
    if (compressed <= 0 || declared / compressed > MAX_COMPRESSION_RATIO) {
      throw new Error(
        `ZIP entry '${file.name}' declares an implausible compression ratio (${declared} bytes from ${compressed} bytes compressed) - likely a decompression bomb`
      );
    }
  }
}

export function extractSkpContents(data: Uint8Array): SkpContents {
  // Allow both VFF-wrapped and bare ZIP (some exporters omit the header)
  if (!validateHeader(data)) {
    const zipInHeader = findSequence(data.subarray(0, Math.min(64, data.length)), ZIP_LOCAL_HEADER) >= 0;
    if (!zipInHeader) {
      throw new Error('Not a valid SketchUp (.skp) file');
    }
  }

  const version = readVersion(data);
  const zipOffset = findZipOffset(data);
  const zipBytes = data.subarray(zipOffset);

  // Only decompress entries we actually consume - a ZIP full of unrelated
  // large assets (the file's own thumbnails, etc.) would otherwise get
  // fully inflated into memory alongside model.dat for nothing.
  const wanted = (file: UnzipFileInfo): boolean => {
    const lower = file.name.toLowerCase();
    const isWanted = (
      lower === 'model.dat' ||
      lower.endsWith('/model.dat') ||
      lower.endsWith('.xml') ||
      lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.includes('material')
    );
    if (isWanted) validateEntrySize(file);
    return isWanted;
  };

  let unzipped: Record<string, Uint8Array>;
  try {
    unzipped = unzipSync(zipBytes, { filter: wanted });
  } catch (e) {
    throw new Error('Failed to decompress ZIP archive: ' + (e as Error).message);
  }

  let modelData: Uint8Array | null = null;
  const materialFiles: Record<string, Uint8Array> = {};

  for (const entry of Object.keys(unzipped)) {
    const lower = entry.toLowerCase();
    if (lower === 'model.dat' || lower.endsWith('/model.dat')) {
      modelData = unzipped[entry];
    } else if (
      lower.endsWith('.xml') ||
      lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.includes('material')
    ) {
      materialFiles[entry] = unzipped[entry];
    }
  }

  if (!modelData) {
    throw new Error('ZIP archive found but does not contain a model.dat entry');
  }

  return {
    version,
    modelData,
    materialFiles,
  };
}
