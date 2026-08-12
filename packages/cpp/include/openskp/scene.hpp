#pragma once

#include <array>
#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include <openskp/export.hpp>

namespace openskp {

struct InstanceNode {
  std::string name;
  std::string definition_name;
  std::string layer;
  std::array<double, 3> position_mm{};
  std::map<std::string, std::string> properties;
  std::vector<InstanceNode> children;
};

struct MeshMetadata {
  std::string name;
  std::string definition_name;
  std::string layer;
  std::array<double, 3> position_mm{};
  std::map<std::string, std::string> properties;
  std::string path;
};

struct GlbPrimitive {
  std::vector<float> positions;
  std::vector<float> normals;
  // Flat [u, v, u, v, ...] texture coordinates, matching positions 1:1.
  // Computed from the source face's uv_transform (or the default
  // face-plane projection when a face has none): a face-plane basis from
  // the normal, inverting uv_transform when present, divided by the
  // material's texture tile size. A vertex shared by two faces that
  // disagree on UV is split, since indexed glTF meshes need
  // position/normal/uv aligned per vertex. Faces with a PROJECTED texture
  // (terrain-drape, e.g. Add Location) still use the face-plane formula
  // here, since the real projection-plane basis isn't captured in the
  // parsed data - their UVs will be approximate.
  std::vector<float> uvs;
  std::vector<std::uint32_t> indices;
  std::size_t material_index{};
  std::string geom_name;
};

struct PbrMetallicRoughness {
  std::array<double, 4> base_color_factor{1, 1, 1, 1};
  double metallic_factor{};
  double roughness_factor{0.8};
};

struct GltfMaterial {
  std::string name;
  std::string texture_path;
  PbrMetallicRoughness pbr_metallic_roughness;
  bool double_sided{};
};

struct OPENSKP_EXPORT Scene {
  InstanceNode scene_hierarchy;
  std::map<std::string, MeshMetadata> mesh_index;
  std::vector<GlbPrimitive> glb_primitives;
  std::vector<GltfMaterial> gltf_materials;
};
}  // namespace openskp
