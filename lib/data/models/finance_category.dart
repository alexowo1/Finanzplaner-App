class FinanceCategory {
  const FinanceCategory({
    required this.id,
    required this.name,
    required this.updatedAtMs,
    required this.deletedAtMs,
  });

  final String id;
  final String name;
  final int updatedAtMs;
  final int? deletedAtMs;

  Map<String, dynamic> toJson() {
    return {
      'entityId': id,
      'name': name,
      'clientUpdatedAtMs': updatedAtMs,
      'deletedAtMs': deletedAtMs ?? 0,
    };
  }

  factory FinanceCategory.fromJson(Map<String, dynamic> json) {
    final deletedAtMs = (json['deletedAtMs'] as num?)?.toInt() ?? 0;

    return FinanceCategory(
      id: json['entityId'] as String,
      name: json['name'] as String,
      updatedAtMs: (json['clientUpdatedAtMs'] as num).toInt(),
      deletedAtMs: deletedAtMs == 0 ? null : deletedAtMs,
    );
  }
}
