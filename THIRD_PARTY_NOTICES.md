# Third-party data notices

The MIT License in this repository applies to the application source code. It
does not replace the licenses or usage terms of the Quran datasets below.

## Tanzil Uthmani Quran Text

Files covered:

- `assets/quran/source/quran-uthmani.txt`
- `assets/quran/data/quran_data.json` (a structured derivative that preserves
  the source verse text)

Source: [Tanzil Project](https://tanzil.net/)

Copyright (C) 2007-2021 Tanzil Project

License: [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/)

Tanzil's published terms require that:

- Verbatim copies of the Quran text may be copied and distributed, but the text
  must not be changed.
- The Tanzil Project must be clearly identified as the source, with a link to
  `tanzil.net` so users can follow text updates.
- The copyright notice must be included in verbatim copies and reproduced in
  files derived from or containing a substantial portion of the text.

The authoritative terms are available at
<https://tanzil.net/docs/Text_License>. If this summary differs from the
upstream terms, the upstream terms govern.

## KFGQPC Hafs reference dataset

File covered:

- `assets/quran/reference/hafsData_v18.json`

Source: King Fahd Glorious Quran Printing Complex data, obtained through a
public dataset distribution. The file is used only as a development-time
reference for integrity comparison and is not loaded by the application at
runtime.

The upstream provenance and redistribution terms for this exact copy still
need to be recorded more precisely. Until that documentation is complete,
redistributors should verify the current terms with the King Fahd Complex and
must not assume that the repository's MIT License covers this file.

## Integrity policy

Quran source text is treated as immutable. Search indexes, highlights, notes,
and categories must never overwrite it. Any mismatch found by validation is a
failure that requires human review.
