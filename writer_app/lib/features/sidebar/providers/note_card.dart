// @trace FEAT-20260517-115000-0004
// Description: Model for individual Note Cards with JSON serialization (Updated for Dynamic Categories & Attributions).

import 'package:uuid/uuid.dart';

class NoteCard {
  final String id;
  final String title;
  final String content;
  final String category;
  final List<String> connections;
  final bool isAttribution;
  final String? sourceUrl;
  final List<AttributionItem>? attributionItems;
  final String attributionType;

  NoteCard({
    String? id,
    required this.title,
    required this.content,
    this.category = 'general',
    this.connections = const [],
    this.isAttribution = false,
    this.sourceUrl,
    this.attributionItems,
    this.attributionType = 'bullet',
  }) : id = id ?? const Uuid().v4();

  NoteCard copyWith({
    String? title,
    String? content,
    String? category,
    List<String>? connections,
    bool? isAttribution,
    String? sourceUrl,
    List<AttributionItem>? attributionItems,
    String? attributionType,
  }) {
    return NoteCard(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      connections: connections ?? this.connections,
      isAttribution: isAttribution ?? this.isAttribution,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      attributionItems: attributionItems ?? this.attributionItems,
      attributionType: attributionType ?? this.attributionType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'category': category,
      'connections': connections,
      'isAttribution': isAttribution,
      'sourceUrl': sourceUrl,
      'attributionItems': attributionItems?.map((x) => x.toJson()).toList(),
      'attributionType': attributionType,
    };
  }

  factory NoteCard.fromJson(Map<String, dynamic> json) {
    final dynamic catVal = json['category'];
    String categoryStr = 'general';
    if (catVal is int) {
      // Map old enum index to string representation
      if (catVal == 0) {
        categoryStr = 'people';
      } else if (catVal == 1) {
        categoryStr = 'places';
      } else if (catVal == 2) {
        categoryStr = 'events';
      } else {
        categoryStr = 'general';
      }
    } else if (catVal is String) {
      categoryStr = catVal;
    }

    final itemsRaw = json['attributionItems'] as List<dynamic>?;
    final List<AttributionItem>? items = itemsRaw
        ?.map((x) => AttributionItem.fromJson(x as Map<String, dynamic>))
        .toList();

    return NoteCard(
      id: json['id'] as String?,
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      category: categoryStr,
      connections: json['connections'] != null
          ? List<String>.from(json['connections'] as Iterable)
          : const [],
      isAttribution: (json['isAttribution'] as bool?) ?? false,
      sourceUrl: json['sourceUrl'] as String?,
      attributionItems: items,
      attributionType: (json['attributionType'] as String?) ?? 'bullet',
    );
  }

  String getAttributionMarkdown() {
    if (attributionItems == null || attributionItems!.isEmpty) return '';
    final buffer = StringBuffer();
    for (int i = 0; i < attributionItems!.length; i++) {
      final item = attributionItems![i];
      final prefix = attributionType == 'number' ? '${i + 1}. ' : '* ';
      buffer.writeln('$prefix${item.text}');
    }
    return buffer.toString();
  }
}

class AttributionItem {
  final String id;
  final String text;
  final List<String> connections;

  AttributionItem({
    String? id,
    required this.text,
    this.connections = const [],
  }) : id = id ?? const Uuid().v4();

  AttributionItem copyWith({
    String? text,
    List<String>? connections,
  }) {
    return AttributionItem(
      id: id,
      text: text ?? this.text,
      connections: connections ?? this.connections,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'connections': connections,
    };
  }

  factory AttributionItem.fromJson(Map<String, dynamic> json) {
    return AttributionItem(
      id: json['id'] as String?,
      text: (json['text'] as String?) ?? '',
      connections: json['connections'] != null
          ? List<String>.from(json['connections'] as Iterable)
          : const [],
    );
  }
}
