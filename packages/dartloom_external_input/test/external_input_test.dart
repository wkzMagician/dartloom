import 'package:dartloom_external_input/dartloom_external_input.dart';
import 'package:test/test.dart';

void main() {
  test('round trips a mixed external input batch', () {
    final batch = ExternalInputBatch(
      source: ExternalInputSource.share,
      items: [
        const ExternalText('note'),
        ExternalUrl(Uri.parse('https://example.com/article')),
        const ExternalFile(
          path: '/inbox/report.pdf',
          name: 'report.pdf',
          mimeType: 'application/pdf',
        ),
      ],
    );

    expect(ExternalInputBatch.fromJson(batch.toJson()), batch);
  });

  test('rejects a file without a path', () {
    expect(
      () => ExternalInput.fromJson({'type': 'file'}),
      throwsFormatException,
    );
  });
}
