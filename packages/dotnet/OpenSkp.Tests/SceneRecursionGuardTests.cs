using System.Collections.Generic;
using System.Linq;
using Xunit;
using OpenSkp;

namespace OpenSkp.Tests
{
    /// <summary>
    /// A component definition that (directly or transitively) instances
    /// itself must throw, not recurse until the stack overflows. Real .skp
    /// files can't easily be hand-crafted to exercise this, so these tests
    /// build a synthetic Core.RawParsed directly using the same
    /// GeometryBuilder shape Geometry.cs produces.
    /// </summary>
    public class SceneRecursionGuardTests
    {
        private static GeometryBuilderInstance Instance(long refIdx, string name = "child") =>
            new GeometryBuilderInstance
            {
                Offset = 0,
                RefGuid = "",
                RefIdx = refIdx,
                Name = name,
                Matrix = new List<double> { 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1.0 },
                MaterialId = null,
                Children = new List<TlvNode>(),
            };

        [Fact]
        public void SelfReferencingDefinitionThrows()
        {
            var builder = new GeometryBuilder();
            builder.Instances.Add(Instance(1));
            var rootBuilder = new GeometryBuilder();
            rootBuilder.Instances.Add(Instance(1));

            var parsed = new Core.RawParsed
            {
                DefsDict = new Dictionary<long, Geometry.RawDefinition>
                {
                    [1] = new Geometry.RawDefinition { Guid = "g1", Name = "self_ref", Builder = builder },
                },
                Root = new Geometry.RawDefinition { Guid = "ROOT", Name = "ROOT_MODEL", Builder = rootBuilder },
            };

            var ex = Assert.Throws<SkpParseException>(() => SceneBuilder.Build(parsed));
            Assert.Contains("Recursive component definition", ex.Message);
        }

        [Fact]
        public void IndirectCycleThrows()
        {
            var builderA = new GeometryBuilder();
            builderA.Instances.Add(Instance(2));
            var builderB = new GeometryBuilder();
            builderB.Instances.Add(Instance(1));
            var rootBuilder = new GeometryBuilder();
            rootBuilder.Instances.Add(Instance(1));

            var parsed = new Core.RawParsed
            {
                DefsDict = new Dictionary<long, Geometry.RawDefinition>
                {
                    [1] = new Geometry.RawDefinition { Guid = "g1", Name = "a", Builder = builderA },
                    [2] = new Geometry.RawDefinition { Guid = "g2", Name = "b", Builder = builderB },
                },
                Root = new Geometry.RawDefinition { Guid = "ROOT", Name = "ROOT_MODEL", Builder = rootBuilder },
            };

            Assert.Throws<SkpParseException>(() => SceneBuilder.Build(parsed));
        }

        [Fact]
        public void LegitimateSiblingReuseDoesNotThrow()
        {
            var shared = new GeometryBuilder();
            var rootBuilder = new GeometryBuilder();
            rootBuilder.Instances.Add(Instance(1, "child_a"));
            rootBuilder.Instances.Add(Instance(1, "child_b"));

            var parsed = new Core.RawParsed
            {
                DefsDict = new Dictionary<long, Geometry.RawDefinition>
                {
                    [1] = new Geometry.RawDefinition { Guid = "g1", Name = "shared", Builder = shared },
                },
                Root = new Geometry.RawDefinition { Guid = "ROOT", Name = "ROOT_MODEL", Builder = rootBuilder },
            };

            var scene = SceneBuilder.Build(parsed);
            Assert.Equal(2, scene.SceneHierarchy.Children.Count);
        }
    }
}
