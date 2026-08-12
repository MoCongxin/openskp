"""DXF (AutoCAD Drawing Exchange Format R2000 / AC1015) 3D export module for OpenSKP.

Exports a baked :class:`~openskp.scene.Scene` to 3D DXF format with Polyface Mesh
or 3DFACE entities grouped by layer using ezdxf for 100% AutoCAD / DWG TrueView compatibility.
Includes layer and entity RGB material base colors (ACI Group 62 and True Color Group 420).
"""

from __future__ import annotations

import pathlib
from typing import TYPE_CHECKING, Literal, Union

import ezdxf

if TYPE_CHECKING:
    from ..scene import Scene

# 1 metre = 39.37007874015748 inches (SketchUp native unit)
METRES_TO_INCHES = 39.37007874015748


def _sanitize_layer_name(name: str) -> str:
    """Sanitize layer name for DXF Group 8 compliance."""
    if not name:
        return "0"
    illegal = '<>/\\"~:;?*=`|'
    clean = "".join(c if c not in illegal else "_" for c in name)
    return clean.strip() or "0"


def _rgb_to_aci(r: int, g: int, b: int) -> int:
    """Map 0-255 RGB color to closest standard AutoCAD Color Index (ACI 1-255)."""
    standard_aci = (
        (255, 0, 0, 1),      # Red
        (255, 255, 0, 2),    # Yellow
        (0, 255, 0, 3),      # Green
        (0, 255, 255, 4),    # Cyan
        (0, 0, 255, 5),      # Blue
        (255, 0, 255, 6),    # Magenta
        (255, 255, 255, 7),  # White
        (128, 128, 128, 8),  # Dark Gray
        (192, 192, 192, 9),  # Light Gray
    )
    best_aci = 7
    min_dist = float("inf")
    for sr, sg, sb, aci in standard_aci:
        dist = (r - sr) ** 2 + (g - sg) ** 2 + (b - sb) ** 2
        if dist < min_dist:
            min_dist = dist
            best_aci = aci
    return best_aci


def _get_prim_rgb(scene: Scene, prim: any) -> tuple[int, int, int]:
    """Extract (R, G, B) integer tuple (0-255) for a primitive's material."""
    r, g, b = 200, 200, 200
    if prim.material_index is not None and scene.gltf_materials and prim.material_index < len(scene.gltf_materials):
        mat = scene.gltf_materials[prim.material_index]
        if isinstance(mat, dict):
            pbr = mat.get("pbrMetallicRoughness", {})
            color_vec = pbr.get("baseColorFactor", [0.8, 0.8, 0.8, 1.0])
            if len(color_vec) >= 3:
                r = int(round(color_vec[0] * 255.0))
                g = int(round(color_vec[1] * 255.0))
                b = int(round(color_vec[2] * 255.0))
    return max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b))


def to_dxf(
    scene: Scene,
    scale: float = METRES_TO_INCHES,
    mode: Literal["3dface", "polyface"] = "3dface",
) -> str:
    """Serialize a baked scene to AutoCAD R2000 (AC1015) 3D ASCII DXF format.

    Args:
        scene: The baked scene returned by :meth:`SkpFile.build_scene`.
        scale: Scale factor for vertex coordinates (default: METRES_TO_INCHES).
        mode: Export entity mode ('polyface' for Polyface Meshes or '3dface' for 3DFACE entities).

    Returns:
        Formatted ASCII DXF text string.
    """
    if scene is None or scene.glb_primitives is None:
        raise ValueError("scene cannot be None")

    doc = ezdxf.new("R2000")
    msp = doc.modelspace()

    for prim in scene.glb_primitives:
        layer_name = _sanitize_layer_name(prim.geom_name or "0")
        v_count = len(prim.positions) // 3
        tri_count = len(prim.indices) // 3
        if v_count == 0 or tri_count == 0:
            continue

        r, g, b = _get_prim_rgb(scene, prim)
        aci_color = _rgb_to_aci(r, g, b)
        true_color = (r << 16) | (g << 8) | b

        if not doc.layers.has_entry(layer_name):
            layer_entry = doc.layers.add(layer_name)
            layer_entry.dxf.color = aci_color
            layer_entry.dxf.true_color = true_color

        if mode == "polyface":
            unique_verts = []
            vert_map = {}
            index_remap = []
            for i in range(v_count):
                pos = (
                    round(prim.positions[i * 3] * scale, 6),
                    round(prim.positions[i * 3 + 1] * scale, 6),
                    round(prim.positions[i * 3 + 2] * scale, 6),
                )
                if pos not in vert_map:
                    vert_map[pos] = len(unique_verts)
                    unique_verts.append(pos)
                index_remap.append(vert_map[pos])

            from ezdxf.render import MeshBuilder
            mesh = MeshBuilder()
            mesh.add_vertices(unique_verts)
            for i in range(tri_count):
                idx0 = index_remap[prim.indices[i * 3]]
                idx1 = index_remap[prim.indices[i * 3 + 1]]
                idx2 = index_remap[prim.indices[i * 3 + 2]]
                mesh.add_face([unique_verts[idx0], unique_verts[idx1], unique_verts[idx2]])

            mesh.render_polyface(
                msp,
                dxfattribs={
                    "layer": layer_name,
                    "color": aci_color,
                    "true_color": true_color,
                },
            )
        else:
            for i in range(tri_count):
                i0 = prim.indices[i * 3]
                i1 = prim.indices[i * 3 + 1]
                i2 = prim.indices[i * 3 + 2]
                p0 = (
                    prim.positions[i0 * 3] * scale,
                    prim.positions[i0 * 3 + 1] * scale,
                    prim.positions[i0 * 3 + 2] * scale,
                )
                p1 = (
                    prim.positions[i1 * 3] * scale,
                    prim.positions[i1 * 3 + 1] * scale,
                    prim.positions[i1 * 3 + 2] * scale,
                )
                p2 = (
                    prim.positions[i2 * 3] * scale,
                    prim.positions[i2 * 3 + 1] * scale,
                    prim.positions[i2 * 3 + 2] * scale,
                )
                msp.add_3dface(
                    [p0, p1, p2, p2],
                    dxfattribs={
                        "layer": layer_name,
                        "color": aci_color,
                        "true_color": true_color,
                    },
                )

    import io
    stream = io.StringIO()
    doc.write(stream)
    return stream.getvalue()


def export(
    scene: Scene,
    output_path: Union[str, pathlib.Path],
    scale: float = METRES_TO_INCHES,
    mode: Literal["3dface", "polyface"] = "3dface",
) -> None:
    """Export a baked scene to an AutoCAD R2000 3D DXF file.

    Args:
        scene: The baked scene returned by :meth:`SkpFile.build_scene`.
        output_path: Destination file path (.dxf).
        scale: Scale factor for vertex coordinates (default: METRES_TO_INCHES).
        mode: Export entity mode ('polyface' or '3dface').
    """
    if scene is None:
        raise ValueError("scene cannot be None")

    out = pathlib.Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)

    text = to_dxf(scene, scale=scale, mode=mode)
    with open(out, "w", encoding="utf-8") as fp:
        fp.write(text)


__all__ = ["to_dxf", "export", "METRES_TO_INCHES"]
