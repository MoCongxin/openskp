# OpenSKP

**The open-source SketchUp (`.skp`) file parser — TypeScript / JavaScript edition.**

Parse `.skp` files without SketchUp. No SDK. No license. Zero native
dependencies — `fflate` handles ZIP extraction and a ported `earcut`
handles triangulation, so it runs anywhere JavaScript does: Node.js or the
browser.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![npm](https://img.shields.io/npm/v/openskp.svg?logo=npm&logoColor=white)](https://www.npmjs.com/package/openskp)
[![Node](https://img.shields.io/node/v/openskp.svg?logo=node.js&logoColor=white)](https://www.npmjs.com/package/openskp)

🏠 [openskp.com](https://openskp.com) · 🌐 [Try the Live Web Viewer](https://iamahsanmehmood.github.io/openskp/) · 📖 [Docs](https://iamahsanmehmood.github.io/openskp/docs/) · [Changelog](https://github.com/iamahsanmehmood/openskp/blob/main/CHANGELOG.md)

> [!IMPORTANT]
> This project was built by reverse engineering a proprietary binary format. It is not affiliated with or endorsed by Trimble Inc. or SketchUp.

## What is OpenSKP?

OpenSKP is the first and only open-source, cross-platform parser for
SketchUp binary files — reverse-engineered from both the modern **VFF
container** (SketchUp 2021+) and the classic **MFC `CArchive`** container
(SketchUp 2013–2020). It gives you full programmatic access to geometry,
materials, components, layers, and metadata, with no SketchUp installation
and no proprietary SDK required. The same parser and export API also ship
as first-class packages for Python, .NET, Dart, and C++ — see the
[project README](https://github.com/iamahsanmehmood/openskp) for the full
cross-language picture.

## Features

- **Full-fidelity parsing** — vertices, edges, faces, normals, UV
  coordinates, nested component hierarchies, layers/tags, materials,
  textures, styles, and dynamic-component attributes.
- **Both SketchUp file generations** — modern VFF (2021+) and legacy MFC
  (2013–2020) containers, transparently, behind one `parseSkp()`/`.parse()`
  call.
- **Scene baking** — an opt-in `buildScene()` pass resolves the full placed
  scene graph to world-space, triangulated, export-ready geometry.
- **Native multi-format export** — glTF (GLB), Wavefront OBJ/MTL, STL,
  PLY, AutoCAD DXF (3DFACE and Polyface Mesh), IFC4 (BIM/ISO 10303-21 STEP),
  and JSON — all written from scratch, no third-party CAD/BIM SDK involved.
  The DXF writer is verified against real desktop AutoCAD, not just lenient
  DXF readers.
- **Runs anywhere JavaScript does** — zero native dependencies, works in
  Node.js and directly in the browser from a `File`/`Blob`.
- **Structured observability** — opt-in progress reporting and
  structured, location-carrying parse errors.

## Installation

```bash
npm install openskp
```

## Quick Start

```typescript
import { SkpFile } from 'openskp';

// Node.js
const skp = SkpFile.open('model.skp');
const model = skp.parse();

// Browser: parse from a File/Blob's ArrayBuffer
import { parseSkp } from 'openskp';
const buffer = await file.arrayBuffer();
const model2 = parseSkp(buffer);

console.log(model.version, model.layers.length, 'layers');

// Inspect definitions (component geometry) - model.definitions is a Map
for (const [id, defn] of model.definitions) {
  console.log(`${defn.name}: ${defn.faces.length} faces, ${defn.vertices.length} vertices`);
}

// model.root holds whatever is placed directly in the model, not inside
// any component/group
console.log(model.root.instances.length, 'root-level instances');

// Opt-in: full placed scene graph, triangulated, world-space, GLB-ready
const scene = skp.buildScene();
console.log(scene.glbPrimitives.length, 'renderable mesh primitives');
```

## Exporting

```typescript
import { toGLB, toOBJ, toMTL, exportOBJ, toSTLAscii, toSTLBinary, exportSTL, toPLYAscii, toPLYBinary, exportPLY, toDXF, exportDXF, toIFC, exportIFC, toJSON } from 'openskp';

// Serialize a built scene straight to .glb bytes (in-memory, no disk I/O)
const glbBytes = toGLB(scene);

// Export to Wavefront OBJ string, plus a companion .mtl material library
const objText = toOBJ(scene, 'output.mtl');
const mtlText = toMTL(scene);

// Node.js only: writes both output.obj and output.mtl together
exportOBJ(scene, 'output.obj');

// Export to STL ASCII or Binary string/buffer
const stlText = toSTLAscii(scene);
const stlBytes = toSTLBinary(scene);

// Export to PLY ASCII or Binary string/buffer
const plyText = toPLYAscii(scene);
const plyBytes = toPLYBinary(scene);

// Export to AutoCAD 3D DXF text format (R2000 / AC1015 compliant)
const dxfText = toDXF(scene);

// Node.js only: export directly to a .dxf file
exportDXF(scene, 'output.dxf');

// Export to IFC4 / BIM (ISO 10303-21 STEP format string / file)
const ifcText = toIFC(scene);
exportIFC(scene, 'output.ifc');

// Full metadata as a JSON-compatible object
const meta = toJSON(model, scene);
```

## Observability

`parse()`/`buildScene()` accept an optional options object for progress
reporting and structured errors — silent by default:

```typescript
const model = skp.parse({
  onProgress: (info) => console.log(`${info.stage}: ${info.current}/${info.total}`),
  onLog: (level, message) => console.log(`[${level}] ${message}`),
});
```

Parse failures throw `SkpParseError`, carrying `stage`, `recordIndex`,
`totalRecords`, `tag`, and `definitionId` context, with the original
error preserved as `.cause`. See
[docs/OBSERVABILITY.md](../../docs/OBSERVABILITY.md) for the full
cross-language reference.

## Known limitation: large files

Memory use scales worse than the other four ports on very large files —
a 113 MB file needs 8–16 GB of Node heap, and files beyond ~150-200 MB
may not parse in a browser tab at all (a typical tab's heap ceiling is
~4 GB). Root cause: V8's per-object overhead on millions of small
geometry objects. See
[docs/DEVELOPER_GUIDE.md](../../docs/DEVELOPER_GUIDE.md#performance) for
verified numbers before parsing very large files in this package.

## Package Structure

| Module | Purpose |
|---|---|
| `parser.ts` | TLV binary parser for SketchUp's internal format |
| `model.ts` | Interfaces for geometry, layers, materials, scenes |
| `legacy.ts` | Legacy MFC container support (SketchUp 2013–2020) |
| `vff.ts` | VFF/ZIP container handling (`fflate`-based) |
| `triangulator.ts` | Planar polygon triangulation (ported `earcut`) |
| `transforms.ts` | 3D matrix transforms and coordinate conversions |
| `observability.ts` | Progress/log callback types |
| `errors.ts` | `SkpParseError` and structured failure context |
| `index.ts` | Public entry point — `SkpFile`, `parseSkp`, `buildScene`, `toGLB`, `toJSON` |

## Requirements

Node.js ≥ 16, or any modern browser. No native dependencies.

## Used in Production

OpenSKP powers the SketchUp import pipeline for
[FrameSmart](https://frame-smart.com/) (a 3D collaboration platform with
nearly 200 active users) and [IngeTrazo](https://ingetrazo.com/) (a
SketchUp-alternative 3D modeler with a BIM → IFC bridge). Using OpenSKP in
your own project? [Open an issue](https://github.com/iamahsanmehmood/openskp/issues)
or a PR to get added here.

## Contributing

The Python package in `../python/` and this package are both full,
independent implementations at parity — neither is a stub for the other.
See [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines.

## License

MIT — see [LICENSE](../../LICENSE)
