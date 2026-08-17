#include <gtest/gtest.h>

#include <openskp/openskp.hpp>

#include "test_helpers.hpp"

namespace openskp {
namespace {

// Regression test for legacy (pre-2021 MFC) .skp files with fewer than two
// materials.
//
// The archive's absolute slot numbering is normally bootstrapped by parsing
// two CMaterial records with a throwaway archive and reading the second
// one's own class-ref tag - that trick needs at least 2 materials and
// doesn't work for a file with 0 or 1. Every fixture that predates this
// test (capilla_quiroz_v17.skp, gondola_v20.skp, Untitled.skp) happens to
// have several materials, so this gap went unnoticed - see openskp#158.
//
// Fixtures: blank_v17.skp (0 materials) and single_material_v17.skp (1
// material named "RedMat") - both saved as legacy v17 directly via the
// official SketchUp SDK (SUModelSaveToFileWithVersion), so their content is
// SketchUp's own built-in empty-document boilerplate plus one synthetic
// material, not user/client data.

TEST(LegacySingleMaterial, ParsesAZeroMaterialLegacyFile) {
  // No CMaterial record anywhere in this file - exercises the CLayer-
  // pattern fallback for locating the walk's start position, not just the
  // bootstrap trick itself.
  auto file = SkpFile::open(test::fixture("blank_v17.skp"));
  auto model = file.parse();

  EXPECT_EQ(model.version, "{17.0.1}");
  EXPECT_TRUE(model.materials.empty());
  ASSERT_EQ(model.layers.size(), 1u);
  EXPECT_EQ(model.layers[0].name, "Layer0");
  EXPECT_TRUE(model.definitions.empty());
  EXPECT_TRUE(model.root().instances.empty());
}

TEST(LegacySingleMaterial, ParsesASingleMaterialLegacyFile) {
  auto file = SkpFile::open(test::fixture("single_material_v17.skp"));
  auto model = file.parse();

  EXPECT_EQ(model.version, "{17.0.1}");
  ASSERT_EQ(model.materials.size(), 1u);
  EXPECT_EQ(model.materials[0].name, "RedMat");
  ASSERT_EQ(model.layers.size(), 1u);
  EXPECT_EQ(model.layers[0].name, "Layer0");
}

}  // namespace
}  // namespace openskp
