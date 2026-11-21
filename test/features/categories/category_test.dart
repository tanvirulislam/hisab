import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/features/categories/domain/category.dart';

Category _cat(String id, {String? parentId, String? systemKey, String name = 'X'}) => Category(
  id: id,
  parentId: parentId,
  type: CategoryType.expense,
  systemKey: systemKey,
  name: name,
  iconKey: 'label',
  color: 0,
  isDefault: systemKey != null,
  isActive: true,
  sortOrder: 0,
);

void main() {
  test('seeded categories are translated, custom ones keep their name', () {
    final fish = _cat('1', systemKey: 'grocery.fish', name: 'Fish');
    expect(fish.displayName('bn'), 'মাছ');
    expect(fish.displayName('en'), 'Fish');
    final custom = _cat('2', name: 'Gym');
    expect(custom.displayName('bn'), 'Gym');
  });

  test('fallback categories are protected', () {
    expect(_cat('1', systemKey: 'others').isProtected, isTrue);
    expect(_cat('2', systemKey: 'income.other').isProtected, isTrue);
    expect(_cat('3', systemKey: 'grocery').isProtected, isFalse);
    expect(_cat('4').isProtected, isFalse);
  });

  test('buildTree keeps order, nests children and drops orphans', () {
    final tree = CategoryNode.buildTree([
      _cat('a'),
      _cat('a1', parentId: 'a'),
      _cat('b'),
      _cat('a2', parentId: 'a'),
      _cat('orphan', parentId: 'gone'),
    ]);
    expect(tree.map((n) => n.category.id), ['a', 'b']);
    expect(tree.first.children.map((c) => c.id), ['a1', 'a2']);
    expect(tree.last.children, isEmpty);
  });
}
