sealed class ExternalInput {
  const ExternalInput();

  Map<String, Object?> toJson();

  static ExternalInput fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('An external input must be a JSON object.');
    }
    final json = Map<String, Object?>.from(value);
    switch (json['type']) {
      case 'text':
        final text = json['text'];
        if (text is! String) {
          throw const FormatException('External text requires a string value.');
        }
        return ExternalText(text);
      case 'url':
        final value = json['url'];
        final url = value is String ? Uri.tryParse(value) : null;
        if (url == null || url.scheme.isEmpty) {
          throw const FormatException('External URL requires an absolute URI.');
        }
        return ExternalUrl(url);
      case 'file':
        final path = json['path'];
        if (path is! String || path.isEmpty) {
          throw const FormatException('External file requires a path.');
        }
        return ExternalFile(
          path: path,
          name: json['name'] as String?,
          mimeType: json['mimeType'] as String?,
        );
      default:
        throw FormatException('Unknown external input type: ${json['type']}');
    }
  }
}

final class ExternalText extends ExternalInput {
  const ExternalText(this.text);

  final String text;

  @override
  Map<String, Object?> toJson() => {'type': 'text', 'text': text};

  @override
  bool operator ==(Object other) => other is ExternalText && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

final class ExternalUrl extends ExternalInput {
  const ExternalUrl(this.url);

  final Uri url;

  @override
  Map<String, Object?> toJson() => {'type': 'url', 'url': url.toString()};

  @override
  bool operator ==(Object other) => other is ExternalUrl && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

final class ExternalFile extends ExternalInput {
  const ExternalFile({required this.path, this.name, this.mimeType});

  final String path;
  final String? name;
  final String? mimeType;

  @override
  Map<String, Object?> toJson() => {
        'type': 'file',
        'path': path,
        if (name != null) 'name': name,
        if (mimeType != null) 'mimeType': mimeType,
      };

  @override
  bool operator ==(Object other) =>
      other is ExternalFile &&
      other.path == path &&
      other.name == name &&
      other.mimeType == mimeType;

  @override
  int get hashCode => Object.hash(path, name, mimeType);
}
