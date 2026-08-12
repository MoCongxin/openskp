using System.Collections.Generic;
using Xunit;
using OpenSkp;

namespace OpenSkp.Tests
{
    public class ObjExportTests
    {
        [Fact]
        public void SerializesSceneToObjAndMtlTextFormat()
        {
            var prim = new GlbPrimitive
            {
                GeomName = "Cube",
                MaterialIndex = 0,
                Positions = new float[] { 0, 0, 0, 1, 0, 0, 0, 1, 0 },
                Normals = new float[] { 0, 0, 1, 0, 0, 1, 0, 0, 1 },
                Uvs = new float[] { 0, 0, 1, 0, 0, 1 },
                Indices = new uint[] { 0, 1, 2 }
            };

            var scene = new Scene
            {
                SceneHierarchy = new InstanceNode { Name = "Root", DefinitionName = "RootDef", Layer = "Layer0" },
                MeshIndex = new Dictionary<string, MeshMetadata>(),
                GlbPrimitives = new List<GlbPrimitive> { prim },
                GltfMaterials = new List<object>
                {
                    new Dictionary<string, object>
                    {
                        { "name", "Yellow_Material" },
                        { "pbrMetallicRoughness", new Dictionary<string, object> { { "baseColorFactor", new List<float> { 1.0f, 1.0f, 0.0f, 1.0f } } } }
                    }
                }
            };

            string objText = ObjExport.ToObj(scene, "scene.mtl");
            Assert.Contains("# OpenSKP OBJ Export", objText);
            Assert.Contains("mtllib scene.mtl", objText);
            Assert.Contains("o Cube", objText);
            Assert.Contains("v 0.000000 0.000000 0.000000", objText);
            Assert.Contains("vt 0.000000 0.000000", objText);
            Assert.Contains("vn 0.000000 0.000000 1.000000", objText);
            Assert.Contains("usemtl Yellow_Material", objText);
            Assert.Contains("f 1/1/1 2/2/2 3/3/3", objText);

            string mtlText = ObjExport.ToMtl(scene);
            Assert.Contains("# OpenSKP MTL Material Library Export", mtlText);
            Assert.Contains("newmtl Yellow_Material", mtlText);
            Assert.Contains("Kd 1.000000 1.000000 0.000000", mtlText);
        }
    }
}
