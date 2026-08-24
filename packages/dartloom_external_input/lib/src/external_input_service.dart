import 'external_input_batch.dart';

abstract interface class ExternalInputService {
  Stream<ExternalInputBatch> get inputs;

  /// Atomically takes batches which arrived before [inputs] was observed.
  Future<List<ExternalInputBatch>> takePending();
}
