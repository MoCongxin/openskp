"""Full metadata JSON export.

Serialises a parsed :class:`~openskp.model.SkpModel` - definitions,
layers, materials - into a JSON-compatible dict, and optionally writes it
to disk. Pass the result of :meth:`SkpFile.build_scene` as *scene* to
also include the resolved, world-space scene hierarchy; omit it for a
lighter summary covering just the raw model (``scene_hierarchy`` is then
``None`` rather than a placeholder).
"""

from __future__ import annotations

import json
import pathlib
from typing import Any, Dict, Optional, Union

from ..model import Definition, Instance, SkpModel
from ..scene import InstanceNode, Scene


def _instance_to_dict(inst: Instance) -> Dict[str, Any]:
    """Convert an unresolved (per-definition) :class:`Instance` to a
    JSON-compatible dict.

    Args:
        inst: An :class:`Instance` (may have nested children).

    Returns:
        Dict representation including recursive children.
    """
    return {
        "name": inst.name,
        "ref_idx": inst.ref_idx,
        "guid": inst.guid,
        "matrix": inst.matrix,
        "layer": inst.layer,
        "properties": inst.properties,
        "children": [_instance_to_dict(c) for c in inst.children],
    }


def _instance_node_to_dict(node: InstanceNode) -> Dict[str, Any]:
    """Convert a baked, world-space :class:`~openskp.scene.InstanceNode`
    (from :meth:`SkpFile.build_scene`) to a JSON-compatible dict.

    Args:
        node: An :class:`~openskp.scene.InstanceNode` (may have nested
            children).

    Returns:
        Dict representation including recursive children.
    """
    return {
        "name": node.name,
        "definition_name": node.definition_name,
        "layer": node.layer,
        "position_mm": list(node.position_mm),
        "properties": node.properties,
        "children": [_instance_node_to_dict(c) for c in node.children],
    }


def _definition_to_dict(defn: Definition) -> Dict[str, Any]:
    """Convert a :class:`Definition` to a JSON-compatible dict.

    Geometry data (vertices, edges, faces) is summarised by count to
    keep the JSON output manageable.

    Args:
        defn: A :class:`Definition`.

    Returns:
        Dict representation.
    """
    return {
        "id": defn.id,
        "guid": defn.guid,
        "name": defn.name,
        "vertex_count": len(defn.vertices),
        "edge_count": len(defn.edges),
        "face_count": len(defn.faces),
        "vertices": [
            {"id": v.id, "x": v.x, "y": v.y, "z": v.z}
            for v in defn.vertices.values()
        ],
        "instances": [_instance_to_dict(i) for i in defn.instances],
    }


def to_dict(model: SkpModel, scene: Optional[Scene] = None) -> Dict[str, Any]:
    """Convert a parsed model (and optionally a baked scene) to a
    JSON-serialisable dict.

    Args:
        model: A fully parsed :class:`SkpModel` (the result of
            :meth:`SkpFile.parse`).
        scene: Optional result of :meth:`SkpFile.build_scene`. When given,
            ``scene_hierarchy`` in the output is the real, resolved
            world-space instance tree; when omitted, it's ``None``
            rather than baking a scene implicitly (matching this
            project's parse()/buildScene() split - a plain export never
            pays for the heavier scene bake unless asked).

    Returns:
        A nested dict containing all metadata, including ``root`` (the
        model's implicit top-level definition - non-componentized geometry
        and instances placed directly in the model, matching
        :attr:`SkpModel.root`) alongside ``definitions`` (numeric-ID-keyed
        component/group definitions).
    """
    return {
        "version": model.version,
        "units": model.units,
        "root": _definition_to_dict(model.root),
        "definitions": {
            str(k): _definition_to_dict(v)
            for k, v in model.definitions.items()
        },
        "layers": [
            {
                "name": layer.name,
                "color_r": layer.color_r,
                "color_g": layer.color_g,
                "color_b": layer.color_b,
                "hidden": layer.hidden,
            }
            for layer in model.layers
        ],
        "materials": [
            {
                "name": mat.name,
                "color": list(mat.color),
                "transparency": mat.transparency,
            }
            for mat in model.materials
        ],
        "scene_hierarchy": (
            _instance_node_to_dict(scene.scene_hierarchy) if scene is not None else None
        ),
    }


def export(
    model: SkpModel,
    output_path: Union[str, pathlib.Path],
    *,
    scene: Optional[Scene] = None,
    indent: int = 2,
) -> None:
    """Export model (and optionally scene) metadata to a JSON file.

    Args:
        model: A fully parsed :class:`SkpModel`.
        output_path: Destination file path (should end in ``.json``).
        scene: Optional result of :meth:`SkpFile.build_scene` - see
            :func:`to_dict`.
        indent: JSON indentation level for pretty-printing.
    """
    out = pathlib.Path(output_path)
    out.parent.mkdir(parents=True, exist_ok=True)

    data = to_dict(model, scene)
    with open(out, "w", encoding="utf-8") as fp:
        json.dump(data, fp, indent=indent, ensure_ascii=False)
