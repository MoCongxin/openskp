import 'package:openskp/src/core.dart';
import 'package:openskp/src/geometry.dart';
import 'package:openskp/src/scene.dart';
import 'package:openskp/openskp.dart';
import 'package:test/test.dart';

/// A component definition that (directly or transitively) instances itself
/// must throw, not recurse until the stack overflows. Real .skp files can't
/// easily be hand-crafted to exercise this, so these tests build a
/// synthetic RawParsed directly using the same GeometryBuilder shape
/// geometry.dart produces.

GeometryBuilderInstance _instance(int refIdx, [String name = 'child']) {
  return GeometryBuilderInstance()
    ..offset = 0
    ..refGuid = ''
    ..refIdx = refIdx
    ..name = name
    ..matrix = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1.0]
    ..materialId = null
    ..children = [];
}

void main() {
  test('self-referencing definition throws', () {
    final builder = GeometryBuilder()..instances.add(_instance(1));
    final rootBuilder = GeometryBuilder()..instances.add(_instance(1));

    final parsed = RawParsed()
      ..defsDict[1] = RawDefinition(guid: 'g1', name: 'self_ref', builder: builder)
      ..root = RawDefinition(guid: 'ROOT', name: 'ROOT_MODEL', builder: rootBuilder);

    expect(
      () => SceneBuilder.build(parsed),
      throwsA(isA<SkpParseException>().having(
        (e) => e.message,
        'message',
        contains('Recursive component definition'),
      )),
    );
  });

  test('indirect cycle throws', () {
    final builderA = GeometryBuilder()..instances.add(_instance(2));
    final builderB = GeometryBuilder()..instances.add(_instance(1));
    final rootBuilder = GeometryBuilder()..instances.add(_instance(1));

    final parsed = RawParsed()
      ..defsDict[1] = RawDefinition(guid: 'g1', name: 'a', builder: builderA)
      ..defsDict[2] = RawDefinition(guid: 'g2', name: 'b', builder: builderB)
      ..root = RawDefinition(guid: 'ROOT', name: 'ROOT_MODEL', builder: rootBuilder);

    expect(() => SceneBuilder.build(parsed), throwsA(isA<SkpParseException>()));
  });

  test('legitimate sibling reuse does not throw', () {
    final shared = GeometryBuilder();
    final rootBuilder = GeometryBuilder()
      ..instances.add(_instance(1, 'child_a'))
      ..instances.add(_instance(1, 'child_b'));

    final parsed = RawParsed()
      ..defsDict[1] = RawDefinition(guid: 'g1', name: 'shared', builder: shared)
      ..root = RawDefinition(guid: 'ROOT', name: 'ROOT_MODEL', builder: rootBuilder);

    final scene = SceneBuilder.build(parsed);
    expect(scene.sceneHierarchy.children.length, 2);
  });
}
