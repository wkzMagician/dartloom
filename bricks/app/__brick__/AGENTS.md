# Agent Instructions

This project is managed by Dartloom. Read `dartloom.yaml` before changing
infrastructure. Feature code imports capability contracts and obtains configured
implementations through `Dartloom.get<T>(name: ...)`; it must not import adapter
packages directly. Register app-owned implementations through the generated
`initializeDartloom` custom factory map. Keep business code in `lib/features`.
Call `bootstrapDartloom()` from `lib/capabilities/bootstrap.dart` before
running the application's widget tree. Dartloom only owns files in
`lib/capabilities`; application widgets and ARB files remain application-owned.

Before finishing, run `dart format .`, `flutter analyze`, and `flutter test`.
