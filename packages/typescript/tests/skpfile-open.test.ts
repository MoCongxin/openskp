import { describe, it, expect } from 'vitest';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { SkpFile } from '../src/index';

/**
 * SkpFile.open() validation - matches the same file-not-found/wrong-
 * extension checks already present in every other port (Python: raises
 * FileNotFoundError/ValueError; Dart: FileSystemException/ArgumentError;
 * .NET: FileNotFoundException/ArgumentException; C++:
 * std::filesystem::filesystem_error/std::invalid_argument). This port
 * previously had neither check at all - a missing file surfaced as
 * Node's own bare ENOENT, and a non-.skp path was accepted and handed
 * straight to the parser.
 */
describe('SkpFile.open validation', () => {
  it('throws for a missing file', () => {
    const missing = path.join(__dirname, 'fixtures', 'does-not-exist.skp');
    expect(() => SkpFile.open(missing)).toThrow(/File not found/);
  });

  it('throws for a file without a .skp extension', () => {
    const tmpPath = path.join(os.tmpdir(), `openskp-test-${Date.now()}.txt`);
    fs.writeFileSync(tmpPath, 'not a skp file');
    try {
      expect(() => SkpFile.open(tmpPath)).toThrow(/Expected a \.skp file/);
    } finally {
      fs.unlinkSync(tmpPath);
    }
  });

  it('extension check is case-insensitive', () => {
    // Copied to a tmpdir (not alongside the real fixture) - on a
    // case-insensitive filesystem (Windows, default macOS),
    // 'Untitled.SKP' and 'Untitled.skp' name the same file, so cleaning
    // up the uppercase copy in-place would delete the real fixture out
    // from under every other test.
    const filePath = path.join(os.tmpdir(), `openskp-test-${Date.now()}.SKP`);
    fs.copyFileSync(path.join(__dirname, 'fixtures', 'Untitled.skp'), filePath);
    try {
      expect(() => SkpFile.open(filePath)).not.toThrow();
    } finally {
      fs.unlinkSync(filePath);
    }
  });
});
