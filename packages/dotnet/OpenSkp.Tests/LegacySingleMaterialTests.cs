using System;
using System.IO;
using System.Linq;
using Xunit;
using OpenSkp;

namespace OpenSkp.Tests
{
    /// <summary>
    /// Regression test for legacy (pre-2021 MFC) .skp files with fewer than
    /// two materials.
    ///
    /// The archive's absolute slot numbering is normally bootstrapped by
    /// parsing two CMaterial records with a throwaway archive and reading
    /// the second one's own class-ref tag - that trick needs at least 2
    /// materials and doesn't work for a file with 0 or 1. Every fixture
    /// that predates this test (capilla_quiroz_v17.skp, gondola_v20.skp,
    /// Untitled.skp) happens to have several materials, so this gap went
    /// unnoticed - see openskp#158.
    ///
    /// Fixtures: blank_v17.skp (0 materials) and single_material_v17.skp
    /// (1 material named "RedMat") - both saved as legacy v17 directly via
    /// the official SketchUp SDK (SUModelSaveToFileWithVersion), so their
    /// content is SketchUp's own built-in empty-document boilerplate plus
    /// one synthetic material, not user/client data.
    /// </summary>
    public class LegacySingleMaterialTests
    {
        private static string FixturePath(string name) =>
            Path.Combine(AppContext.BaseDirectory, "fixtures", name);

        [Fact]
        public void ParsesAZeroMaterialLegacyFile()
        {
            // No CMaterial record anywhere in this file - exercises the
            // CLayer-pattern fallback for locating the walk's start
            // position, not just the bootstrap trick itself.
            var model = SkpFile.Open(FixturePath("blank_v17.skp"));

            Assert.Equal("{17.0.1}", model.Version);
            Assert.Empty(model.Materials);
            var names = model.Layers.Select(l => l.Name).ToList();
            Assert.Single(names);
            Assert.Equal("Layer0", names[0]);
            Assert.Empty(model.Definitions);
            Assert.Empty(model.Root.Instances);
        }

        [Fact]
        public void ParsesASingleMaterialLegacyFile()
        {
            var model = SkpFile.Open(FixturePath("single_material_v17.skp"));

            Assert.Equal("{17.0.1}", model.Version);
            Assert.Single(model.Materials);
            Assert.Equal("RedMat", model.Materials[0].Name);
            var names = model.Layers.Select(l => l.Name).ToList();
            Assert.Single(names);
            Assert.Equal("Layer0", names[0]);
        }
    }
}
