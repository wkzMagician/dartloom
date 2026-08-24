/// A presentation-neutral destination supplied by an application to a
/// platform-owned external-input picker.
final class ExternalInputDestination {
  const ExternalInputDestination({
    required this.id,
    required this.title,
    this.subtitle,
  });

  final String id;
  final String title;
  final String? subtitle;
}
