class StepIngredient {
  final String name;
  final String quantity;
  final String? prepMethod;

  const StepIngredient({
    required this.name,
    required this.quantity,
    this.prepMethod,
  });

  factory StepIngredient.fromJson(Map<String, dynamic> json) {
    return StepIngredient(
      name: json['name'] as String,
      quantity: json['quantity'] as String,
      prepMethod: json['prep_method'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      if (prepMethod != null) 'prep_method': prepMethod,
    };
  }
}
