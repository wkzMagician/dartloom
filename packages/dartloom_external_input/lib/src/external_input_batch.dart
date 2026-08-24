import 'external_input.dart';

enum ExternalInputSource { share, openWith, intent, deepLink }

final class ExternalInputBatch {
  const ExternalInputBatch({required this.items, required this.source});

  final List<ExternalInput> items;
  final ExternalInputSource source;

  Map<String, Object?> toJson() => {
        'items': items.map((item) => item.toJson()).toList(growable: false),
        'source': source.name,
      };

  static ExternalInputBatch fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'An external input batch must be a JSON object.',
      );
    }
    final json = Map<String, Object?>.from(value);
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException(
        'External input batch requires an items list.',
      );
    }
    final sourceName = json['source'];
    final source = switch (sourceName) {
      'share' => ExternalInputSource.share,
      'openWith' => ExternalInputSource.openWith,
      'intent' => ExternalInputSource.intent,
      'deepLink' => ExternalInputSource.deepLink,
      _ => throw FormatException('Unknown external input source: $sourceName'),
    };
    return ExternalInputBatch(
      items: List.unmodifiable(rawItems.map(ExternalInput.fromJson)),
      source: source,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExternalInputBatch &&
      other.source == source &&
      _sameItems(other.items, items);

  @override
  int get hashCode => Object.hashAll([source, ...items]);
}

bool _sameItems(List<ExternalInput> first, List<ExternalInput> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
