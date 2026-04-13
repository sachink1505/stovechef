class Ingredient {
  final String name;
  final String quantity;
  final String? prepMethod;
  final List<String> aliases;

  const Ingredient({
    required this.name,
    required this.quantity,
    this.prepMethod,
    this.aliases = const [],
  });

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    final raw = json['aliases'];
    final List<String> aliases;
    if (raw is Map) {
      aliases = raw.values.whereType<String>().toList();
    } else if (raw is List) {
      aliases = raw.whereType<String>().toList();
    } else {
      aliases = const [];
    }
    return Ingredient(
      name: json['name'] as String,
      quantity: json['quantity'] as String,
      prepMethod: json['prep_method'] as String?,
      aliases: aliases,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      if (prepMethod != null) 'prep_method': prepMethod,
      'aliases': aliases,
    };
  }
}
