using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using Xunit;
using OpenSkp;

namespace OpenSkp.Tests
{
    /// <summary>
    /// Tests for GlbExport - the from-scratch binary glTF (.glb) writer
    /// (no external dependency, matching how this project stays
    /// dependency-light everywhere except C++'s bundled TinyGLTF).
    /// Uses System.Text.Json here only to parse the *output* for
    /// assertions - that's part of the modern .NET SDK the test project
    /// already targets (net9.0), not a new dependency on the library
    /// itself (which stays netstandard2.0, hence GlbExport's own
    /// hand-rolled MiniJson).
    /// </summary>
    public class GlbTests
    {
        private static string FixturePath(string name) =>
            Path.Combine(AppContext.BaseDirectory, "fixtures", name);

        private static Scene TriangleScene()
        {
            return new Scene
            {
                GltfMaterials = new System.Collections.Generic.List<object>
                {
                    new
                    {
                        pbrMetallicRoughness = new
                        {
                            baseColorFactor = new[] { 0.25, 0.5, 0.75, 1.0 },
                            metallicFactor = 0.1,
                            roughnessFactor = 0.9,
                        },
                    },
                },
                GlbPrimitives = new System.Collections.Generic.List<GlbPrimitive>
                {
                    new GlbPrimitive
                    {
                        Positions = new float[] { 1, 2, 3, -4, 5, 0, 2, -1, 7 },
                        Normals = new float[] { 0, 0, 1, 0, 0, 1, 0, 0, 1 },
                        Uvs = new float[] { 0, 0, 1, 0, 0, 1 },
                        Indices = new uint[] { 0, 1, 2 },
                        MaterialIndex = 0,
                        GeomName = "triangle",
                    },
                },
            };
        }

        [Fact]
        public void SerializesSceneAndBinaryData()
        {
            var bytes = GlbExport.ToGlb(TriangleScene());
            Assert.True(bytes.Length >= 12);
            Assert.Equal("glTF", Encoding.ASCII.GetString(bytes, 0, 4));

            var (json, binary) = ParseGlb(bytes);
            Assert.Equal("2.0", json.GetProperty("asset").GetProperty("version").GetString());

            var meshes = json.GetProperty("meshes");
            Assert.Equal(1, meshes.GetArrayLength());
            var prim = meshes[0].GetProperty("primitives")[0];
            var attrs = prim.GetProperty("attributes");
            Assert.True(attrs.TryGetProperty("POSITION", out _));
            Assert.True(attrs.TryGetProperty("NORMAL", out _));
            Assert.True(attrs.TryGetProperty("TEXCOORD_0", out _));
            Assert.Equal(0, prim.GetProperty("material").GetInt32());

            var accessors = json.GetProperty("accessors");
            var posAccessor = accessors[attrs.GetProperty("POSITION").GetInt32()];
            Assert.Equal(5126, posAccessor.GetProperty("componentType").GetInt32());
            Assert.Equal("VEC3", posAccessor.GetProperty("type").GetString());
            Assert.Equal(3, posAccessor.GetProperty("count").GetInt32());
            var min = posAccessor.GetProperty("min").EnumerateArray().Select(e => e.GetDouble()).ToArray();
            var max = posAccessor.GetProperty("max").EnumerateArray().Select(e => e.GetDouble()).ToArray();
            Assert.Equal(new[] { -4.0, -1.0, 0.0 }, min);
            Assert.Equal(new[] { 2.0, 5.0, 7.0 }, max);

            var uvAccessor = accessors[attrs.GetProperty("TEXCOORD_0").GetInt32()];
            Assert.Equal(5126, uvAccessor.GetProperty("componentType").GetInt32());
            Assert.Equal("VEC2", uvAccessor.GetProperty("type").GetString());
            Assert.Equal(3, uvAccessor.GetProperty("count").GetInt32());
            var uvBufferView = json.GetProperty("bufferViews")[uvAccessor.GetProperty("bufferView").GetInt32()];
            var uvOffset = uvBufferView.GetProperty("byteOffset").GetInt32();
            Assert.Equal(1.0f, BitConverter.ToSingle(binary, uvOffset + 2 * 4));

            var materials = json.GetProperty("materials");
            var pbr = materials[0].GetProperty("pbrMetallicRoughness");
            Assert.Equal(0.25, pbr.GetProperty("baseColorFactor")[0].GetDouble());
            Assert.Equal(0.1, pbr.GetProperty("metallicFactor").GetDouble());
            Assert.Equal(0.9, pbr.GetProperty("roughnessFactor").GetDouble());
        }

        [Fact]
        public void SerializesAnEmptyScene()
        {
            var bytes = GlbExport.ToGlb(new Scene());
            var (json, _) = ParseGlb(bytes);
            Assert.Equal(0, json.GetProperty("meshes").GetArrayLength());
            Assert.Equal(0, json.GetProperty("nodes").GetArrayLength());
        }

        [Fact]
        public void RejectsMalformedGeometry()
        {
            var scene = TriangleScene();
            scene.GlbPrimitives[0].Positions = scene.GlbPrimitives[0].Positions.Take(8).ToArray();
            Assert.Throws<ArgumentException>(() => GlbExport.ToGlb(scene));

            scene = TriangleScene();
            scene.GlbPrimitives[0].Normals = scene.GlbPrimitives[0].Normals.Take(2).ToArray();
            Assert.Throws<ArgumentException>(() => GlbExport.ToGlb(scene));

            scene = TriangleScene();
            scene.GlbPrimitives[0].Uvs = scene.GlbPrimitives[0].Uvs.Take(1).ToArray();
            Assert.Throws<ArgumentException>(() => GlbExport.ToGlb(scene));

            scene = TriangleScene();
            scene.GlbPrimitives[0].Indices = Array.Empty<uint>();
            Assert.Throws<ArgumentException>(() => GlbExport.ToGlb(scene));

            scene = TriangleScene();
            scene.GlbPrimitives[0].Indices = new uint[] { 0, 1, 5 };
            Assert.Throws<ArgumentException>(() => GlbExport.ToGlb(scene));

            scene = TriangleScene();
            scene.GlbPrimitives[0].MaterialIndex = 1;
            Assert.Throws<ArgumentException>(() => GlbExport.ToGlb(scene));
        }

        [Fact]
        public void RejectsNonFiniteValues()
        {
            var scene = TriangleScene();
            scene.GlbPrimitives[0].Positions[0] = float.NaN;
            Assert.Throws<ArgumentException>(() => GlbExport.ToGlb(scene));

            scene = TriangleScene();
            scene.GlbPrimitives[0].Normals[0] = float.PositiveInfinity;
            Assert.Throws<ArgumentException>(() => GlbExport.ToGlb(scene));

            scene = TriangleScene();
            scene.GlbPrimitives[0].Uvs[0] = float.NegativeInfinity;
            Assert.Throws<ArgumentException>(() => GlbExport.ToGlb(scene));
        }

        [Fact]
        public void ExportsRealFixtureMatchingToGlbAndBuildScene()
        {
            var scene = SkpFile.BuildScene(FixturePath("capilla_quiroz_v17.skp"));
            var expected = GlbExport.ToGlb(scene);

            var output = Path.Combine(Path.GetTempPath(), "openskp-dotnet-glb-test.glb");
            GlbExport.ExportGlb(scene, output);
            try
            {
                var actual = File.ReadAllBytes(output);
                Assert.Equal(expected, actual);

                var (json, binary) = ParseGlb(actual);
                var meshes = json.GetProperty("meshes")[0].GetProperty("primitives");
                Assert.Equal(scene.GlbPrimitives.Count, meshes.GetArrayLength());

                // Every primitive must carry TEXCOORD_0, and the decoded
                // values must exactly match the source GlbPrimitive.Uvs
                // that fed the writer - a real round-trip check, not
                // just "some accessor exists."
                for (var i = 0; i < scene.GlbPrimitives.Count; i++)
                {
                    var prim = scene.GlbPrimitives[i];
                    var attrs = meshes[i].GetProperty("attributes");
                    Assert.True(attrs.TryGetProperty("TEXCOORD_0", out var uvAccessorIdx));
                    var uvAccessor = json.GetProperty("accessors")[uvAccessorIdx.GetInt32()];
                    var uvBufferView = json.GetProperty("bufferViews")[uvAccessor.GetProperty("bufferView").GetInt32()];
                    var uvOffset = uvBufferView.GetProperty("byteOffset").GetInt32();
                    var uvCount = uvAccessor.GetProperty("count").GetInt32();
                    Assert.Equal(prim.Uvs.Length, uvCount * 2);
                    for (var j = 0; j < prim.Uvs.Length; j++)
                    {
                        Assert.Equal(prim.Uvs[j], BitConverter.ToSingle(binary, uvOffset + j * 4));
                    }
                }
            }
            finally
            {
                File.Delete(output);
            }
        }

        [Fact]
        public void ReportsFileFailuresWithoutCreatingDirectories()
        {
            var output = Path.Combine(Path.GetTempPath(), "openskp-missing-parent-" + Guid.NewGuid(), "asset.glb");
            Assert.ThrowsAny<Exception>(() => GlbExport.ExportGlb(TriangleScene(), output));
        }

        private static (JsonElement Json, byte[] Binary) ParseGlb(byte[] bytes)
        {
            var jsonChunkLen = BitConverter.ToUInt32(bytes, 12);
            var jsonStr = Encoding.UTF8.GetString(bytes, 20, (int)jsonChunkLen);
            var json = JsonDocument.Parse(jsonStr).RootElement;

            var binHeaderOffset = 20 + (int)jsonChunkLen;
            byte[] binary = Array.Empty<byte>();
            if (binHeaderOffset < bytes.Length)
            {
                var binChunkLen = BitConverter.ToUInt32(bytes, binHeaderOffset);
                binary = new byte[binChunkLen];
                Array.Copy(bytes, binHeaderOffset + 8, binary, 0, (int)binChunkLen);
            }
            return (json, binary);
        }
    }
}
