using System;
using System.IO;
using System.Linq;
using Xunit;
using OpenSkp;

namespace OpenSkp.Tests
{
    /// <summary>
    /// Real-file regression test for the classic (pre-2021) MFC .skp reader.
    ///
    /// Fixture: fixtures/capilla_quiroz_v17.skp - a small chapel authored in
    /// SketchUp 2017 (v17.0.18899, ~212 KB), the same real-file fixture Marco
    /// Sumari contributed for the Python legacy reader (PR #14), also used
    /// by the TypeScript port's legacy.test.ts. Every assertion here mirrors
    /// that test's byte-for-byte-matched values against Python ground truth.
    /// </summary>
    public class LegacyTests
    {
        private static string FixturePath(string name) =>
            Path.Combine(AppContext.BaseDirectory, "fixtures", name);

        [Fact]
        public void ParsesRealV17FileMatchingPythonGroundTruth()
        {
            var model = SkpFile.Open(FixturePath("capilla_quiroz_v17.skp"));

            Assert.Equal("{17.0.18899}", model.Version);

            // Definitions - ROOT is exposed separately via model.Root, so
            // only the two named component definitions show up here.
            Assert.Equal(2, model.Definitions.Count);

            Assert.True(model.Definitions.TryGetValue(40, out var puerta));
            Assert.Equal("puerta", puerta!.Name);
            Assert.Equal(24, puerta.Faces.Count);
            Assert.Equal(95, puerta.Edges.Count);
            Assert.Equal(64, puerta.Vertices.Count);

            Assert.True(model.Definitions.TryGetValue(395, out var grada));
            Assert.Equal("grada", grada!.Name);
            Assert.Equal(11, grada.Faces.Count);
            Assert.Equal(30, grada.Edges.Count);
            Assert.Equal(20, grada.Vertices.Count);

            Assert.True(puerta.Vertices.TryGetValue(45, out var v45));
            Assert.Equal(60.671292283583, v45!.X, 9);
            Assert.True(Math.Abs(v45.Y - 8.526512829121202e-14) < 1e-18);
            Assert.Equal(109.03580700984524, v45.Z, 9);

            Assert.Equal(16, model.Materials.Count);
            var materialNames = model.Materials.Select(m => m.Name).OrderBy(n => n, StringComparer.Ordinal).ToList();
            var expectedNames = new[]
            {
                "*1",
                "[0037_SandyBrown]",
                "[0048_PaleGoldenrod]",
                "[0050_LemonChiffon]",
                "[0062_YellowGreen]",
                "[0064_Chartreuse]",
                "[0069_LimeGreen]",
                "[0070_SpringGreen]",
                "[0097_DeepSkyBlue]",
                "[0102_RoyalBlue]",
                "[Color G03]",
                "[Polished Concrete New]",
                "[Polished Concrete Old]",
                "[Roofing Tile Spanish]",
                "[Translucent Glass Blue]",
                "[Translucent Glass Safety]",
            }.OrderBy(n => n, StringComparer.Ordinal).ToList();
            Assert.Equal(expectedNames, materialNames);

            Assert.Single(model.Layers);
            Assert.Equal("Layer0", model.Layers[0].Name);
            Assert.False(model.Layers[0].Hidden);

            double minX = double.PositiveInfinity, minY = double.PositiveInfinity, minZ = double.PositiveInfinity;
            double maxX = double.NegativeInfinity, maxY = double.NegativeInfinity, maxZ = double.NegativeInfinity;
            foreach (var d in model.Definitions.Values)
            {
                foreach (var v in d.Vertices.Values)
                {
                    if (v.X < minX) minX = v.X;
                    if (v.X > maxX) maxX = v.X;
                    if (v.Y < minY) minY = v.Y;
                    if (v.Y > maxY) maxY = v.Y;
                    if (v.Z < minZ) minZ = v.Z;
                    if (v.Z > maxZ) maxZ = v.Z;
                }
            }
            Assert.Equal(0.0, minX, 2);
            Assert.Equal(0.0, minY, 2);
            Assert.Equal(0.0, minZ, 2);
            Assert.Equal(77.402, maxX, 2);
            Assert.Equal(51.969, maxY, 2);
            Assert.Equal(133.071, maxZ, 2);

            // Root-level placements: 3 instances (2x grada, 1x puerta).
            // ref_idx on the legacy path is the definition's slot id
            // (legacy instances carry no guid, matching Python/TS's
            // ref_guid = "" for this path).
            Assert.Equal(3, model.Root.Instances.Count);
            var byRefIdx = model.Root.Instances
                .Select(i => model.Definitions.TryGetValue(i.RefIdx ?? -1, out var dd) ? dd.Name : null)
                .OrderBy(n => n, StringComparer.Ordinal)
                .ToList();
            Assert.Equal(new[] { "grada", "grada", "puerta" }, byRefIdx);
            Assert.All(model.Root.Instances, i => Assert.False(i.Hidden));
            foreach (var defn in model.Definitions.Values)
            {
                Assert.All(defn.Faces.Values, f => Assert.False(f.Hidden));
            }
        }

        [Fact]
        public void DetectsLegacyContainer()
        {
            var bytes = File.ReadAllBytes(FixturePath("capilla_quiroz_v17.skp"));
            Assert.True(Legacy.IsLegacy(bytes));
        }
    }

    /// <summary>
    /// Both MFC class-ref encodings the definition-tail scanner must match.
    /// Mirrors packages/python/tests/test_parser.py::TestLegacyClassRef
    /// (openskp#28 / #39): once a class slot passes 0x7FFF the short 16-bit
    /// form 0x8000|slot can't fit, so MFC escalates to the big-tag escape
    /// (0x7FFF followed by a u32 of 0x80000000|slot).
    /// </summary>
    public class LegacyClassRefTests
    {
        [Fact]
        public void ShortForm()
        {
            var data = BitConverter.GetBytes((ushort)(0x8000 | 278));
            Assert.True(LegacyBytes.IsClassRef(data, 0, 278));
            Assert.False(LegacyBytes.IsClassRef(data, 0, 279));
        }

        [Fact]
        public void BigTagEscape()
        {
            // slot 65712 does not fit in 0x8000|slot: MFC writes 0x7FFF + u32
            var data = new byte[6];
            BitConverter.GetBytes((ushort)0x7FFF).CopyTo(data, 0);
            BitConverter.GetBytes(0x80000000u | 65712).CopyTo(data, 2);
            Assert.True(LegacyBytes.IsClassRef(data, 0, 65712));
            Assert.False(LegacyBytes.IsClassRef(data, 0, 65713));
        }

        [Fact]
        public void BigSlotNeverMatchesShortForm()
        {
            // the pre-fix scanner compared a u16 read against 0x8000|65712,
            // which cannot fit in 16 bits - the truncated value must not match
            var data = BitConverter.GetBytes(unchecked((ushort)(0x8000 | 65712)));
            Assert.False(LegacyBytes.IsClassRef(data, 0, 65712));
        }

        [Fact]
        public void TruncatedData()
        {
            var data = new byte[] { 0xFF, 0x7F, 0xB0 };
            Assert.False(LegacyBytes.IsClassRef(data, 0, 65712));
        }
    }
}
