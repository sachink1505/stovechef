enum FoodPreference { vegetarian, nonVegetarian, everything }

extension FoodPreferenceX on FoodPreference {
  String toJson() {
    switch (this) {
      case FoodPreference.vegetarian:
        return 'vegetarian';
      case FoodPreference.nonVegetarian:
        return 'non_vegetarian';
      case FoodPreference.everything:
        return 'everything';
    }
  }

  static FoodPreference fromJson(String value) {
    switch (value) {
      case 'vegetarian':
        return FoodPreference.vegetarian;
      case 'non_vegetarian':
        return FoodPreference.nonVegetarian;
      case 'everything':
        return FoodPreference.everything;
      default:
        return FoodPreference.everything;
    }
  }
}

class UserProfile {
  final String id;
  final String email;
  final String name;
  final FoodPreference foodPreference;
  final String? phone;
  final String? avatarUrl;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.name,
    required this.foodPreference,
    this.phone,
    this.avatarUrl,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      foodPreference: FoodPreferenceX.fromJson(json['food_preference'] as String),
      phone: json['phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'food_preference': foodPreference.toJson(),
      if (phone != null) 'phone': phone,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? id,
    String? email,
    String? name,
    FoodPreference? foodPreference,
    String? phone,
    String? avatarUrl,
    DateTime? createdAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      foodPreference: foodPreference ?? this.foodPreference,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
