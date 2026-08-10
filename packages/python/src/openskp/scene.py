"""Scene baking: flatten a parsed file's placed instances into a
world-space, triangulated 3D scene ready for rendering or GLB export.

This is deliberately a *separate*, opt-in step from :func:`SkpFile.parse`.
Baking walks the entire placed scene graph - so a file that reuses a
handful of definitions across many thousands of instances can produce far
more data here than the file's raw (un-instanced) geometry. Keeping it
separate means a plain ``SkpFile.open(path).parse()`` never pays for this
heavier computation, matching the same design used by the TypeScript,
C#, and Dart ports (``buildScene()`` / ``BuildScene()`` there).

Ported from the TypeScript reference implementation
(``packages/typescript/src/model.ts``'s ``buildSceneFromParsed``), reusing
this package's own proven ``_core.py`` primitives (``transform_point``,
``multiply_matrices``, ``triangulate_face_3d``) rather than duplicating
them.
"""

from __future__ import annotations

import logging
import time
from array import array
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

from . import _core
from .errors import SkpParseError

logger = logging.getLogger("openskp.scene")

# Mirrors _core._PROGRESS_INTERVAL - counts placed instances (not
# definitions), since a handful of definitions can be instanced thousands
# of times and that's where scene-baking's own cost actually scales.
_PROGRESS_INTERVAL = 500

INCHES_TO_MM = 25.4
INCHES_TO_M = 0.0254


@dataclass
class InstanceNode:
    """One node in the baked, world-space instance tree."""

    name: str = ""
    definition_name: str = ""
    layer: str = ""
    position_mm: Tuple[float, float, float] = (0.0, 0.0, 0.0)
    properties: Dict[str, str] = field(default_factory=dict)
    children: List["InstanceNode"] = field(default_factory=list)


@dataclass
class MeshMetadata:
    """Metadata for one baked mesh, keyed the same as its GlbPrimitive's
    ``geom_name`` in :attr:`Scene.glb_primitives`."""

    name: str = ""
    definition_name: str = ""
    layer: str = ""
    position_mm: Tuple[float, float, float] = (0.0, 0.0, 0.0)
    properties: Dict[str, str] = field(default_factory=dict)
    path: str = ""


@dataclass
class GlbPrimitive:
    """One triangulated, world-space mesh: all faces sharing a single
    resolved color from one flattened scene-graph position. Ready to hand
    straight to a GLB/glTF exporter or any other renderer.

    Attributes:
        positions: Flat [x, y, z, x, y, z, ...] vertex positions, in
            metres, Y-up.
        normals: Flat [x, y, z, ...] vertex normals, matching *positions*
            1:1.
        uvs: Flat [u, v, u, v, ...] texture coordinates, matching
            *positions* 1:1. Computed from each source face's
            ``uv_transform`` (or the default face-plane projection when a
            face has none) - see ``Face.uv_transform`` in model.py for the
            formula. A vertex shared by two faces that disagree on UV is
            split, since indexed glTF meshes need position/normal/uv
            aligned per vertex. Faces with ``uv_projected`` set (terrain
            drape textures) still use the face-plane formula here, since
            the real projection-plane basis isn't captured in the parsed
            data - their UVs will be approximate.
        indices: Triangle vertex indices into *positions*/*normals*/*uvs*
            (3 per triangle).
        material_index: Index into :attr:`Scene.gltf_materials` for this
            primitive's resolved color.
        geom_name: Matches the corresponding key in
            :attr:`Scene.mesh_index`.
    """

    positions: array
    normals: array
    uvs: array
    indices: array
    material_index: int
    geom_name: str


@dataclass
class Scene:
    """The result of baking a parsed file's placed instances into a flat,
    world-space 3D scene."""

    scene_hierarchy: InstanceNode = field(default_factory=InstanceNode)
    mesh_index: Dict[str, MeshMetadata] = field(default_factory=dict)
    glb_primitives: List[GlbPrimitive] = field(default_factory=list)
    gltf_materials: List[Dict[str, Any]] = field(default_factory=list)


def _invert_3x3(m: Tuple[float, ...]) -> Tuple[float, ...]:
    """Inverse of a row-major 3x3 matrix, via the cofactor/adjugate method."""
    a, b, c, d, e, f, g, h, i = m
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    if abs(det) < 1e-12:
        return (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
    inv_det = 1.0 / det
    return (
        (e * i - f * h) * inv_det, (c * h - b * i) * inv_det, (b * f - c * e) * inv_det,
        (f * g - d * i) * inv_det, (a * i - c * g) * inv_det, (c * d - a * f) * inv_det,
        (d * h - e * g) * inv_det, (b * g - a * h) * inv_det, (a * e - b * d) * inv_det,
    )


def _face_uv_basis(n: Tuple[float, float, float]) -> Tuple[Tuple[float, float, float], Tuple[float, float, float]]:
    """Face-plane basis vectors (xr, yr) for UV projection, from a face
    normal. See ``Face.uv_transform`` in model.py for the recipe this
    implements."""
    nx, ny, nz = n
    # xr = normalize(Z x n) = normalize((-ny, nx, 0))
    cx, cy = -ny, nx
    clen = (cx * cx + cy * cy) ** 0.5
    if clen < 1e-9:
        xr = (1.0, 0.0, 0.0)
        yr = (0.0, 1.0 if nz >= 0 else -1.0, 0.0)
    else:
        xr = (cx / clen, cy / clen, 0.0)
        # yr = n x xr
        yr = (
            ny * xr[2] - nz * xr[1],
            nz * xr[0] - nx * xr[2],
            nx * xr[1] - ny * xr[0],
        )
    return xr, yr


def _compute_face_uv(
    p: Tuple[float, float, float],
    xr: Tuple[float, float, float],
    yr: Tuple[float, float, float],
    uv_transform: Optional[Tuple[float, ...]],
    tile_w: float,
    tile_h: float,
) -> Tuple[float, float]:
    """UV of point *p* (inches, local/object space) on a face with the
    given plane basis, per-face ``uv_transform`` (or ``None`` for the
    default projection), and material tile size (inches)."""
    px = p[0] * xr[0] + p[1] * xr[1] + p[2] * xr[2]
    py = p[0] * yr[0] + p[1] * yr[1] + p[2] * yr[2]
    if uv_transform is None:
        return px / tile_w, py / tile_h
    inv = _invert_3x3(uv_transform)
    u = px * inv[0] + py * inv[3] + inv[6]
    v = px * inv[1] + py * inv[4] + inv[7]
    q = px * inv[2] + py * inv[5] + inv[8]
    if abs(q) < 1e-12:
        q = 1.0
    return (u / q) / tile_w, (v / q) / tile_h


def _reconstruct_loop_vertices(loop, edges) -> List[int]:
    loop_verts: List[int] = []
    for edge_id, orient in loop:
        if edge_id in edges:
            v1, v2 = edges[edge_id]
            v_start = v1 if orient == 1 else v2
            if not loop_verts or loop_verts[-1] != v_start:
                loop_verts.append(v_start)
    if len(loop_verts) > 1 and loop_verts[0] == loop_verts[-1]:
        loop_verts = loop_verts[:-1]
    return loop_verts


def build_scene(parsed: Dict[str, Any]) -> Scene:
    """Bake every instance actually placed in ``parsed`` (the output of
    :func:`openskp._core.full_parse` / ``full_parse_legacy``) into
    world-space, triangulated mesh data.

    Args:
        parsed: Output of ``_core.full_parse()``. Callers normally get
            this by calling :meth:`SkpFile.parse` first is *not* required -
            :meth:`SkpFile.build_scene` re-runs the raw parse independently,
            so a plain ``parse()`` call never carries this cost.

    Returns:
        A populated :class:`Scene`.
    """
    t0 = time.monotonic()
    defs_dict = parsed["defs_dict"]
    layer_colors = parsed["layer_colors"]
    layer_id_to_name = parsed["layer_id_to_name"]
    material_id_to_name = parsed.get("material_id_to_name", {})
    materials = parsed["materials"]
    materials_by_folder = parsed.get("materials_by_folder", {})

    logger.info("Building scene: %d definitions available", len(defs_dict))

    instance_counter = [0]
    mesh_counter = [0]
    mesh_index: Dict[str, MeshMetadata] = {}
    glb_primitives: List[GlbPrimitive] = []

    color_to_material_index: Dict[Tuple[int, int, int], int] = {}
    gltf_materials: List[Dict[str, Any]] = []

    # Definitions currently being instantiated on the active recursion
    # path (not "ever visited" - the same definition legitimately reused
    # by sibling instances is fine). Guards against a component that
    # directly or transitively instances itself, which would otherwise
    # recurse until the stack overflows.
    active_definitions: set = set()

    def get_layer_color(name: str) -> Tuple[int, int, int]:
        return layer_colors.get(name, (136, 136, 136))

    def get_material_index(color: Tuple[int, int, int]) -> int:
        if color in color_to_material_index:
            return color_to_material_index[color]
        idx = len(gltf_materials)
        r, g, b = color
        gltf_materials.append(
            {
                "pbrMetallicRoughness": {
                    "baseColorFactor": [r / 255, g / 255, b / 255, 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.8,
                }
            }
        )
        color_to_material_index[color] = idx
        return idx

    def instantiate(
        def_id,
        current_matrix,
        parent_layer: str = "Layer0",
        path_name: str = "ROOT",
        inherited_color: Optional[Tuple[int, int, int]] = None,
    ) -> List[InstanceNode]:
        d = defs_dict.get(def_id)
        if d is None:
            return []
        builder = d["builder"]

        if builder.faces:
            # Group faces sharing a resolved color into one mesh each -
            # same grouping the TS reference uses, to keep primitive count
            # proportional to actual color variety rather than face count.
            face_groups: Dict[Tuple[int, int, int], Dict[str, Any]] = {}

            for f_id, f_data in builder.faces.items():
                face_color = inherited_color
                face_mat_id = f_data.get("material_id")
                mat = None
                if face_mat_id is not None:
                    mat_name = material_id_to_name.get(face_mat_id)
                    mat = materials.get(mat_name) or materials_by_folder.get(mat_name)
                    if mat:
                        c = mat["color"]
                        face_color = (c["r"], c["g"], c["b"])
                if face_color is None:
                    face_color = get_layer_color(parent_layer)

                group = face_groups.get(face_color)
                if group is None:
                    group = {
                        "color": face_color,
                        "local_verts": [],
                        "local_uvs": [],
                        "normals_accum": [],
                        "local_faces": [],
                        "local_v_map": {},
                    }
                    face_groups[face_color] = group

                loops = []
                for loop in f_data["loops"]:
                    loop_verts = _reconstruct_loop_vertices(loop, builder.edges)
                    if loop_verts:
                        loops.append(loop_verts)
                if not loops:
                    continue

                try:
                    triangles = _core.triangulate_face_3d(builder.vertices, loops, f_data["normal"])
                except Exception as e:
                    raise SkpParseError(
                        f"Failed to triangulate face: {e}",
                        stage="build_scene", definition_id=def_id,
                    ) from e

                fn = f_data["normal"]
                tex = mat.get("texture") if mat else None
                tile_w = tex.get("x_scale") if tex else None
                tile_h = tex.get("y_scale") if tex else None
                tile_w = tile_w if tile_w and tile_w > 1e-9 else 1.0
                tile_h = tile_h if tile_h and tile_h > 1e-9 else 1.0
                xr, yr = _face_uv_basis(fn)
                uv_transform = f_data.get("uv_transform")

                # Vertices are deduped per (v_id, uv) rather than just
                # v_id: UVs are inherently per-face, so a vertex position
                # shared by two faces that disagree on texture mapping
                # must become two distinct output vertices (glTF requires
                # position/normal/uv aligned per index).
                face_local_map: Dict[int, int] = {}
                for tri in triangles:
                    face_indices = []
                    for v_id in tri:
                        if v_id not in builder.vertices:
                            continue
                        idx = face_local_map.get(v_id)
                        if idx is None:
                            p = builder.vertices[v_id]
                            u, v = _compute_face_uv(p, xr, yr, uv_transform, tile_w, tile_h)
                            key = (v_id, u, v)
                            idx = group["local_v_map"].get(key)
                            if idx is None:
                                group["local_verts"].append(p)
                                group["local_uvs"].append((u, v))
                                group["normals_accum"].append([fn[0], fn[1], fn[2]])
                                idx = len(group["local_verts"]) - 1
                                group["local_v_map"][key] = idx
                            else:
                                accum = group["normals_accum"][idx]
                                accum[0] += fn[0]
                                accum[1] += fn[1]
                                accum[2] += fn[2]
                            face_local_map[v_id] = idx
                        face_indices.append(idx)
                    if len(face_indices) == 3:
                        group["local_faces"].append(face_indices)

            for face_color, group in face_groups.items():
                local_faces = group["local_faces"]
                if not local_faces:
                    continue

                is_root = path_name == "ROOT"
                tx = 0.0 if is_root else (current_matrix[9] if len(current_matrix) > 9 else 0.0) * INCHES_TO_MM
                ty = 0.0 if is_root else (current_matrix[10] if len(current_matrix) > 10 else 0.0) * INCHES_TO_MM
                tz = 0.0 if is_root else (current_matrix[11] if len(current_matrix) > 11 else 0.0) * INCHES_TO_MM

                safe_path = path_name.replace(" / ", "__").replace(" ", "_")[:80]
                color_suffix = f"_{face_color[0]}_{face_color[1]}_{face_color[2]}" if len(face_groups) > 1 else ""
                geom_name = f"mesh_{mesh_counter[0]}_{safe_path}_{parent_layer}{color_suffix}"
                mesh_counter[0] += 1

                mesh_index[geom_name] = MeshMetadata(
                    name="ROOT" if is_root else (path_name.split(" / ")[-1] or ""),
                    definition_name=d.get("name") or "",
                    layer=parent_layer,
                    position_mm=(round(tx, 2), round(ty, 2), round(tz, 2)),
                    properties={},
                    path=path_name,
                )

                local_verts = group["local_verts"]
                local_uvs = group["local_uvs"]
                positions = array("f", [0.0]) * (len(local_verts) * 3)
                normals = array("f", [0.0]) * (len(local_verts) * 3)
                uvs = array("f", [0.0]) * (len(local_verts) * 2)
                vertex_normals_accum = group["normals_accum"]

                for i, v in enumerate(local_verts):
                    pt = _core.transform_point(v, current_matrix)
                    positions[i * 3] = pt[0] * INCHES_TO_M
                    positions[i * 3 + 1] = pt[2] * INCHES_TO_M
                    positions[i * 3 + 2] = -pt[1] * INCHES_TO_M

                    uvs[i * 2] = local_uvs[i][0]
                    uvs[i * 2 + 1] = local_uvs[i][1]

                    raw_n = vertex_normals_accum[i]
                    norm_len = (raw_n[0] ** 2 + raw_n[1] ** 2 + raw_n[2] ** 2) ** 0.5
                    if norm_len > 1e-6:
                        n = (raw_n[0] / norm_len, raw_n[1] / norm_len, raw_n[2] / norm_len)
                    else:
                        n = (0.0, 0.0, 1.0)

                    nx = current_matrix[0] * n[0] + current_matrix[1] * n[1] + current_matrix[2] * n[2]
                    ny = current_matrix[3] * n[0] + current_matrix[4] * n[1] + current_matrix[5] * n[2]
                    nz = current_matrix[6] * n[0] + current_matrix[7] * n[1] + current_matrix[8] * n[2]
                    length = (nx * nx + ny * ny + nz * nz) ** 0.5
                    if length > 1e-6:
                        normals[i * 3] = nx / length
                        normals[i * 3 + 1] = nz / length
                        normals[i * 3 + 2] = -ny / length
                    else:
                        normals[i * 3] = 0.0
                        normals[i * 3 + 1] = 1.0
                        normals[i * 3 + 2] = 0.0

                indices = array("I", [0]) * (len(local_faces) * 3)
                for i, tri in enumerate(local_faces):
                    indices[i * 3] = tri[0]
                    indices[i * 3 + 1] = tri[1]
                    indices[i * 3 + 2] = tri[2]

                material_index = get_material_index(face_color)
                glb_primitives.append(
                    GlbPrimitive(
                        positions=positions,
                        normals=normals,
                        uvs=uvs,
                        indices=indices,
                        material_index=material_index,
                        geom_name=geom_name,
                    )
                )

        child_instances_info: List[InstanceNode] = []
        for inst in builder.instances:
            ref_idx = inst["ref_idx"]
            inst_matrix = inst["matrix"]
            new_matrix = _core.multiply_matrices(current_matrix, inst_matrix)

            l_name = parent_layer
            inst_color = inherited_color
            properties: Dict[str, str] = {}

            d007 = next((c for c in inst["children"] if c["tag"] == "D007"), None)
            if d007:
                d207 = next((c for c in d007["children"] if c["tag"] == "D207"), None)
                if d207 and d207["payload"]:
                    p = d207["payload"]
                    l_id = p[0] if len(p) == 1 else _core.parse_var_int(p, 0, len(p))
                    l_name = layer_id_to_name.get(l_id, parent_layer)

                d107 = next((c for c in d007["children"] if c["tag"] == "D107"), None)
                if d107:
                    inst_mat_id = _core.parse_var_int(d107["payload"], 0, len(d107["payload"]))
                    mat_name = material_id_to_name.get(inst_mat_id)
                    mat = materials.get(mat_name) or materials_by_folder.get(mat_name)
                    if mat:
                        c = mat["color"]
                        inst_color = (c["r"], c["g"], c["b"])

                try:
                    properties = _core.extract_dynamic_properties(d007)
                except Exception:
                    pass

            inst_name = inst["name"] or f"Component_{ref_idx}"
            full_path_name = f"{path_name} / {inst_name}"
            instance_counter[0] += 1
            if instance_counter[0] % _PROGRESS_INTERVAL == 0:
                logger.debug("Processed %d placed instances", instance_counter[0])

            if ref_idx in active_definitions:
                raise SkpParseError(
                    "Recursive component definition",
                    stage="build_scene", definition_id=ref_idx,
                )
            active_definitions.add(ref_idx)
            child_nodes = instantiate(ref_idx, new_matrix, l_name, full_path_name, inst_color)
            active_definitions.discard(ref_idx)

            tx = new_matrix[9] * INCHES_TO_MM if len(new_matrix) > 9 else 0.0
            ty = new_matrix[10] * INCHES_TO_MM if len(new_matrix) > 10 else 0.0
            tz = new_matrix[11] * INCHES_TO_MM if len(new_matrix) > 11 else 0.0

            inst_info = InstanceNode(
                name=inst["name"] or "",
                definition_name=(defs_dict.get(ref_idx) or {}).get("name") or "",
                layer=l_name,
                position_mm=(round(tx, 2), round(ty, 2), round(tz, 2)),
                properties=properties,
                children=child_nodes,
            )
            child_instances_info.append(inst_info)

            safe_child_path = full_path_name.replace(" / ", "__").replace(" ", "_")[:80]
            for geom_name, existing in mesh_index.items():
                if safe_child_path in geom_name:
                    existing.properties = properties
                    existing.name = inst["name"] or ""

        return child_instances_info

    identity_mat = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1.0]
    root_children = instantiate("ROOT", identity_mat)

    for geom_name, existing in mesh_index.items():
        if existing.path == "ROOT":
            existing.name = "ROOT"
            existing.definition_name = "ROOT_MODEL"
            existing.layer = "Layer0"
            existing.position_mm = (0.0, 0.0, 0.0)
            existing.properties = {}

    scene_hierarchy = InstanceNode(
        name="ROOT",
        definition_name="ROOT_MODEL",
        layer="Layer0",
        position_mm=(0.0, 0.0, 0.0),
        properties={},
        children=root_children,
    )

    logger.info(
        "Scene build complete: %d instances, %d meshes, %d primitives (%.2fs)",
        instance_counter[0], len(mesh_index), len(glb_primitives),
        time.monotonic() - t0,
    )

    return Scene(
        scene_hierarchy=scene_hierarchy,
        mesh_index=mesh_index,
        glb_primitives=glb_primitives,
        gltf_materials=gltf_materials,
    )
