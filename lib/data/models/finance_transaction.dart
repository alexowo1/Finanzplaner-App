class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.date,
    required this.category,
    required this.categoryId,
    required this.note,
    required this.updatedAtMs,
    required this.deletedAtMs,
  });

  final String id;
  final String type;
  final int amountCents;
  final String date;

  /// Gespeicherter Kategoriename als Snapshot.
  final String category;

  /// Eindeutige ID der Kategorie.
  final String? categoryId;

  final String? note;
  final int updatedAtMs;
  final int? deletedAtMs;

  Map<String, dynamic> toJson() {
    return {
      'entityId': id,
      'type': type,
      'amountCents': amountCents,
      'bookingDate': date,
      'categoryEntityId': categoryId ?? '',
      'categoryNameSnapshot': category,
      'note': note ?? '',
      'clientUpdatedAtMs': updatedAtMs,
      'deletedAtMs': deletedAtMs ?? 0,
    };
  }

  factory FinanceTransaction.fromJson(Map<String, dynamic> json) {
    final categoryId = json['categoryEntityId'] as String? ?? '';
    final note = json['note'] as String? ?? '';
    final deletedAtMs = (json['deletedAtMs'] as num?)?.toInt() ?? 0;

    return FinanceTransaction(
      id: json['entityId'] as String,
      type: json['type'] as String,
      amountCents: (json['amountCents'] as num).toInt(),
      date: json['bookingDate'] as String,
      category: json['categoryNameSnapshot'] as String,
      categoryId: categoryId.isEmpty ? null : categoryId,
      note: note.isEmpty ? null : note,
      updatedAtMs: (json['clientUpdatedAtMs'] as num).toInt(),
      deletedAtMs: deletedAtMs == 0 ? null : deletedAtMs,
    );
  }
}
