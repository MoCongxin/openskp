"""Regression test for legacy (pre-2021 MFC) .skp files with fewer than
two materials.

The archive's absolute slot numbering is normally bootstrapped by parsing
two CMaterial records with a throwaway archive and reading the second
one's own class-ref tag - that trick needs at least 2 materials. Files
with 0 or 1 fall back to ``_retry_count_after_v20_filler``'s sibling,
``_probe_layer_anchor_bases`` (legacy.py): walk the material(s) and layer
list with a throwaway relative base, then use the definition-list
anchor - a back-ref to the active layer using the file's REAL absolute
numbering - to recover the true slot base from the layer's known
relative slot.

Python is the only one of the five ports that already had this fallback
before openskp#158/#159 - every other language hard-failed. This test
locks the behavior in here too, for parity with the regression coverage
the other four ports now have.

Fixtures: blank_v17.skp (0 materials) and single_material_v17.skp (1
material named "RedMat") - both saved as legacy v17 directly via the
official SketchUp SDK (SUModelSaveToFileWithVersion), so their content is
SketchUp's own built-in empty-document boilerplate plus one synthetic
material, not user/client data.
"""
from __future__ import annotations

import pathlib

from openskp import SkpFile
from openskp.legacy import is_legacy

BLANK = pathlib.Path(__file__).parent / "fixtures" / "blank_v17.skp"
SINGLE_MATERIAL = pathlib.Path(__file__).parent / "fixtures" / "single_material_v17.skp"


class TestLegacySingleMaterial:
    def test_detects_both_fixtures_as_legacy(self):
        assert is_legacy(BLANK.read_bytes()) is True
        assert is_legacy(SINGLE_MATERIAL.read_bytes()) is True

    def test_parses_a_zero_material_legacy_file(self):
        # No CMaterial record anywhere in this file - exercises the
        # CLayer-pattern fallback for locating the walk's start position,
        # not just the bootstrap trick itself.
        model = SkpFile.open(str(BLANK)).parse()
        assert model.version == "{17.0.1}"
        assert len(model.materials) == 0
        assert [layer.name for layer in model.layers] == ["Layer0"]
        assert len(model.definitions) == 0
        assert len(model.root.instances) == 0

    def test_parses_a_single_material_legacy_file(self):
        model = SkpFile.open(str(SINGLE_MATERIAL)).parse()
        assert model.version == "{17.0.1}"
        assert len(model.materials) == 1
        assert model.materials[0].name == "RedMat"
        assert [layer.name for layer in model.layers] == ["Layer0"]
