#include <gtest/gtest.h>

#include <openskp/openskp.hpp>

#include "internal.hpp"

// Face::hidden / Instance::hidden - the same per-element "Hide" bit edges
// already exposed. Confirmed by directly scanning a real fixture that every
// single face and instance carries a D307 child under its D007 container -
// the exact same display-flags record edges already read (base 0x06,
// +0x01 hidden bit) - just never looked up for these two entity types (see
// the Python port's PR for the scan methodology).
//
// build_model() is called directly with a synthetic RawParsed (hand-crafting
// a real hidden-face/instance file isn't practical), matching the layer
// hidden test's approach.

namespace openskp::test {
namespace {

TEST(FaceInstanceHidden, ReportsHiddenFaceAndInstanceAsHidden) {
  RawParsed parsed;

  RawFace hiddenFace;
  hiddenFace.hidden = true;
  RawFace visibleFace;
  visibleFace.hidden = false;
  parsed.root.builder.faces[1] = hiddenFace;
  parsed.root.builder.faces[2] = visibleFace;

  RawInstance hiddenInst;
  hiddenInst.name = "hidden_one";
  hiddenInst.hidden = true;
  RawInstance visibleInst;
  visibleInst.name = "visible_one";
  visibleInst.hidden = false;
  parsed.root.builder.instances.push_back(hiddenInst);
  parsed.root.builder.instances.push_back(visibleInst);

  auto model = build_model(std::move(parsed));

  ASSERT_TRUE(model.root().faces.count(1));
  ASSERT_TRUE(model.root().faces.count(2));
  EXPECT_TRUE(model.root().faces.at(1).hidden);
  EXPECT_FALSE(model.root().faces.at(2).hidden);

  bool foundHidden = false, foundVisible = false;
  for (const auto& inst : model.root().instances) {
    if (inst.name == "hidden_one") {
      foundHidden = true;
      EXPECT_TRUE(inst.hidden);
    } else if (inst.name == "visible_one") {
      foundVisible = true;
      EXPECT_FALSE(inst.hidden);
    }
  }
  EXPECT_TRUE(foundHidden);
  EXPECT_TRUE(foundVisible);
}

TEST(FaceInstanceHidden, DefaultsToVisible) {
  RawParsed parsed;
  RawFace f;
  parsed.root.builder.faces[1] = f;
  RawInstance i;
  i.name = "n";
  parsed.root.builder.instances.push_back(i);

  auto model = build_model(std::move(parsed));

  ASSERT_TRUE(model.root().faces.count(1));
  EXPECT_FALSE(model.root().faces.at(1).hidden);
  ASSERT_FALSE(model.root().instances.empty());
  EXPECT_FALSE(model.root().instances[0].hidden);
}

}  // namespace
}  // namespace openskp::test
