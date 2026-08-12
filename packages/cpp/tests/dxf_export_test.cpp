#include "openskp/dxf_export.hpp"

#include <gtest/gtest.h>

namespace openskp {
namespace {

TEST(DxfExport, SerializesSceneTo3DxfText) {
  Scene scene;
  GlbPrimitive prim;
  prim.geom_name = "Walls";
  prim.material_index = 0;
  prim.positions = {0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0};
  prim.normals = {0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0};
  prim.uvs = {0.0, 0.0, 1.0, 0.0, 0.0, 1.0};
  prim.indices = {0, 1, 2};
  scene.glb_primitives.push_back(prim);

  std::string dxf_text = to_dxf(scene, METRES_TO_INCHES, "polyface");
  EXPECT_NE(dxf_text.find("$ACADVER"), std::string::npos);
  EXPECT_NE(dxf_text.find("AC1015"), std::string::npos);
  EXPECT_NE(dxf_text.find("POLYLINE"), std::string::npos);
  EXPECT_NE(dxf_text.find("AcDbPolyFaceMesh"), std::string::npos);
  EXPECT_NE(dxf_text.find("Walls"), std::string::npos);
  EXPECT_NE(dxf_text.find("EOF"), std::string::npos);
}

}  // namespace
}  // namespace openskp
