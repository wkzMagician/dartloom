/// Model contracts contain no application prompts, credentials, or Flutter code.
library;

enum ModelAccess { api, subscription, local }

class ModelConnection {
  const ModelConnection({
    required this.access,
    required this.model,
    this.endpoint = '',
    this.executable = 'codex',
  });
  final ModelAccess access;
  final String model;
  final String endpoint;
  final String executable;

  Map<String, Object?> toJson() => {
    'access': access.name,
    'model': model,
    'endpoint': endpoint,
    'executable': executable,
  };

  factory ModelConnection.fromJson(Map<String, Object?> json) =>
      ModelConnection(
        access: ModelAccess.values.byName(json['access']! as String),
        model: json['model'] as String? ?? '',
        endpoint: json['endpoint'] as String? ?? '',
        executable: json['executable'] as String? ?? 'codex',
      );
}

class ModelRequest {
  const ModelRequest({required this.system, required this.input});
  final String system;
  final String input;
}

abstract interface class GenerationModel {
  Future<String> generate(ModelRequest request);
}

abstract interface class EmbeddingModel {
  String get identity;
  Future<List<List<double>>> embed(List<String> texts);
}

class ModelException implements Exception {
  const ModelException(this.message);
  final String message;
  @override
  String toString() => message;
}
