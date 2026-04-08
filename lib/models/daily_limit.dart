class DailyLimit {
  final String userId;
  final String date; // yyyy-MM-dd
  final int count;

  const DailyLimit({
    required this.userId,
    required this.date,
    required this.count,
  });

  factory DailyLimit.fromJson(Map<String, dynamic> json) {
    return DailyLimit(
      userId: json['user_id'] as String,
      date: json['date'] as String,
      count: json['count'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'date': date,
      'count': count,
    };
  }

  DailyLimit copyWith({String? userId, String? date, int? count}) {
    return DailyLimit(
      userId: userId ?? this.userId,
      date: date ?? this.date,
      count: count ?? this.count,
    );
  }
}
