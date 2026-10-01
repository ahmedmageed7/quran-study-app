# Quran Study App | تطبيق دراسة القرآن

تطبيق مفتوح المصدر مبني باستخدام Flutter، صُمم لقراءة القرآن ودراسته وتنظيم
الملاحظات الشخصية مع المحافظة الصارمة على سلامة النص القرآني.

An open-source Flutter app for reading and studying the Quran, organizing
personal notes, and preserving the Quran text as an immutable source.

> The project is under active development and is not yet published to an app
> store. Quran text correctness is treated as a release-blocking requirement.

## لماذا هذا المشروع؟

يجمع التطبيق بين القراءة والبحث وأدوات الدراسة الشخصية في تجربة عربية تعمل
محليًا. النص القرآني منفصل عن بيانات المستخدم ولا تعدله عمليات البحث أو
التظليل أو التصنيف أو الملاحظات.

## Current features

- Quran reader using Uthmani text.
- Arabic search with a separate normalized search representation.
- Manual verse categories.
- Word-based highlighting with multiple colors.
- Personal notes linked to verses.
- Locally saved reading progress and settings.
- Separate SQLite storage for user-created data.
- Automated checks for Quran data and user-data integrity.
- Widget, integration, search, storage, and database tests.

## Quran text integrity

The application treats the Quran text as immutable, read-only data:

- The production text is derived from the Tanzil Uthmani text.
- Search normalization never replaces or modifies the displayed source text.
- Highlights store word indexes rather than modified Quran text.
- Notes, categories, reading progress, and settings live in a separate local
  database.
- A release check verifies that all 6,236 production verses match the immutable
  source exactly and appear under the correct surah and ayah numbers.

See [Quran data sources and notices](THIRD_PARTY_NOTICES.md) for attribution and
the terms that apply to the included datasets.

## Development

### Requirements

- Flutter SDK compatible with Dart `^3.13.4`
- Android Studio or another supported Flutter development environment

### Run the app

```sh
flutter pub get
flutter run
```

### Run tests

```sh
flutter test
```

### Validate Quran data

```sh
dart run tools/quran_validation/validate_production.dart
```

A validation mismatch must be investigated and must never be accepted by
silently changing the Quran source.

## Project status and roadmap

The reader, search, categories, highlighting, notes, reading progress, and local
storage are implemented. Current work focuses on release readiness, additional
accessibility review, documentation, and carefully scoped study features.

Planned AI-assisted analysis must remain optional. It must never generate,
replace, correct, or automatically classify Quran text.

## Contributing

Issues and pull requests are welcome. Changes involving Quran data require:

1. A documented source and license.
2. Reproducible validation.
3. Passing integrity checks and tests.
4. Human review before merge.

Please avoid committing personal notes, generated databases, credentials, or
build artifacts.

## License

The application source code is licensed under the MIT License. Quran text and
reference datasets are excluded from the MIT grant and remain subject to their
respective upstream terms. See [LICENSE](LICENSE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
