# Contributing

Thank you for helping improve Quran Study App. Bug reports, accessibility
feedback, documentation improvements, tests, and focused code changes are
welcome.

## Before opening a pull request

1. Open or reference an issue that explains the problem and intended behavior.
2. Keep the change focused and avoid unrelated formatting changes.
3. Run `flutter test` and `flutter analyze`.
4. Add or update tests when behavior changes.

## Quran data changes

Changes involving Quran text receive additional review. A contribution must:

- identify the authoritative source and applicable terms;
- preserve the immutable production source;
- include a reproducible validation procedure;
- pass `dart run tools/quran_validation/validate_production.dart`;
- explain every byte-level change for human review.

Search normalization, highlighting, notes, and categories must never modify the
canonical Quran text. Do not submit generated or corrected Quran text from an
AI system.

## Code style

Format Dart files with `dart format`. Prefer small, readable components and
tests that describe user-visible behavior.

## Personal and sensitive data

Do not include credentials, personal notes, local databases, analytics exports,
or other user data in issues or pull requests.
