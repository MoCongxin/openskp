using System;
using System.IO;
using System.Linq;
using Xunit;
using OpenSkp;

namespace OpenSkp.Tests
{
    /// <summary>
    /// Real-file regression test for JsonExport.ToDict() - openskp's
    /// canonical JSON export schema, shared with the Python (to_dict) and
    /// TypeScript (toJSON) ports. Cross-checked directly against both on
    /// this exact fixture.
    /// </summary>
    public class JsonExportTests
    {
        private static string FixturePath(string name) =>
            Path.Combine(AppContext.BaseDirectory, "fixtures", name);

        [Fact]
        public void MatchesPythonAndTypeScriptGroundTruth()
        {
            var model = SkpFile.Open(FixturePath("capilla_quiroz_v17.skp"));
            var d = JsonExport.ToDict(model);

            Assert.Equal("1.0", d["format_version"]);
            Assert.Equal("{17.0.18899}", d["sketchup_version"]);
            Assert.Equal(2, d["total_definitions"]);
            Assert.Equal(1, d["total_layers"]);
            Assert.Equal(0, d["total_meshes"]);

            var root = (System.Collections.Generic.Dictionary<string, object?>)d["root"]!;
            Assert.Equal(251, root["vertex_count"]);
            Assert.Equal(390, root["edge_count"]);
            Assert.Equal(146, root["face_count"]);
            var rootInstances = (System.Collections.Generic.List<object>)root["instances"]!;
            Assert.Equal(3, rootInstances.Count);
            var firstInst = (System.Collections.Generic.Dictionary<string, object?>)rootInstances[0];
            Assert.Equal(new[] { "name", "ref_idx", "guid", "matrix" }.OrderBy(x => x), firstInst.Keys.OrderBy(x => x));

            var definitions = (System.Collections.Generic.Dictionary<string, object?>)d["definitions"]!;
            var puerta = definitions.Values
                .Cast<System.Collections.Generic.Dictionary<string, object?>>()
                .First(v => (string)v["name"]! == "puerta");
            Assert.Equal(40L, puerta["id"]);
            Assert.Equal(64, puerta["vertex_count"]);
            Assert.Equal(95, puerta["edge_count"]);
            Assert.Equal(24, puerta["face_count"]);
            Assert.Equal(95, ((System.Collections.Generic.List<object>)puerta["edges"]!).Count);
            Assert.Equal(24, ((System.Collections.Generic.List<object>)puerta["faces"]!).Count);

            var layers = (System.Collections.Generic.List<object>)d["layers"]!;
            var firstLayer = (System.Collections.Generic.Dictionary<string, object?>)layers[0];
            var layerColor = (System.Collections.Generic.Dictionary<string, object?>)firstLayer["color"]!;
            Assert.Equal(255, layerColor["r"]);
            Assert.Equal(84, layerColor["g"]);
            Assert.Equal(84, layerColor["b"]);

            Assert.Empty((System.Collections.Generic.Dictionary<string, object?>)d["mesh_index"]!);
            Assert.Null(d["scene_hierarchy"]);
        }

        [Fact]
        public void IncludesSceneHierarchyAndMeshIndexWhenSceneIsPassed()
        {
            var model = SkpFile.Open(FixturePath("capilla_quiroz_v17.skp"));
            var scene = SkpFile.BuildScene(FixturePath("capilla_quiroz_v17.skp"));
            var d = JsonExport.ToDict(model, scene);

            Assert.Equal(scene.MeshIndex.Count, d["total_meshes"]);
            var hierarchy = (System.Collections.Generic.Dictionary<string, object?>)d["scene_hierarchy"]!;
            Assert.Equal("ROOT", hierarchy["name"]);
            Assert.True(hierarchy.ContainsKey("definition_name"));
            Assert.True(hierarchy.ContainsKey("position_mm"));

            var meshIndex = (System.Collections.Generic.Dictionary<string, object?>)d["mesh_index"]!;
            var firstMesh = (System.Collections.Generic.Dictionary<string, object?>)meshIndex.Values.First()!;
            Assert.True(firstMesh.ContainsKey("definition_name"));
            Assert.True(firstMesh.ContainsKey("position_mm"));
        }

        [Fact]
        public void ProducesJsonSerializableOutput()
        {
            var model = SkpFile.Open(FixturePath("capilla_quiroz_v17.skp"));
            var scene = SkpFile.BuildScene(FixturePath("capilla_quiroz_v17.skp"));
            var d = JsonExport.ToDict(model, scene);
            var json = MiniJson.Serialize(d);
            Assert.False(string.IsNullOrEmpty(json));
        }
    }
}
