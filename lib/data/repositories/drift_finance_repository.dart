import '../../db/database.dart';
import '../models/finance_category.dart';
import '../models/finance_transaction.dart';
import 'finance_repository.dart';

class DriftFinanceRepository implements FinanceRepository {
  DriftFinanceRepository(this._db);

  final AppDatabase _db;

  FinanceTransaction _mapTransaction(TxEntry entry) => FinanceTransaction(
    id: entry.id,
    type: entry.type,
    amountCents: entry.amountCents,
    date: entry.date,
    category: entry.category,
    categoryId: entry.categoryId,
    note: entry.note,
    updatedAtMs: entry.updatedAtMs,
    deletedAtMs: entry.deletedAtMs,
  );

  FinanceCategory _mapCategory(CategoryEntry entry) => FinanceCategory(
    id: entry.id,
    name: entry.name,
    updatedAtMs: entry.updatedAtMs,
    deletedAtMs: entry.deletedAtMs,
  );

  @override
  Stream<List<FinanceTransaction>> watchActiveTransactionsInRange({
    String? startIsoInclusive,
    String? endIsoExclusive,
    String? categoryId,
  }) {
    return _db
        .watchActiveTransactionsInRange(
          startIsoInclusive: startIsoInclusive,
          endIsoExclusive: endIsoExclusive,
          categoryId: categoryId,
        )
        .map((rows) => rows.map(_mapTransaction).toList(growable: false));
  }

  @override
  Stream<List<FinanceCategory>> watchActiveCategories() {
    return _db.watchActiveCategories().map(
      (rows) => rows.map(_mapCategory).toList(growable: false),
    );
  }

  @override
  Future<CategoryCreationResult> createCategory(String name) async {
    final result = await _db.createCategory(name);
    return switch (result) {
      CreateCategoryResult.created => CategoryCreationResult.created,
      CreateCategoryResult.restored => CategoryCreationResult.restored,
      CreateCategoryResult.alreadyExists =>
        CategoryCreationResult.alreadyExists,
      CreateCategoryResult.invalid => CategoryCreationResult.invalid,
    };
  }

  @override
  Future<FinanceCategory?> getActiveCategoryByName(String name) async {
    final entry = await _db.getActiveCategoryByName(name);
    return entry == null ? null : _mapCategory(entry);
  }

  @override
  Future<FinanceCategory?> getCategoryById(String id) async {
    final entry = await _db.getCategoryById(id);
    return entry == null ? null : _mapCategory(entry);
  }

  @override
  Future<void> saveTransaction({
    required String id,
    required String type,
    required int amountCents,
    required String date,
    required String category,
    String? categoryId,
    String? note,
    required int updatedAtMs,
    int? deletedAtMs,
  }) {
    return _db.upsertTransaction(
      id: id,
      type: type,
      amountCents: amountCents,
      date: date,
      category: category,
      categoryId: categoryId,
      note: note,
      updatedAtMs: updatedAtMs,
      deletedAtMs: deletedAtMs,
    );
  }

  @override
  Future<void> deleteTransaction(String id) => _db.softDelete(id);

  @override
  Future<void> renameCategory(String id, String newName) =>
      _db.renameCategory(id, newName);

  @override
  Future<int> countActiveTransactionsForCategory(String categoryId) =>
      _db.countActiveTransactionsForCategory(categoryId);

  @override
  Future<void> deleteCategoryWithPolicy({
    required String categoryId,
    required CategoryDeletionPolicy policy,
    String? targetCategoryId,
  }) {
    return _db.transaction(() async {
      final transactionCount = await _db.countActiveTransactionsForCategory(
        categoryId,
      );

      if (transactionCount > 0) {
        switch (policy) {
          case CategoryDeletionPolicy.moveTransactions:
            final CategoryEntry target;

            if (targetCategoryId == null) {
              target = await _db.ensureCategoryActiveByName('Sonstige');
            } else {
              final existingTarget = await _db.getCategoryById(
                targetCategoryId,
              );

              if (existingTarget == null ||
                  existingTarget.deletedAtMs != null) {
                throw StateError('Die Zielkategorie ist nicht verfügbar.');
              }

              if (existingTarget.id == categoryId) {
                throw ArgumentError(
                  'Eine Kategorie kann nicht in sich selbst verschoben werden.',
                );
              }

              target = existingTarget;
            }

            await _db.moveActiveTransactionsToCategory(
              fromCategoryId: categoryId,
              toCategoryId: target.id,
              toCategoryNameSnapshot: target.name,
            );
            break;

          case CategoryDeletionPolicy.archiveTransactions:
            final archive = await _db.ensureCategoryActiveByName('Archiv');

            await _db.moveActiveTransactionsToCategory(
              fromCategoryId: categoryId,
              toCategoryId: archive.id,
              toCategoryNameSnapshot: archive.name,
            );
            break;

          case CategoryDeletionPolicy.deleteTransactions:
            await _db.softDeleteActiveTransactionsForCategory(categoryId);
            break;
        }
      }

      await _db.softDeleteCategory(categoryId);
    });
  }
}
