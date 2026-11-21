import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/core/database/app_database.dart';
import 'package:hisab/core/errors/app_exception.dart';
import 'package:hisab/core/utils/money.dart';
import 'package:hisab/features/categories/data/drift_category_repository.dart';
import 'package:hisab/features/categories/domain/category.dart';
import 'package:hisab/features/categories/domain/category_repository.dart';
import 'package:hisab/features/transactions/data/drift_transaction_repository.dart';
import 'package:hisab/features/transactions/domain/drafts.dart';
import 'package:hisab/features/transactions/domain/ledger_entry.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late DriftCategoryRepository repo;
  late DriftTransactionRepository txns;
  late String personal, family, pCash;

  setUp(() async {
    db = await openTestDb();
    repo = DriftCategoryRepository(db);
    txns = DriftTransactionRepository(db);
    personal = (await workspaceOfType(db, 'personal')).id;
    family = (await workspaceOfType(db, 'family')).id;
    pCash = (await firstAccountOf(db, personal)).id;
  });
  tearDown(() => db.close());

  Future<String> spend(String categoryId, {String? sub}) => txns.createEntry(EntryDraft(
      type: EntryType.expense, workspaceId: personal, accountId: pCash,
      amount: const Money(100), categoryId: categoryId, subcategoryId: sub, occurredAt: testNow));

  CategoryDraft draft(String name, {String? parentId, String? workspaceId}) => CategoryDraft(
      name: name, type: CategoryType.expense, iconKey: 'label', color: 0xFF112233,
      parentId: parentId, workspaceId: workspaceId);

  test('creates a top-level and a subcategory that inherits type, workspace and color', () async {
    final gym = await repo.createCategory(draft('Gym', workspaceId: personal));
    final fee = await repo.createCategory(CategoryDraft(
        name: 'Monthly fee', type: CategoryType.income, iconKey: 'label', color: 0, parentId: gym));
    final row = (await db.categoriesDao.findById(fee))!;
    expect(row.type, 'expense');
    expect(row.workspaceId, personal);
    expect(row.color, 0xFF112233);
  });

  test('rejects empty names, duplicates (incl. translated names) and nested subcategories', () async {
    await expectLater(repo.createCategory(draft('  ')),
        throwsA(isA<ValidationException>().having((e) => e.code, 'code', CategoryError.nameInvalid)));
    for (final dup in ['transportation', 'যাতায়াত']) {
      await expectLater(repo.createCategory(draft(dup)),
          throwsA(isA<ValidationException>().having((e) => e.code, 'code', CategoryError.nameDuplicate)),
          reason: dup);
    }
    final lunch = await categoryByKey(db, 'food.lunch');
    await expectLater(repo.createCategory(draft('Late lunch', parentId: lunch.id)),
        throwsA(isA<ValidationException>().having((e) => e.code, 'code', CategoryError.parentInvalid)));
    // Same name in different workspaces is fine.
    await repo.createCategory(draft('Kids', workspaceId: personal));
    await repo.createCategory(draft('Kids', workspaceId: family));
  });

  test('renaming a seeded category shows the new name in both languages', () async {
    final fish = await categoryByKey(db, 'grocery.fish');
    await repo.updateCategory(fish.id, name: 'Hilsa', iconKey: fish.icon, color: fish.color);
    final c = DriftCategoryRepository.toDomain((await db.categoriesDao.findById(fish.id))!);
    expect(c.displayName('bn'), 'Hilsa');
    expect(c.displayName('en'), 'Hilsa');
  });

  test('protected fallback categories cannot be archived or deleted', () async {
    final others = await categoryByKey(db, 'others');
    await expectLater(repo.setArchived(others.id, archived: true), throwsA(isA<ValidationException>()));
    await expectLater(repo.deleteCategory(others.id), throwsA(isA<ValidationException>()));
  });

  test('archiving a parent archives its subcategories and hides them from entry', () async {
    final grocery = await categoryByKey(db, 'grocery');
    await repo.setArchived(grocery.id, archived: true);
    final fish = await categoryByKey(db, 'grocery.fish');
    expect(fish.isActive, isFalse);
    final tree = await repo.watchCategoryTree([personal], CategoryType.expense).first;
    expect(tree.map((n) => n.category.id), isNot(contains(grocery.id)));
    final managed = await repo.watchManagedTree([personal], CategoryType.expense).first;
    expect(managed.map((n) => n.category.id), contains(grocery.id));

    await expectLater(repo.setArchived(fish.id, archived: false),
        throwsA(isA<ValidationException>().having((e) => e.code, 'code', CategoryError.parentArchived)));
    await repo.setArchived(grocery.id, archived: false);
    await repo.setArchived(fish.id, archived: false);
  });

  test('a used category cannot be deleted; an unused one can (§7.2)', () async {
    final food = await categoryByKey(db, 'food');
    await spend(food.id);
    expect(await repo.usageCount(food.id), 1);
    await expectLater(repo.deleteCategory(food.id),
        throwsA(isA<ConflictException>().having((e) => e.code, 'code', CategoryError.inUse)));

    final gift = await categoryByKey(db, 'gifts');
    await repo.deleteCategory(gift.id);
    expect((await db.categoriesDao.findById(gift.id))!.deletedAt, isNotNull);
  });

  test('usage of a subcategory blocks deleting its parent', () async {
    final grocery = await categoryByKey(db, 'grocery');
    final fish = await categoryByKey(db, 'grocery.fish');
    await spend(grocery.id, sub: fish.id);
    expect(await repo.usageCount(grocery.id), 1);
    await expectLater(repo.deleteCategory(grocery.id), throwsA(isA<ConflictException>()));
  });

  test('reassign moves transactions and archives the old category', () async {
    final food = await categoryByKey(db, 'food');
    final lunch = await categoryByKey(db, 'food.lunch');
    final others = await categoryByKey(db, 'others');
    final id = await spend(food.id, sub: lunch.id);

    await repo.reassignAndArchive(food.id, toId: others.id);
    final row = (await db.transactionsDao.findById(id))!;
    expect(row.categoryId, others.id);
    expect(row.subcategoryId, isNull);
    expect((await categoryByKey(db, 'food')).isActive, isFalse);
    expect((await categoryByKey(db, 'food.lunch')).isActive, isFalse);
  });

  test('reassigning a subcategory keeps the parent on its transactions', () async {
    final grocery = await categoryByKey(db, 'grocery');
    final fish = await categoryByKey(db, 'grocery.fish');
    final id = await spend(grocery.id, sub: fish.id);
    await repo.reassignAndArchive(fish.id);
    final row = (await db.transactionsDao.findById(id))!;
    expect(row.categoryId, grocery.id);
    expect(row.subcategoryId, isNull);
  });

  test('reassign rejects targets of another type or a narrower workspace (rule 11)', () async {
    final food = await categoryByKey(db, 'food');
    final salary = await categoryByKey(db, 'income.salary');
    final famOnly = await repo.createCategory(draft('Kids', workspaceId: family));
    for (final to in [salary.id, famOnly, food.id]) {
      await expectLater(repo.reassignAndArchive(food.id, toId: to),
          throwsA(isA<ValidationException>()), reason: to);
    }
  });
}
