using System;
using System.Text;
using Xunit;
using OpenSkp;

namespace OpenSkp.Tests
{
    /// <summary>
    /// SkpModel.Units - the model's unit-system string, read from
    /// meta/meta.dat in VFF files. Never opened by any parser before this
    /// (zero references to the filename anywhere in the codebase).
    /// Confirmed plaintext payload in a real fixture (Untitled.skp):
    /// meta.dat uses the same low-level TLV framing as model.dat (2-byte
    /// tag + 4-byte little-endian length + payload), one flat record list
    /// wrapped in a single outer record (tag 0x6400); tag 0x6D00 carries
    /// the units string as plain text.
    /// </summary>
    public class MetaUnitsTests
    {
        private static byte[] Tlv(string tagHex, byte[] payload)
        {
            var tag = new byte[] { Convert.ToByte(tagHex.Substring(0, 2), 16), Convert.ToByte(tagHex.Substring(2, 2), 16) };
            var len = BitConverter.GetBytes((uint)payload.Length);
            var result = new byte[6 + payload.Length];
            Array.Copy(tag, 0, result, 0, 2);
            Array.Copy(len, 0, result, 2, 4);
            Array.Copy(payload, 0, result, 6, payload.Length);
            return result;
        }

        private static byte[] HexToBytes(string hex)
        {
            var result = new byte[hex.Length / 2];
            for (int i = 0; i < result.Length; i++)
            {
                result[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
            }
            return result;
        }

        [Fact]
        public void ExtractsUnitsFromExactRealFixtureBytes()
        {
            // The exact 388-byte meta/meta.dat payload from a real VFF
            // fixture (Untitled.skp, SketchUp 25.0.575) - byte-for-byte,
            // not hand-crafted.
            string hex =
                "6400" + "7e010000" +
                "7500" + "08000000" + Convert.ToHexString(Encoding.ASCII.GetBytes("25.0.575")) +
                "7600" + "02000000" + "1800" +
                "7700" + "02000000" + "0200" +
                "7300" + "02000000" + "0100" +
                "7400" + "02000000" + "1100" +
                "6600" + "10000000" + "dcd4752a383d724783022fa29cda3224" +
                "6700" + "2e000000" + "2823" + "28000000" + "2923" + "04000000" + "04000000" + "2a23" + "18000000" +
                    Convert.ToHexString(Encoding.ASCII.GetBytes("meta/model_thumbnail.png")) +
                "6800" + "30000000" + "2823" + "2a000000" + "2923" + "04000000" + "04000000" + "2a23" + "1a000000" +
                    Convert.ToHexString(Encoding.ASCII.GetBytes("meta/preview_thumbnail.png")) +
                "6900" + "01000000" + "01" +
                "6a00" + "00000000" +
                "6b00" + "00000000" +
                "6c00" + "00000000" +
                "6e00" + "00000000" +
                "7100" + "01000000" + "00" +
                "7900" + "01000000" + "00" +
                "7200" + "01000000" + "00" +
                "6d00" + "0a000000" + Convert.ToHexString(Encoding.ASCII.GetBytes("Millimeter")) +
                "7000" + "01000000" + "01" +
                "6f00" + "27000000" + Convert.ToHexString(Encoding.ASCII.GetBytes("E:/Devs/TEst/Skp Test/ref2/Untitled.skp")) +
                "7800" + "52000000" +
                    "c800" + "4c000000" +
                    "c900" + "46000000" +
                    "ca00" + "40000000" +
                    "cb00" + "22000000" + Convert.ToHexString(Encoding.ASCII.GetBytes("SketchUp Client (Windows) 25.0.575")) +
                "cc00" + "04000000" + "23c5326a" +
                "cd00" + "08000000" + "ec443dc9b4db9877";

            byte[] bytes = HexToBytes(hex);

            Assert.Equal("Millimeter", Vff.ReadMetaUnits(bytes));
        }

        [Fact]
        public void ExtractsUnitsFromMinimalSyntheticRecord()
        {
            var inner = Tlv("6D00", Encoding.UTF8.GetBytes("Inches"));
            var outer = Tlv("6400", inner);

            Assert.Equal("Inches", Vff.ReadMetaUnits(outer));
        }

        [Fact]
        public void ReturnsNullWhenUnitsTagAbsent()
        {
            var inner = Tlv("7500", Encoding.UTF8.GetBytes("25.0.575"));
            var outer = Tlv("6400", inner);

            Assert.Null(Vff.ReadMetaUnits(outer));
        }

        [Fact]
        public void ReturnsNullForEmptyOrTruncatedBytes()
        {
            Assert.Null(Vff.ReadMetaUnits(Array.Empty<byte>()));
            Assert.Null(Vff.ReadMetaUnits(new byte[] { 1, 2, 3 }));
        }
    }
}
