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
  Future<FinanceCategory> ensureCategoryActiveByName(String name) async {
    final entry = await _db.ensureCategoryActiveByName(name);
    return _mapCategory(entry);
  }

  @override
  Future<void> moveActiveTransactionsToCategory({
    required String fromCategoryId,
    required String toCategoryId,
    required String toCategoryNameSnapshot,
  }) {
    return _db.moveActiveTransactionsToCategory(
      fromCategoryId: fromCategoryId,
      toCategoryId: toCategoryId,
      toCategoryNameSnapshot: toCategoryNameSnapshot,
    );
  }

  @override
  Future<void> deleteActiveTransactionsForCategory(String categoryId) =>
      _db.softDeleteActiveTransactionsForCategory(categoryId);

  @override
  Future<void> deleteCategory(String id) => _db.softDeleteCategory(id);

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _db.transaction(action);
}
