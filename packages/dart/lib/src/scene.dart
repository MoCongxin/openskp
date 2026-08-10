import 'dart:math';

import 'core.dart';
import 'errors.dart';
import 'geometry.dart';
import 'observability.dart';
import 'tlv.dart';
import 'transforms.dart';
import 'triangulator.dart';

/// One node in the baked, world-space instance tree.
class InstanceNode {
  String name;
  String definitionName;
  String layer;
  (double, double, double) positionMm;
  Map<String, String> properties;
  List<InstanceNode> children;

  InstanceNode({
    this.name = '',
    this.definitionName = '',
    this.layer = '',
    this.positionMm = (0.0, 0.0, 0.0),
    Map<String, String>? properties,
    List<InstanceNode>? children,
  })  : properties = properties ?? {},
        children = children ?? [];
}

/// Metadata for one baked mesh, keyed the same as its GlbPrimitive's
/// geomName in Scene.meshIndex.
class MeshMetadata {
  String name;
  String definitionName;
  String layer;
  (double, double, double) positionMm;
  Map<String, String> properties;
  String path;

  MeshMetadata({
    this.name = '',
    this.definitionName = '',
    this.layer = '',
    this.positionMm = (0.0, 0.0, 0.0),
    Map<String, String>? properties,
    this.path = '',
  }) : properties = properties ?? {};
}

/// One triangulated, world-space mesh: all faces sharing a single resolved
/// color from one flattened scene-graph position. Ready to hand straight
/// to a GLB/glTF exporter or any other renderer.
class GlbPrimitive {
  /// Flat [x, y, z, x, y, z, ...] vertex positions, in metres, Y-up.
  final List<double> positions;

  /// Flat [x, y, z, ...] vertex normals, matching positions 1:1.
  final List<double> normals;

  /// Flat [u, v, u, v, ...] texture coordinates, matching positions 1:1.
  /// Computed from each source face's uvTransform (or the default
  /// face-plane projection when a face has none) - see
  /// GeometryBuilderFace.uvTransform's usage for the formula. A vertex
  /// shared by two faces that disagree on UV is split, since indexed glTF
  /// meshes need position/normal/uv aligned per vertex. Faces with a
  /// PROJECTED texture (terrain-drape, e.g. Add Location) still use the
  /// face-plane formula here, since the real projection-plane basis isn't
  /// captured in the parsed data - their UVs will be approximate.
  final List<double> uvs;

  /// Triangle vertex indices into positions/normals/uvs (3 per triangle).
  final List<int> indices;

  /// Index into Scene.gltfMaterials for this primitive's resolved color.
  final int materialIndex;

  /// Matches the corresponding key in Scene.meshIndex.
  final String geomName;

  GlbPrimitive({
    required this.positions,
    required this.normals,
    required this.uvs,
    required this.indices,
    required this.materialIndex,
    required this.geomName,
  });
}

/// The result of baking a parsed file's placed instances into a flat,
/// world-space 3D scene.
class Scene {
  InstanceNode sceneHierarchy;
  Map<String, MeshMetadata> meshIndex;
  List<GlbPrimitive> glbPrimitives;
  List<Map<String, dynamic>> gltfMaterials;

  Scene({
    required this.sceneHierarchy,
    required this.meshIndex,
    required this.glbPrimitives,
    required this.gltfMaterials,
  });
}

class _FaceGroup {
  final (int, int, int) color;
  final List<(double, double, double)> localVerts = [];
  final List<(double, double)> localUvs = [];
  final List<List<double>> normalsAccum = [];
  final List<List<int>> localFaces = [];
  final Map<(int, double, double), int> localVMap = {};
  _FaceGroup(this.color);
}

const double _inchesToMm = 25.4;
const double _inchesToM = 0.0254;

/// Inverse of a row-major 3x3 matrix, via the cofactor/adjugate method.
List<double> _invert3x3(List<double> m) {
  final a = m[0], b = m[1], c = m[2];
  final d = m[3], e = m[4], f = m[5];
  final g = m[6], h = m[7], i = m[8];
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  if (det.abs() < 1e-12) {
    return [1, 0, 0, 0, 1, 0, 0, 0, 1];
  }
  final invDet = 1 / det;
  return [
    (e * i - f * h) * invDet, (c * h - b * i) * invDet, (b * f - c * e) * invDet,
    (f * g - d * i) * invDet, (a * i - c * g) * invDet, (c * d - a * f) * invDet,
    (d * h - e * g) * invDet, (b * g - a * h) * invDet, (a * e - b * d) * invDet,
  ];
}

/// Face-plane basis vectors (xr, yr) for UV projection, from a face normal.
((double, double, double), (double, double, double)) _faceUvBasis((double, double, double) n) {
  final (nx, ny, nz) = n;
  final cx = -ny, cy = nx;
  final clen = sqrt(cx * cx + cy * cy);
  if (clen < 1e-9) {
    return ((1.0, 0.0, 0.0), (0.0, nz >= 0 ? 1.0 : -1.0, 0.0));
  }
  final xr = (cx / clen, cy / clen, 0.0);
  final yr = (ny * xr.$3 - nz * xr.$2, nz * xr.$1 - nx * xr.$3, nx * xr.$2 - ny * xr.$1);
  return (xr, yr);
}

/// UV of point p (inches, local/object space) on a face with the given
/// plane basis, per-face uvTransform (or null for the default projection),
/// and material tile size (inches).
(double, double) _computeFaceUv(
  (double, double, double) p,
  (double, double, double) xr,
  (double, double, double) yr,
  List<double>? uvTransform,
  double tileW,
  double tileH,
) {
  final px = p.$1 * xr.$1 + p.$2 * xr.$2 + p.$3 * xr.$3;
  final py = p.$1 * yr.$1 + p.$2 * yr.$2 + p.$3 * yr.$3;
  if (uvTransform == null) {
    return (px / tileW, py / tileH);
  }
  final inv = _invert3x3(uvTransform);
  final u = px * inv[0] + py * inv[3] + inv[6];
  final v = px * inv[1] + py * inv[4] + inv[7];
  var q = px * inv[2] + py * inv[5] + inv[8];
  if (q.abs() < 1e-12) q = 1.0;
  return (u / q / tileW, v / q / tileH);
}

/// Bakes every instance actually placed in a parsed model into world-space,
/// triangulated mesh data - SketchUp's own component/group nesting fully
/// resolved and flattened. See SkpFile.buildScene() for why this is a
/// separate, opt-in step from parse().
///
/// Ported from the TypeScript reference implementation
/// (model.ts's buildSceneFromParsed).
class SceneBuilder {
  static Scene build(RawParsed parsed, [ParseOptions? options]) {
    final sw = Stopwatch()..start();
    final defsDict = parsed.defsDict;
    final layerColors = parsed.layerColors;
    final layerIdToName = parsed.layerIdToName;
    final materialIdToName = parsed.materialIdToName;
    final materials = parsed.materials;
    final materialsByFolder = parsed.materialsByFolder;

    emitLog(options, SkpLogLevel.info, 'Building scene: ${defsDict.length} definitions available');
    var instanceCounter = 0;

    int meshCounter = 0;
    final meshIndex = <String, MeshMetadata>{};
    final glbPrimitives = <GlbPrimitive>[];

    final colorToMaterialIndex = <(int, int, int), int>{};
    final gltfMaterials = <Map<String, dynamic>>[];

    (int, int, int) getLayerColor(String name) => layerColors[name] ?? (136, 136, 136);

    int getMaterialIndex((int, int, int) color) {
      final existing = colorToMaterialIndex[color];
      if (existing != null) return existing;
      final idx = gltfMaterials.length;
      final (r, g, b) = color;
      gltfMaterials.add({
        'pbrMetallicRoughness': {
          'baseColorFactor': [r / 255, g / 255, b / 255, 1.0],
          'metallicFactor': 0.0,
          'roughnessFactor': 0.8,
        },
      });
      colorToMaterialIndex[color] = idx;
      return idx;
    }

    List<int> reconstructLoopVertices(List<(int, int)> loop, Map<int, (int?, int?)> edges) {
      final loopVerts = <int>[];
      for (final (edgeId, orient) in loop) {
        final ends = edges[edgeId];
        if (ends != null) {
          final vStart = orient == 1 ? ends.$1 : ends.$2;
          if (vStart != null && (loopVerts.isEmpty || loopVerts.last != vStart)) {
            loopVerts.add(vStart);
          }
        }
      }
      if (loopVerts.length > 1 && loopVerts.first == loopVerts.last) {
        loopVerts.removeLast();
      }
      return loopVerts;
    }

    List<InstanceNode> instantiateBuilder(
      GeometryBuilder builder,
      String defName,
      int? defId,
      List<double> currentMatrix,
      String parentLayer,
      String pathName,
      (int, int, int)? inheritedColor,
    ) {
      if (builder.faces.isNotEmpty) {
        final faceGroups = <(int, int, int), _FaceGroup>{};

        for (final faceEntry in builder.faces.entries) {
          final fData = faceEntry.value;
          (int, int, int)? faceColor = inheritedColor;
          final faceMatId = fData.materialId;
          RawMaterial? mat;
          if (faceMatId != null) {
            final matName = materialIdToName[faceMatId];
            if (matName != null) {
              mat = materials[matName] ?? materialsByFolder[matName];
              if (mat != null) faceColor = (mat.r, mat.g, mat.b);
            }
          }
          final resolvedColor = faceColor ?? getLayerColor(parentLayer);

          final group = faceGroups.putIfAbsent(resolvedColor, () => _FaceGroup(resolvedColor));

          final loops = <List<int>>[];
          for (final loop in fData.loops) {
            final loopVerts = reconstructLoopVertices(loop, builder.edges);
            if (loopVerts.isNotEmpty) loops.add(loopVerts);
          }
          if (loops.isEmpty) continue;

          List<List<int>> triangles;
          try {
            triangles = Triangulator.triangulateFace3D(builder.vertices, loops, fData.normal);
          } catch (e) {
            throw SkpParseException(
              'Failed to triangulate face: $e',
              stage: 'build_scene', definitionId: defId, cause: e,
            );
          }

          final fn = fData.normal;
          final tex = mat?.texture;
          final tileW = (tex != null && tex.xScale > 1e-9) ? tex.xScale : 1.0;
          final tileH = (tex != null && tex.yScale > 1e-9) ? tex.yScale : 1.0;
          final (xr, yr) = _faceUvBasis(fn);
          final uvTransform = fData.uvTransform;

          // Vertices are deduped per (vId, uv) rather than just vId: UVs
          // are inherently per-face, so a vertex position shared by two
          // faces that disagree on texture mapping must become two
          // distinct output vertices (glTF requires position/normal/uv
          // aligned per index).
          final faceLocalMap = <int, int>{};
          for (final tri in triangles) {
            final faceIndices = <int>[];
            for (final vId in tri) {
              if (!builder.vertices.containsKey(vId)) continue;
              var idx = faceLocalMap[vId];
              if (idx == null) {
                final p = builder.vertices[vId]!;
                final (u, v) = _computeFaceUv(p, xr, yr, uvTransform, tileW, tileH);
                final key = (vId, u, v);
                idx = group.localVMap[key];
                if (idx == null) {
                  group.localVerts.add(p);
                  group.localUvs.add((u, v));
                  group.normalsAccum.add([fn.$1, fn.$2, fn.$3]);
                  idx = group.localVerts.length - 1;
                  group.localVMap[key] = idx;
                } else {
                  final accum = group.normalsAccum[idx];
                  accum[0] += fn.$1;
                  accum[1] += fn.$2;
                  accum[2] += fn.$3;
                }
                faceLocalMap[vId] = idx;
              }
              faceIndices.add(idx);
            }
            if (faceIndices.length == 3) {
              group.localFaces.add(faceIndices);
            }
          }
        }

        final isRootPath = pathName == 'ROOT';
        final multiGroup = faceGroups.length > 1;

        for (final groupEntry in faceGroups.entries) {
          final color = groupEntry.key;
          final group = groupEntry.value;
          if (group.localFaces.isEmpty) continue;

          final tx = isRootPath ? 0.0 : (currentMatrix.length > 9 ? currentMatrix[9] : 0.0) * _inchesToMm;
          final ty = isRootPath ? 0.0 : (currentMatrix.length > 10 ? currentMatrix[10] : 0.0) * _inchesToMm;
          final tz = isRootPath ? 0.0 : (currentMatrix.length > 11 ? currentMatrix[11] : 0.0) * _inchesToMm;

          var safePath = pathName.replaceAll(' / ', '__').replaceAll(' ', '_');
          if (safePath.length > 80) safePath = safePath.substring(0, 80);
          final colorSuffix = multiGroup ? '_${color.$1}_${color.$2}_${color.$3}' : '';
          final geomName = 'mesh_${meshCounter}_${safePath}_$parentLayer$colorSuffix';
          meshCounter++;

          meshIndex[geomName] = MeshMetadata(
            name: isRootPath ? 'ROOT' : (pathName.split(' / ').lastOrNull ?? ''),
            definitionName: defName,
            layer: parentLayer,
            positionMm: (_round2(tx), _round2(ty), _round2(tz)),
            path: pathName,
          );

          final vertCount = group.localVerts.length;
          final positions = List<double>.filled(vertCount * 3, 0.0);
          final normals = List<double>.filled(vertCount * 3, 0.0);
          final uvs = List<double>.filled(vertCount * 2, 0.0);
          final vertexNormalsAccum = group.normalsAccum;

          for (int i = 0; i < vertCount; i++) {
            final v = group.localVerts[i];
            final pt = Transforms.transformPoint(currentMatrix, v);
            positions[i * 3] = pt.$1 * _inchesToM;
            positions[i * 3 + 1] = pt.$3 * _inchesToM;
            positions[i * 3 + 2] = -pt.$2 * _inchesToM;

            uvs[i * 2] = group.localUvs[i].$1;
            uvs[i * 2 + 1] = group.localUvs[i].$2;

            final raw = vertexNormalsAccum[i];
            final normLen = _len3(raw[0], raw[1], raw[2]);
            double nx0, ny0, nz0;
            if (normLen > 1e-6) {
              nx0 = raw[0] / normLen;
              ny0 = raw[1] / normLen;
              nz0 = raw[2] / normLen;
            } else {
              nx0 = 0;
              ny0 = 0;
              nz0 = 1;
            }

            final m0 = currentMatrix.length > 0 ? currentMatrix[0] : 1.0;
            final m1 = currentMatrix.length > 1 ? currentMatrix[1] : 0.0;
            final m2 = currentMatrix.length > 2 ? currentMatrix[2] : 0.0;
            final m3 = currentMatrix.length > 3 ? currentMatrix[3] : 0.0;
            final m4 = currentMatrix.length > 4 ? currentMatrix[4] : 1.0;
            final m5 = currentMatrix.length > 5 ? currentMatrix[5] : 0.0;
            final m6 = currentMatrix.length > 6 ? currentMatrix[6] : 0.0;
            final m7 = currentMatrix.length > 7 ? currentMatrix[7] : 0.0;
            final m8 = currentMatrix.length > 8 ? currentMatrix[8] : 1.0;

            final nx = m0 * nx0 + m1 * ny0 + m2 * nz0;
            final ny = m3 * nx0 + m4 * ny0 + m5 * nz0;
            final nz = m6 * nx0 + m7 * ny0 + m8 * nz0;
            final length = _len3(nx, ny, nz);
            if (length > 1e-6) {
              normals[i * 3] = nx / length;
              normals[i * 3 + 1] = nz / length;
              normals[i * 3 + 2] = -ny / length;
            } else {
              normals[i * 3] = 0;
              normals[i * 3 + 1] = 1;
              normals[i * 3 + 2] = 0;
            }
          }

          final indices = <int>[];
          for (final tri in group.localFaces) {
            indices.add(tri[0]);
            indices.add(tri[1]);
            indices.add(tri[2]);
          }

          final materialIndex = getMaterialIndex(color);
          glbPrimitives.add(GlbPrimitive(
            positions: positions,
            normals: normals,
            uvs: uvs,
            indices: indices,
            materialIndex: materialIndex,
            geomName: geomName,
          ));
        }
      }

      final childInstancesInfo = <InstanceNode>[];
      for (final inst in builder.instances) {
        final refIdx = inst.refIdx;
        final newMatrix = Transforms.multiplyMatrices(currentMatrix, inst.matrix);

        var lName = parentLayer;
        (int, int, int)? instColor = inheritedColor;
        final properties = <String, String>{};

        final d007 = inst.children.where((c) => c.tag == 'D007').firstOrNull;
        if (d007 != null) {
          final d207 = d007.children.where((c) => c.tag == 'D207').firstOrNull;
          if (d207 != null && d207.payload.isNotEmpty) {
            final p = d207.payload;
            final lId = p.length == 1 ? p[0] : Tlv.parseVarInt(p, 0, p.length);
            lName = layerIdToName[lId] ?? parentLayer;
          }
          final d107 = d007.children.where((c) => c.tag == 'D107').firstOrNull;
          if (d107 != null) {
            final instMatId = Tlv.parseVarInt(d107.payload, 0, d107.payload.length);
            final matName = materialIdToName[instMatId];
            if (matName != null) {
              final mat = materials[matName] ?? materialsByFolder[matName];
              if (mat != null) instColor = (mat.r, mat.g, mat.b);
            }
          }
          // Dynamic properties (attribute dictionaries under D007) are not
          // yet ported for Dart; left empty.
        }

        final instName = (inst.name != null && inst.name!.isNotEmpty) ? inst.name! : 'Component_$refIdx';
        final fullPathName = '$pathName / $instName';
        instanceCounter++;
        if (instanceCounter % progressInterval == 0) {
          emitProgress(options, 'build_scene', instanceCounter, instanceCounter);
          emitLog(options, SkpLogLevel.debug, 'Processed $instanceCounter placed instances');
        }
        final childDef = refIdx != null ? defsDict[refIdx] : null;
        final childNodes = (refIdx != null && childDef != null)
            ? instantiateBuilder(childDef.builder, childDef.name ?? '', refIdx, newMatrix, lName, fullPathName, instColor)
            : <InstanceNode>[];

        final itx = newMatrix.length > 9 ? newMatrix[9] * _inchesToMm : 0.0;
        final ity = newMatrix.length > 10 ? newMatrix[10] * _inchesToMm : 0.0;
        final itz = newMatrix.length > 11 ? newMatrix[11] * _inchesToMm : 0.0;

        final instInfo = InstanceNode(
          name: inst.name ?? '',
          definitionName: childDef?.name ?? '',
          layer: lName,
          positionMm: (_round2(itx), _round2(ity), _round2(itz)),
          properties: properties,
          children: childNodes,
        );
        childInstancesInfo.add(instInfo);

        var safeChildPath = fullPathName.replaceAll(' / ', '__').replaceAll(' ', '_');
        if (safeChildPath.length > 80) safeChildPath = safeChildPath.substring(0, 80);
        for (final entry in meshIndex.entries) {
          if (entry.key.contains(safeChildPath)) {
            entry.value.properties = properties;
            entry.value.name = inst.name ?? '';
          }
        }
      }

      return childInstancesInfo;
    }

    final identityMat = <double>[1.0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1.0];
    final rootChildren = instantiateBuilder(parsed.root.builder, 'ROOT_MODEL', null, identityMat, 'Layer0', 'ROOT', null);

    for (final entry in meshIndex.entries) {
      final existing = entry.value;
      if (existing.path == 'ROOT') {
        existing.name = 'ROOT';
        existing.definitionName = 'ROOT_MODEL';
        existing.layer = 'Layer0';
        existing.positionMm = (0.0, 0.0, 0.0);
        existing.properties = {};
      }
    }

    final sceneHierarchy = InstanceNode(
      name: 'ROOT',
      definitionName: 'ROOT_MODEL',
      layer: 'Layer0',
      positionMm: (0.0, 0.0, 0.0),
      children: rootChildren,
    );

    emitLog(
      options, SkpLogLevel.info,
      'Scene build complete: $instanceCounter instances, ${meshIndex.length} meshes, '
      '${glbPrimitives.length} primitives (${(sw.elapsedMilliseconds / 1000).toStringAsFixed(2)}s)',
    );

    return Scene(
      sceneHierarchy: sceneHierarchy,
      meshIndex: meshIndex,
      glbPrimitives: glbPrimitives,
      gltfMaterials: gltfMaterials,
    );
  }

  static double _round2(double v) => (v * 100).round() / 100;
  static double _len3(double x, double y, double z) => sqrt(x * x + y * y + z * z);
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

extension _LastOrNullExt<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
