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
    return Ingredient(
      name: json['name'] as String,
      quantity: json['quantity'] as String,
      prepMethod: json['prep_method'] as String?,
      aliases: (json['aliases'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
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
