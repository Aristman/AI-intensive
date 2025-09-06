import 'dart:convert';

class ProfileEntry {
  final String title;
  final String description;

  const ProfileEntry({required this.title, required this.description});

  ProfileEntry copyWith({String? title, String? description}) => ProfileEntry(
        title: title ?? this.title,
        description: description ?? this.description,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
      };

  factory ProfileEntry.fromJson(Map<String, dynamic> json) => ProfileEntry(
        title: (json['title'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
      );
}

class UserProfile {
  final String name;
  final String role;
  final List<ProfileEntry> preferences;
  final List<ProfileEntry> exclusions;

  const UserProfile({
    required this.name,
    required this.role,
    this.preferences = const [],
    this.exclusions = const [],
  });

  UserProfile copyWith({
    String? name,
    String? role,
    List<ProfileEntry>? preferences,
    List<ProfileEntry>? exclusions,
  }) => UserProfile(
        name: name ?? this.name,
        role: role ?? this.role,
        preferences: preferences ?? this.preferences,
        exclusions: exclusions ?? this.exclusions,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'role': role,
        'preferences': preferences.map((e) => e.toJson()).toList(),
        'exclusions': exclusions.map((e) => e.toJson()).toList(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: (json['name'] ?? '').toString(),
        role: (json['role'] ?? 'user').toString(),
        preferences: ((json['preferences'] as List?) ?? const [])
            .whereType<dynamic>()
            .map((e) => ProfileEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        exclusions: ((json['exclusions'] as List?) ?? const [])
            .whereType<dynamic>()
            .map((e) => ProfileEntry.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  String toJsonString() => jsonEncode(toJson());
  factory UserProfile.fromJsonString(String source) => UserProfile.fromJson(
        Map<String, dynamic>.from(jsonDecode(source) as Map),
      );
}
