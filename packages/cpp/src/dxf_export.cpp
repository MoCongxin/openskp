#include "openskp/dxf_export.hpp"

#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <tuple>
#include <vector>

namespace openskp {

static std::string sanitize_layer_name(const std::string& name) {
  if (name.empty()) return "0";
  std::string clean = name;
  const std::string illegal = "<>/\\\"~:;?*=`|";
  for (char& c : clean) {
    if (illegal.find(c) != std::string::npos) {
      c = '_';
    }
  }
  // Trim whitespace
  size_t first = clean.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) return "0";
  size_t last = clean.find_last_not_of(" \t\r\n");
  return clean.substr(first, last - first + 1);
}

static int rgb_to_aci(int r, int g, int b) {
  static const std::vector<std::tuple<int, int, int, int>> standard_aci = {
      {255, 0, 0, 1},   {255, 255, 0, 2},   {0, 255, 0, 3},     {0, 255, 255, 4},  {0, 0, 255, 5},
      {255, 0, 255, 6}, {255, 255, 255, 7}, {128, 128, 128, 8}, {192, 192, 192, 9}};
  int best_aci = 7;
  double min_dist = 1e18;
  for (const auto& [sr, sg, sb, aci] : standard_aci) {
    double d = (r - sr) * (r - sr) + (g - sg) * (g - sg) + (b - sb) * (b - sb);
    if (d < min_dist) {
      min_dist = d;
      best_aci = aci;
    }
  }
  return best_aci;
}

static std::tuple<int, int, int> get_prim_rgb(const Scene& scene, const GlbPrimitive& prim) {
  int r = 200, g = 200, b = 200;
  if (prim.material_index < scene.gltf_materials.size()) {
    const auto& mat = scene.gltf_materials[prim.material_index];
    const auto& factor = mat.pbr_metallic_roughness.base_color_factor;
    r = static_cast<int>(std::round(factor[0] * 255.0));
    g = static_cast<int>(std::round(factor[1] * 255.0));
    b = static_cast<int>(std::round(factor[2] * 255.0));
  }
  return {std::max(0, std::min(255, r)), std::max(0, std::min(255, g)),
          std::max(0, std::min(255, b))};
}

std::string to_dxf(const Scene& scene, double scale, const std::string& mode) {
  (void)mode;
  std::map<std::string, std::tuple<int, int, int>> layer_colors;
  for (const auto& prim : scene.glb_primitives) {
    std::string l_name = sanitize_layer_name(prim.geom_name);
    if (layer_colors.find(l_name) == layer_colors.end()) {
      layer_colors[l_name] = get_prim_rgb(scene, prim);
    }
  }

  if (layer_colors.empty()) {
    layer_colors["0"] = {200, 200, 200};
  }

  uint64_t handle_id = 0x100;
  auto next_handle = [&handle_id]() -> std::string {
    std::stringstream ss_h;
    ss_h << std::hex << std::uppercase << handle_id++;
    return ss_h.str();
  };

  std::map<std::string, std::string> layer_handles;
  for (const auto& [l_name, rgb] : layer_colors) {
    (void)rgb;
    layer_handles[l_name] = next_handle();
  }

  std::stringstream ss;
  ss << "  0\r\nSECTION\r\n  2\r\nHEADER\r\n"
     << "  9\r\n$ACADVER\r\n  1\r\nAC1015\r\n"
     << "  9\r\n$ACADMAINTVER\r\n 70\r\n6\r\n"
     << "  9\r\n$DWGCODEPAGE\r\n  3\r\nANSI_1252\r\n"
     << "  9\r\n$INSBASE\r\n 10\r\n0.0\r\n 20\r\n0.0\r\n 30\r\n0.0\r\n"
     << "  9\r\n$EXTMIN\r\n 10\r\n1e+20\r\n 20\r\n1e+20\r\n 30\r\n1e+20\r\n"
     << "  9\r\n$EXTMAX\r\n 10\r\n-1e+20\r\n 20\r\n-1e+20\r\n 30\r\n-1e+20\r\n"
     << "  9\r\n$LIMMIN\r\n 10\r\n0.0\r\n 20\r\n0.0\r\n"
     << "  9\r\n$LIMMAX\r\n 10\r\n420.0\r\n 20\r\n297.0\r\n"
     << "  9\r\n$ORTHOMODE\r\n 70\r\n0\r\n"
     << "  9\r\n$REGENMODE\r\n 70\r\n1\r\n"
     << "  9\r\n$FILLMODE\r\n 70\r\n1\r\n"
     << "  9\r\n$QTEXTMODE\r\n 70\r\n0\r\n"
     << "  9\r\n$MIRRTEXT\r\n 70\r\n1\r\n"
     << "  9\r\n$LTSCALE\r\n 40\r\n1.0\r\n"
     << "  9\r\n$ATTMODE\r\n 70\r\n1\r\n"
     << "  9\r\n$TEXTSIZE\r\n 40\r\n2.5\r\n"
     << "  9\r\n$TRACEWID\r\n 40\r\n1.0\r\n"
     << "  9\r\n$TEXTSTYLE\r\n  7\r\nStandard\r\n"
     << "  9\r\n$CLAYER\r\n  8\r\n0\r\n"
     << "  9\r\n$CELTYPE\r\n  6\r\nByLayer\r\n"
     << "  9\r\n$CECOLOR\r\n 62\r\n256\r\n"
     << "  9\r\n$CELTSCALE\r\n 40\r\n1.0\r\n"
     << "  9\r\n$DISPSILH\r\n 70\r\n0\r\n"
     << "  9\r\n$HANDSEED\r\n  5\r\n__HANDSEED__\r\n"
     << "  9\r\n$INSUNITS\r\n 70\r\n1\r\n"
     << "  0\r\nENDSEC\r\n"
     << "  0\r\nSECTION\r\n  2\r\nCLASSES\r\n"
     << "  0\r\nCLASS\r\n  1\r\nACDBDICTIONARYWDFLT\r\n  2\r\nAcDbDictionaryWithDefault\r\n  "
        "3\r\nObjectDBX Classes\r\n 90\r\n0\r\n 91\r\n0\r\n280\r\n0\r\n281\r\n0\r\n"
     << "  0\r\nENDSEC\r\n"
     << "  0\r\nSECTION\r\n  2\r\nTABLES\r\n"
     << "  0\r\nTABLE\r\n  2\r\nVPORT\r\n  5\r\n1F\r\n100\r\nAcDbSymbolTable\r\n 70\r\n0\r\n  "
        "0\r\nENDTAB\r\n"
     << "  0\r\nTABLE\r\n  2\r\nLTYPE\r\n  5\r\n20\r\n100\r\nAcDbSymbolTable\r\n 70\r\n1\r\n"
     << "  0\r\nLTYPE\r\n  "
        "5\r\n21\r\n100\r\nAcDbSymbolTableRecord\r\n100\r\nAcDbLinetypeTableRecord\r\n  "
        "2\r\nBYBLOCK\r\n 70\r\n0\r\n  3\r\n\r\n 72\r\n65\r\n 73\r\n0\r\n 40\r\n0.0\r\n"
     << "  0\r\nLTYPE\r\n  "
        "5\r\n22\r\n100\r\nAcDbSymbolTableRecord\r\n100\r\nAcDbLinetypeTableRecord\r\n  "
        "2\r\nBYLAYER\r\n 70\r\n0\r\n  3\r\n\r\n 72\r\n65\r\n 73\r\n0\r\n 40\r\n0.0\r\n"
     << "  0\r\nLTYPE\r\n  "
        "5\r\n23\r\n100\r\nAcDbSymbolTableRecord\r\n100\r\nAcDbLinetypeTableRecord\r\n  "
        "2\r\nCONTINUOUS\r\n 70\r\n0\r\n  3\r\nSolid line\r\n 72\r\n65\r\n 73\r\n0\r\n "
        "40\r\n0.0\r\n"
     << "  0\r\nENDTAB\r\n"
     << "  0\r\nTABLE\r\n  2\r\nLAYER\r\n  5\r\n4\r\n100\r\nAcDbSymbolTable\r\n 70\r\n"
     << (layer_colors.size() + 1) << "\r\n"
     << "  0\r\nLAYER\r\n  "
        "5\r\n27\r\n330\r\n4\r\n100\r\nAcDbSymbolTableRecord\r\n100\r\nAcDbLayerTableRecord\r\n  "
        "2\r\n0\r\n 70\r\n0\r\n 62\r\n7\r\n  6\r\nContinuous\r\n"
     << "  0\r\nLAYER\r\n  "
        "5\r\n28\r\n330\r\n4\r\n100\r\nAcDbSymbolTableRecord\r\n100\r\nAcDbLayerTableRecord\r\n  "
        "2\r\nDefpoints\r\n 70\r\n0\r\n 62\r\n7\r\n  6\r\nContinuous\r\n";

  for (const auto& [l_name, rgb] : layer_colors) {
    auto [lr, lg, lb] = rgb;
    int aci = rgb_to_aci(lr, lg, lb);
    int true_color = (lr << 16) | (lg << 8) | lb;
    ss << "  0\r\nLAYER\r\n  5\r\n"
       << layer_handles[l_name]
       << "\r\n330\r\n4\r\n100\r\nAcDbSymbolTableRecord\r\n100\r\nAcDbLayerTableRecord\r\n  2\r\n"
       << l_name << "\r\n 70\r\n0\r\n 62\r\n"
       << aci << "\r\n420\r\n"
       << true_color << "\r\n  6\r\nContinuous\r\n";
  }

  ss << "  0\r\nENDTAB\r\n"
     << "  0\r\nTABLE\r\n  2\r\nSTYLE\r\n  5\r\n25\r\n100\r\nAcDbSymbolTable\r\n 70\r\n0\r\n  "
        "0\r\nENDTAB\r\n"
     << "  0\r\nTABLE\r\n  2\r\nVIEW\r\n  5\r\n26\r\n100\r\nAcDbSymbolTable\r\n 70\r\n0\r\n  "
        "0\r\nENDTAB\r\n"
     << "  0\r\nTABLE\r\n  2\r\nUCS\r\n  5\r\n27\r\n100\r\nAcDbSymbolTable\r\n 70\r\n0\r\n  "
        "0\r\nENDTAB\r\n"
     << "  0\r\nTABLE\r\n  2\r\nAPPID\r\n  5\r\n28\r\n100\r\nAcDbSymbolTable\r\n 70\r\n1\r\n"
     << "  0\r\nAPPID\r\n  "
        "5\r\n29\r\n100\r\nAcDbSymbolTableRecord\r\n100\r\nAcDbRegAppTableRecord\r\n  "
        "2\r\nACAD\r\n 70\r\n0\r\n"
     << "  0\r\nENDTAB\r\n"
     << "  0\r\nTABLE\r\n  2\r\nDIMSTYLE\r\n  5\r\n2A\r\n100\r\nAcDbSymbolTable\r\n 70\r\n0\r\n  "
        "0\r\nENDTAB\r\n"
     << "  0\r\nTABLE\r\n  2\r\nBLOCK_RECORD\r\n  5\r\n2B\r\n100\r\nAcDbSymbolTable\r\n 70\r\n2\r\n"
     << "  0\r\nBLOCK_RECORD\r\n  "
        "5\r\n17\r\n330\r\n2B\r\n100\r\nAcDbSymbolTableRecord\r\n100\r\nAcDbBlockTableRecord\r\n  "
        "2\r\n*Model_Space\r\n"
     << "  0\r\nBLOCK_RECORD\r\n  "
        "5\r\n1B\r\n330\r\n2B\r\n100\r\nAcDbSymbolTableRecord\r\n100\r\nAcDbBlockTableRecord\r\n  "
        "2\r\n*Paper_Space\r\n"
     << "  0\r\nENDTAB\r\n  0\r\nENDSEC\r\n"
     << "  0\r\nSECTION\r\n  2\r\nBLOCKS\r\n"
     << "  0\r\nBLOCK\r\n  5\r\n18\r\n330\r\n17\r\n100\r\nAcDbEntity\r\n  "
        "8\r\n0\r\n100\r\nAcDbBlockBegin\r\n  2\r\n*Model_Space\r\n 70\r\n0\r\n 10\r\n0.0\r\n "
        "20\r\n0.0\r\n 30\r\n0.0\r\n  3\r\n*Model_Space\r\n  1\r\n\r\n"
     << "  0\r\nENDBLK\r\n  5\r\n19\r\n330\r\n17\r\n100\r\nAcDbEntity\r\n  "
        "8\r\n0\r\n100\r\nAcDbBlockEnd\r\n"
     << "  0\r\nBLOCK\r\n  5\r\n1C\r\n330\r\n1B\r\n100\r\nAcDbEntity\r\n  "
        "8\r\n0\r\n100\r\nAcDbBlockBegin\r\n  2\r\n*Paper_Space\r\n 70\r\n0\r\n 10\r\n0.0\r\n "
        "20\r\n0.0\r\n 30\r\n0.0\r\n  3\r\n*Paper_Space\r\n  1\r\n\r\n"
     << "  0\r\nENDBLK\r\n  5\r\n1D\r\n330\r\n1B\r\n100\r\nAcDbEntity\r\n  "
        "8\r\n0\r\n100\r\nAcDbBlockEnd\r\n"
     << "  0\r\nENDSEC\r\n"
     << "  0\r\nSECTION\r\n  2\r\nENTITIES\r\n";

  ss << std::fixed << std::setprecision(6);
  for (const auto& prim : scene.glb_primitives) {
    std::string l_name = sanitize_layer_name(prim.geom_name);
    size_t tri_count = prim.indices.size() / 3;
    if (tri_count == 0) continue;

    auto [pr, pg, pb] = get_prim_rgb(scene, prim);
    int aci = rgb_to_aci(pr, pg, pb);

    for (size_t i = 0; i < tri_count; ++i) {
      uint32_t i0 = prim.indices[i * 3];
      uint32_t i1 = prim.indices[i * 3 + 1];
      uint32_t i2 = prim.indices[i * 3 + 2];

      double v0x = prim.positions[i0 * 3] * scale;
      double v0y = prim.positions[i0 * 3 + 1] * scale;
      double v0z = prim.positions[i0 * 3 + 2] * scale;

      double v1x = prim.positions[i1 * 3] * scale;
      double v1y = prim.positions[i1 * 3 + 1] * scale;
      double v1z = prim.positions[i1 * 3 + 2] * scale;

      double v2x = prim.positions[i2 * 3] * scale;
      double v2y = prim.positions[i2 * 3 + 1] * scale;
      double v2z = prim.positions[i2 * 3 + 2] * scale;

      ss << "  0\r\n3DFACE\r\n  5\r\n"
         << next_handle() << "\r\n330\r\n17\r\n100\r\nAcDbEntity\r\n  8\r\n"
         << l_name << "\r\n 62\r\n"
         << aci << "\r\n100\r\nAcDbFace\r\n"
         << " 10\r\n"
         << v0x << "\r\n 20\r\n"
         << v0y << "\r\n 30\r\n"
         << v0z << "\r\n"
         << " 11\r\n"
         << v1x << "\r\n 21\r\n"
         << v1y << "\r\n 31\r\n"
         << v1z << "\r\n"
         << " 12\r\n"
         << v2x << "\r\n 22\r\n"
         << v2y << "\r\n 32\r\n"
         << v2z << "\r\n"
         << " 13\r\n"
         << v2x << "\r\n 23\r\n"
         << v2y << "\r\n 33\r\n"
         << v2z << "\r\n";
    }
  }

  ss << "  0\r\nENDSEC\r\n"
     << "  0\r\nSECTION\r\n  2\r\nOBJECTS\r\n"
     << "  0\r\nDICTIONARY\r\n  5\r\nA\r\n330\r\n0\r\n100\r\nAcDbDictionary\r\n281\r\n1\r\n"
     << "  3\r\nACAD_COLOR\r\n350\r\nB\r\n"
     << "  3\r\nACAD_GROUP\r\n350\r\nC\r\n"
     << "  3\r\nACAD_LAYOUT\r\n350\r\nD\r\n"
     << "  3\r\nACAD_MATERIAL\r\n350\r\nE\r\n"
     << "  3\r\nACAD_MLEADERSTYLE\r\n350\r\nF\r\n"
     << "  3\r\nACAD_MLINESTYLE\r\n350\r\n10\r\n"
     << "  3\r\nACAD_PLOTSETTINGS\r\n350\r\n11\r\n"
     << "  3\r\nACAD_PLOTSTYLENAME\r\n350\r\n12\r\n"
     << "  3\r\nACAD_SCALELIST\r\n350\r\n14\r\n"
     << "  3\r\nACAD_TABLESTYLE\r\n350\r\n15\r\n"
     << "  3\r\nACAD_VISUALSTYLE\r\n350\r\n16\r\n"
     << "  0\r\nDICTIONARY\r\n  5\r\nB\r\n330\r\nA\r\n100\r\nAcDbDictionary\r\n281\r\n1\r\n"
     << "  0\r\nDICTIONARY\r\n  5\r\nC\r\n330\r\nA\r\n100\r\nAcDbDictionary\r\n281\r\n1\r\n"
     << "  0\r\nDICTIONARY\r\n  5\r\nD\r\n330\r\nA\r\n100\r\nAcDbDictionary\r\n281\r\n1\r\n  "
        "3\r\nModel\r\n350\r\n1A\r\n  3\r\nLayout1\r\n350\r\n1E\r\n"
     << "  0\r\nDICTIONARY\r\n  5\r\nE\r\n330\r\nA\r\n100\r\nAcDbDictionary\r\n281\r\n1\r\n"
     << "  0\r\nDICTIONARY\r\n  5\r\nF\r\n330\r\nA\r\n100\r\nAcDbDictionary\r\n281\r\n1\r\n"
     << "  0\r\nDICTIONARY\r\n  5\r\n10\r\n330\r\nA\r\n100\r\nAcDbDictionary\r\n281\r\n1\r\n"
     << "  0\r\nDICTIONARY\r\n  5\r\n11\r\n330\r\nA\r\n100\r\nAcDbDictionary\r\n281\r\n1\r\n"
     << "  0\r\nACDBDICTIONARYWDFLT\r\n  "
        "5\r\n12\r\n330\r\nA\r\n100\r\nAcDbDictionary\r\n281\r\n1\r\n  "
        "3\r\nNormal\r\n350\r\n13\r\n100\r\nAcDbDictionaryWithDefault\r\n340\r\n13\r\n"
     << "  0\r\nACDBPLACEHOLDER\r\n  5\r\n13\r\n330\r\n12\r\n"
     << "  0\r\nDICTIONARY\r\n  5\r\n14\r\n330\r\nA\r\n100\r\nAcDbDictionary\r\n281\r\n1\r\n"
     << "  0\r\nDICTIONARY\r\n  5\r\n15\r\n330\r\nA\r\n100\r\nAcDbDictionary\r\n281\r\n1\r\n"
     << "  0\r\nDICTIONARY\r\n  5\r\n16\r\n330\r\nA\r\n100\r\nAcDbDictionary\r\n281\r\n1\r\n"
     << "  0\r\nLAYOUT\r\n  5\r\n1A\r\n330\r\nD\r\n100\r\nAcDbPlotSettings\r\n  1\r\n\r\n  "
        "4\r\nA3\r\n  6\r\n\r\n 40\r\n7.5\r\n 41\r\n20.0\r\n 42\r\n7.5\r\n 43\r\n20.0\r\n "
        "44\r\n420.0\r\n 45\r\n297.0\r\n 46\r\n0.0\r\n 47\r\n0.0\r\n 48\r\n0.0\r\n "
        "49\r\n0.0\r\n140\r\n0.0\r\n141\r\n0.0\r\n142\r\n1.0\r\n143\r\n1.0\r\n 70\r\n1024\r\n "
        "72\r\n1\r\n 73\r\n0\r\n 74\r\n5\r\n  7\r\n\r\n 75\r\n16\r\n 76\r\n0\r\n 77\r\n2\r\n "
        "78\r\n300\r\n147\r\n1.0\r\n148\r\n0.0\r\n149\r\n0.0\r\n100\r\nAcDbLayout\r\n  "
        "1\r\nModel\r\n 70\r\n1\r\n 71\r\n0\r\n 10\r\n0.0\r\n 20\r\n0.0\r\n 11\r\n420.0\r\n "
        "21\r\n297.0\r\n 12\r\n0.0\r\n 22\r\n0.0\r\n 32\r\n0.0\r\n 14\r\n1e+20\r\n 24\r\n1e+20\r\n "
        "34\r\n1e+20\r\n 15\r\n-1e+20\r\n 25\r\n-1e+20\r\n 35\r\n-1e+20\r\n146\r\n0.0\r\n "
        "13\r\n0.0\r\n 23\r\n0.0\r\n 33\r\n0.0\r\n 16\r\n1.0\r\n 26\r\n0.0\r\n 36\r\n0.0\r\n "
        "17\r\n0.0\r\n 27\r\n1.0\r\n 76\r\n1\r\n330\r\n17\r\n"
     << "  0\r\nLAYOUT\r\n  5\r\n1E\r\n330\r\nD\r\n100\r\nAcDbPlotSettings\r\n  1\r\n\r\n  "
        "4\r\nA3\r\n  6\r\n\r\n 40\r\n7.5\r\n 41\r\n20.0\r\n 42\r\n7.5\r\n 43\r\n20.0\r\n "
        "44\r\n420.0\r\n 45\r\n297.0\r\n 46\r\n0.0\r\n 47\r\n0.0\r\n 48\r\n0.0\r\n "
        "49\r\n0.0\r\n140\r\n0.0\r\n141\r\n0.0\r\n142\r\n1.0\r\n143\r\n1.0\r\n 70\r\n0\r\n "
        "72\r\n1\r\n 73\r\n0\r\n 74\r\n5\r\n  7\r\n\r\n 75\r\n16\r\n 76\r\n0\r\n 77\r\n2\r\n "
        "78\r\n300\r\n147\r\n1.0\r\n148\r\n0.0\r\n149\r\n0.0\r\n100\r\nAcDbLayout\r\n  "
        "1\r\nLayout1\r\n 70\r\n1\r\n 71\r\n1\r\n 10\r\n0.0\r\n 20\r\n0.0\r\n 11\r\n420.0\r\n "
        "21\r\n297.0\r\n 12\r\n0.0\r\n 22\r\n0.0\r\n 32\r\n0.0\r\n 14\r\n1e+20\r\n 24\r\n1e+20\r\n "
        "34\r\n1e+20\r\n 15\r\n-1e+20\r\n 25\r\n-1e+20\r\n 35\r\n-1e+20\r\n146\r\n0.0\r\n "
        "13\r\n0.0\r\n 23\r\n0.0\r\n 33\r\n0.0\r\n 16\r\n1.0\r\n 26\r\n0.0\r\n 36\r\n0.0\r\n "
        "17\r\n0.0\r\n 27\r\n1.0\r\n 76\r\n1\r\n330\r\n1B\r\n"
     << "  0\r\nENDSEC\r\n"
     << "  0\r\nEOF\r\n";

  std::string text = ss.str();
  std::stringstream hs_stream;
  hs_stream << std::hex << std::uppercase << (handle_id + 0x10);
  std::string handseed_str = hs_stream.str();

  size_t pos = text.find("__HANDSEED__");
  if (pos != std::string::npos) {
    text.replace(pos, 12, handseed_str);
  }
  return text;
}

void export_dxf(const Scene& scene, const std::filesystem::path& path, double scale,
                const std::string& mode) {
  std::filesystem::create_directories(path.parent_path());
  std::string content = to_dxf(scene, scale, mode);
  std::ofstream file(path, std::ios::binary);
  if (!file.is_open()) {
    throw std::runtime_error("Failed to open output file: " + path.string());
  }
  file.write(content.data(), content.size());
}

}  // namespace openskp
