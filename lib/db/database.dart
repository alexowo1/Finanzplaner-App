import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';
part 'database.g.dart';

enum CreateCategoryResult { created, restored, alreadyExists, invalid }

@DataClassName('CategoryEntry')
class Categories extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text().unique()(); // keine Duplikate
  IntColumn get updatedAtMs => integer()();
  IntColumn get deletedAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TxEntry')
class Transactions extends Table {
  TextColumn get id => text()(); // UUID string (Primary Key)
  // Wir speichern absichtlich als Text ("income"/"expense"):
  // - leichter zu debuggen
  // - sehr sync-freundlich (plattformneutral)
  TextColumn get type => text()(); // "income" | "expense"

  IntColumn get amountCents => integer()(); // z.B. 1234 = 12,34 €
  TextColumn get date => text()(); // "YYYY-MM-DD" (keine Zeitzonen-Probleme)
  TextColumn get category => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get note => text().nullable()();

  // Für Sync/Conflict-Resolution später:
  IntColumn get updatedAtMs => integer()(); // Unix millis
  IntColumn get deletedAtMs => integer().nullable()(); // Tombstone

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Transactions, Categories])
class AppDatabase extends _$AppDatabase {
  AppDatabase():
        super(driftDatabase(name: 'haushaltsplaner_db',
      // native: DriftNativeOptions(shareAcrossIsolates: true), // optional
    ),
  );

  @override
  int get schemaVersion => 2;

  /// Nur "aktive" Einträge (nicht gelöscht), neueste zuerst.
  Stream<List<TxEntry>> watchActiveTransactions() {
    final q = select(transactions)
      ..where((t) => t.deletedAtMs.isNull())
      ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.updatedAtMs, mode: OrderingMode.desc),
      ]);
    return q.watch();
  }

  Future<CategoryEntry?> getActiveCategoryByName(String name) {
    final n = name.trim();
    return (select(categories)
      ..where((c) => c.deletedAtMs.isNull() & c.name.equals(n)))
        .getSingleOrNull();
  }

  Future<void> upsertTransaction({
    required String id,
    required String type, // "income"/"expense"
    required int amountCents,
    required String date, // "YYYY-MM-DD"
    required String category,
    String? categoryId,
    String? note,
    required int updatedAtMs,
    int? deletedAtMs,
  }) async {
    await into(transactions).insertOnConflictUpdate(
      TransactionsCompanion(
        id: Value(id),
        type: Value(type),
        amountCents: Value(amountCents),
        date: Value(date),
        category: Value(category),
        categoryId: Value(categoryId),
        note: Value(note),
        updatedAtMs: Value(updatedAtMs),
        deletedAtMs: Value(deletedAtMs),
      ),
    );
  }

  Future<void> upsertCategory({
    required String id,
    required String name,
    required int updatedAtMs,
    int? deletedAtMs,
  }) async {
    await into(categories).insertOnConflictUpdate(
      CategoriesCompanion(
        id: Value(id),
        name: Value(name),
        updatedAtMs: Value(updatedAtMs),
        deletedAtMs: Value(deletedAtMs),
      ),
    );
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deletedAtMs: Value(now),
        updatedAtMs: Value(now),
      ),
    );
  }

  Stream<List<TxEntry>> watchTransactionsForMonth(String yyyyMm) {
    // yyyyMm z.B. "2025-12"
    final q = select(transactions)
      ..where((t) => t.deletedAtMs.isNull() & t.date.like('$yyyyMm-%'))
      ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.updatedAtMs, mode: OrderingMode.desc),
      ]);
    return q.watch();
  }

  Stream<List<TxEntry>> watchActiveTransactionsInRange({
    String? startIsoInclusive, // z.B. "2025-01-01"
    String? endIsoExclusive,   // z.B. "2025-04-01" (erster Tag des Folgemonats)
    String? categoryId,
  }) {
    final q = select(transactions)
      ..where((t) {
        Expression<bool> expr = t.deletedAtMs.isNull();

        if (startIsoInclusive != null) {
          expr = expr & t.date.isBiggerOrEqualValue(startIsoInclusive);
        }
        if (endIsoExclusive != null) {
          expr = expr & t.date.isSmallerThanValue(endIsoExclusive);
        }
        if (categoryId != null) {
          expr = expr & t.categoryId.equals(categoryId);
        }
        return expr;
      })
      ..orderBy([
            (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.updatedAtMs, mode: OrderingMode.desc),
      ]);

    return q.watch();
  }

  static const _uuid = Uuid();

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _ensureDefaultCategory();
    },
    onUpgrade: (m, from, to) async {
      if (from == 1) {
        await m.createTable(categories);
        await m.addColumn(transactions, transactions.categoryId);

        // Kategorien aus bestehenden Transaktionen übernehmen
        final now = DateTime.now().millisecondsSinceEpoch;
        final rows = await customSelect('SELECT DISTINCT category FROM transactions').get();

        for (final r in rows) {
          final name = (r.data['category'] as String?)?.trim();
          if (name == null || name.isEmpty) continue;

          final id = _uuid.v4();
          await into(categories).insert(
            CategoriesCompanion(
              id: Value(id),
              name: Value(name),
              updatedAtMs: Value(now),
              deletedAtMs: const Value(null),
            ),
            mode: InsertMode.insertOrIgnore,
          );

          // Kategorie-ID in Transaktionen setzen
          await customStatement(
            'UPDATE transactions SET category_id = ? WHERE category = ? AND category_id IS NULL',
            [id, name],
          );
        }

        await _ensureDefaultCategory();
      }
    },
  );

  Future<void> _ensureDefaultCategory() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = await (select(categories)
      ..where((c) => c.name.equals('Allgemein') & c.deletedAtMs.isNull()))
        .getSingleOrNull();

    if (existing == null) {
      await into(categories).insert(
        CategoriesCompanion(
          id: Value(_uuid.v4()),
          name: const Value('Allgemein'),
          updatedAtMs: Value(now),
          deletedAtMs: const Value(null),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  Stream<List<CategoryEntry>> watchActiveCategories() {
    final q = select(categories)
      ..where((c) => c.deletedAtMs.isNull())
      ..orderBy([(c) => OrderingTerm(expression: c.name)]);
    return q.watch();
  }

  Future<CategoryEntry?> getCategoryById(String id) {
    return (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<CreateCategoryResult> createCategory(String name) async {
  final n = name.trim();
  if (n.isEmpty) return CreateCategoryResult.invalid;

  final now = DateTime.now().millisecondsSinceEpoch;

  // Wichtig: auch gelöschte Kategorien prüfen (kein deletedAt Filter)
  final existing = await (select(categories)..where((c) => c.name.equals(n))).getSingleOrNull();

  if (existing != null) {
  if (existing.deletedAtMs != null) {
  // Restore (und gleiche ID behalten)
  await (update(categories)..where((c) => c.id.equals(existing.id))).write(
  CategoriesCompanion(
  deletedAtMs: const Value(null),
  updatedAtMs: Value(now),
  ),
  );
  return CreateCategoryResult.restored;
  }
  return CreateCategoryResult.alreadyExists;
  }

  // Neu erstellen (kein insertOrIgnore -> wenn doch was schiefgeht, wird Fehler ausgegeben)
  await into(categories).insert(
  CategoriesCompanion(
  id: Value(_uuid.v4()),
  name: Value(n),
  updatedAtMs: Value(now),
  deletedAtMs: const Value(null),
  ),
  );

  return CreateCategoryResult.created;
  }

  Future<void> renameCategory(String id, String newName) async {
    final n = newName.trim();
    if (n.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    await (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(n),
        updatedAtMs: Value(now),
      ),
    );
  }

  Future<void> softDeleteCategory(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        deletedAtMs: Value(now),
        updatedAtMs: Value(now),
      ),
    );
  }

  // 1) Wie viele (aktive) Buchungen hängen an einer Kategorie?
  Future<int> countActiveTransactionsForCategory(String categoryId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM transactions WHERE deleted_at_ms IS NULL AND category_id = ?',
      variables: [Variable<String>(categoryId)],
    ).getSingle();

    return (row.data['c'] as int?) ?? 0;
  }

// 2) Kategorie anhand Name holen (egal ob deleted oder nicht)
  Future<CategoryEntry?> getCategoryByNameAny(String name) {
    final n = name.trim();
    return (select(categories)..where((c) => c.name.equals(n))).getSingleOrNull();
  }

// 3) Kategorie sicherstellen: existiert -> ggf. restore, sonst neu anlegen
  Future<CategoryEntry> ensureCategoryActiveByName(String name) async {
    final n = name.trim();
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = await getCategoryByNameAny(n);
    if (existing != null) {
      if (existing.deletedAtMs != null) {
        await (update(categories)..where((c) => c.id.equals(existing.id))).write(
          CategoriesCompanion(
            deletedAtMs: const Value(null),
            updatedAtMs: Value(now),
          ),
        );
        return (await (select(categories)..where((c) => c.id.equals(existing.id))).getSingle());
      }
      return existing;
    }

    final id = _uuid.v4();
    await into(categories).insert(
      CategoriesCompanion(
        id: Value(id),
        name: Value(n),
        updatedAtMs: Value(now),
        deletedAtMs: const Value(null),
      ),
    );

    return (await (select(categories)..where((c) => c.id.equals(id))).getSingle());
  }

// 4) Buchungen in andere Kategorie verschieben (sync-tauglich: updatedAtMs setzen)
  Future<void> moveActiveTransactionsToCategory({
    required String fromCategoryId,
    required String toCategoryId,
    required String toCategoryNameSnapshot,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await (update(transactions)
      ..where((t) => t.deletedAtMs.isNull() & t.categoryId.equals(fromCategoryId)))
        .write(
      TransactionsCompanion(
        categoryId: Value(toCategoryId),
        category: Value(toCategoryNameSnapshot), // Snapshot wichtig
        updatedAtMs: Value(now),
      ),
    );
  }

// 5) Buchungen dieser Kategorie löschen (soft-delete, sync-tauglich)
  Future<void> softDeleteActiveTransactionsForCategory(String categoryId) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await (update(transactions)
      ..where((t) => t.deletedAtMs.isNull() & t.categoryId.equals(categoryId)))
        .write(
      TransactionsCompanion(
        deletedAtMs: Value(now),
        updatedAtMs: Value(now),
      ),
    );
  }

}
