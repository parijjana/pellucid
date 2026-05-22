// @trace FEAT-20260517-115000-0004
// Description: Model for individual Note Cards with JSON serialization.

import 'package:uuid/uuid.dart';

enum NoteCategory { people, places, events, general }

class NoteCard {
  final String id;
  final String title;
  final String content;
  final NoteCategory category;
  final List<String> connections;

  NoteCard({
    String? id,
    required this.title,
    required this.content,
    this.category = NoteCategory.general,
    this.connections = const [],
  }) : id = id ?? const Uuid().v4();

  NoteCard copyWith({
    String? title,
    String? content,
    NoteCategory? category,
    List<String>? connections,
  }) {
    return NoteCard(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      connections: connections ?? this.connections,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'category': category.index,
      'connections': connections,
    };
  }

  factory NoteCard.fromJson(Map<String, dynamic> json) {
    return NoteCard(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      category: NoteCategory.values[json['category'] as int],
      connections: List<String>.from(json['connections']),
    );
  }
}
