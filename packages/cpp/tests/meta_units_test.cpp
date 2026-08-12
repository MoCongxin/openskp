#include <gtest/gtest.h>

#include <openskp/openskp.hpp>

#include "internal.hpp"
#include "test_helpers.hpp"

// SkpModel::units - the model's unit-system string, read from
// meta/meta.dat in VFF files. Never opened by any parser before this
// (zero references to the filename anywhere in the codebase). Confirmed
// plaintext payload in a real fixture (Untitled.skp): meta.dat uses the
// same low-level TLV framing as model.dat (2-byte tag + 4-byte
// little-endian length + payload), one flat record list wrapped in a
// single outer record (tag 0x6400); tag 0x6D00 carries the units string
// as plain text.

namespace openskp::test {
namespace {

ByteBuffer hex_to_bytes(const std::string& hex) {
  ByteBuffer out(hex.size() / 2);
  for (std::size_t i = 0; i < out.size(); ++i)
    out[i] = static_cast<std::uint8_t>(std::stoul(hex.substr(i * 2, 2), nullptr, 16));
  return out;
}

TEST(MetaUnits, ExtractsUnitsFromExactRealFixtureBytes) {
  // The leading records of the real 388-byte meta/meta.dat payload from a
  // real VFF fixture (Untitled.skp, SketchUp 25.0.575) - byte-for-byte, not
  // hand-crafted - truncated right after the "6D00" units record, since
  // read_meta_units returns as soon as it finds that tag and never needs
  // the trailing save-path/thumbnail-metadata records that follow it in the
  // real file.
  const ByteBuffer payload = hex_to_bytes(
      "6400"
      "f2000000"  // 242 = the truncated inner payload's real length, not
                  // the original 388-byte file's 0x17e/382 - the outer
                  // record's declared length must match what's actually
                  // present after truncation or the bounds-checked parser
                  // correctly rejects it as malformed.
      "7500"
      "08000000"
      "32352e302e353735"  // "25.0.575"
      "7600"
      "02000000"
      "1800"
      "7700"
      "02000000"
      "0200"
      "7300"
      "02000000"
      "0100"
      "7400"
      "02000000"
      "1100"
      "6600"
      "10000000"
      "dcd4752a383d724783022fa29cda3224"
      "6700"
      "2e000000"
      "2823"
      "28000000"
      "2923"
      "04000000"
      "04000000"
      "2a23"
      "18000000"
      "6d6574612f6d6f64656c5f7468756d626e61696c2e706e67"  // "meta/model_thumbnail.png"
      "6800"
      "30000000"
      "2823"
      "2a000000"
      "2923"
      "04000000"
      "04000000"
      "2a23"
      "1a000000"
      "6d6574612f707265766965775f7468756d626e61696c2e706e67"  // "meta/preview_thumbnail.png"
      "6900"
      "01000000"
      "01"
      "6a00"
      "00000000"
      "6b00"
      "00000000"
      "6c00"
      "00000000"
      "6e00"
      "00000000"
      "7100"
      "01000000"
      "00"
      "7900"
      "01000000"
      "00"
      "7200"
      "01000000"
      "00"
      "6d00"
      "0a000000"
      "4d696c6c696d65746572");  // "Millimeter"

  auto result = read_meta_units(payload);
  ASSERT_TRUE(result.has_value());
  EXPECT_EQ(*result, "Millimeter");
}

TEST(MetaUnits, ExtractsUnitsFromMinimalSyntheticRecord) {
  auto inner = tlv("6D00", bytes("Inches"));
  auto outer = tlv("6400", inner);

  auto result = read_meta_units(outer);
  ASSERT_TRUE(result.has_value());
  EXPECT_EQ(*result, "Inches");
}

TEST(MetaUnits, ReturnsNulloptWhenUnitsTagAbsent) {
  auto inner = tlv("7500", bytes("25.0.575"));
  auto outer = tlv("6400", inner);

  EXPECT_FALSE(read_meta_units(outer).has_value());
}

TEST(MetaUnits, ReturnsNulloptForEmptyOrTruncatedBytes) {
  EXPECT_FALSE(read_meta_units(ByteBuffer{}).has_value());
  EXPECT_FALSE(read_meta_units(ByteBuffer{1, 2, 3}).has_value());
}

}  // namespace
}  // namespace openskp::test
