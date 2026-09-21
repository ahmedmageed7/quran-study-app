\# Quran Study App — Project Specification



\## 1. Project Goal



A personal Android application for studying the Quran and extracting a practical methodology for life.



The user manually classifies Quran verses into personal categories and may later use AI for analysis.



AI is an analysis assistant only.

AI must never be the source of Quranic text and must never automatically classify verses.



\---



\## 2. Quran Text — CRITICAL REQUIREMENT



Primary source: Tanzil Uthmani.



Requirements:



\- Quran text is immutable and read-only.

\- Preserve Uthmani script exactly.

\- Preserve all diacritics and Quranic symbols.

\- Never modify the original Quran text.

\- Search, highlighting, categories, notes, and AI must never alter the original text.

\- Maintain a separate normalized representation for search.

\- Use a trusted secondary source for development-time verification.

\- Do not mix the secondary source into the production Quran text.



\### Automated Validation



Before accepting Quran data:



\- Validate all 114 surahs.

\- Validate verse count.

\- Validate verse ordering.

\- Compare every word.

\- Compare every character.

\- Compare diacritics.

\- Compare Quranic symbols.

\- Validate Unicode representation.

\- Compare the primary source against the trusted reference.



Any mismatch = `FAIL`.



The validation report must identify:



\- Surah

\- Ayah

\- Position

\- Type of difference

\- Primary text

\- Reference text



Production Quran data must not be accepted if validation fails.



\---



\## 3. Main Screen



Main sections:



\- القرآن

\- الفعل

\- العمل

\- المتقين

\- الأسماء الحسنى

\- النواهي

\- الأوامر

\- العقوبات

\- الحمد

\- الدعاء

\- آيات محكمة

\- إضافة بند

\- ملاحظات

\- الإعدادات



Requirements:



\- Arabic RTL.

\- Clear navigation.

\- Android back button supported.

\- Preserve navigation state when returning.



\---



\## 4. Quran Reader



When opening Quran:



\- Resume automatically from the last reading position.

\- Display the complete Uthmani text.

\- Preserve full diacritics and Quranic symbols.

\- Fast and smooth scrolling.

\- Dark mode.

\- Do not reload Quran data unnecessarily.

\- Preserve reading position when navigating away and returning.



\---



\## 5. Manual Verse Classification



Each ayah has a very small vertical three-dot button:



`⋮`



The button is only for category management.



When pressed:



\- Show a very small vertical dropdown.

\- Show all available categories.

\- Categories already assigned to the ayah show `✓` / Selected state.

\- Allow adding the ayah to another category.

\- An ayah may belong to multiple categories.

\- Include `إضافة بند`.

\- Do not add unrelated actions to this menu.



Example:



الآية ⋮



الفعل

✓ العمل

المتقين

✓ الأوامر

...

آيات محكمة



إضافة بند



Do NOT use colored dots to represent the number of categories.



\---



\## 6. Word / Phrase Highlighting



Long-press a word or phrase inside an ayah.



Flow:



1. Show a small color palette.

2. User selects a color.

3. Highlight the selected word/phrase inside the original ayah.

4. Multiple highlights with different colors are supported.

5. Quran text remains immutable.

6. Highlight data must reference the original Quran text rather than storing a replacement Quran string.



Implementation requirement:



Use token-based highlighting or grapheme-aware ranges.



Do NOT rely on simple character offsets that may break Arabic combining marks, Quranic symbols, or grapheme clusters.



\---



\## 7. Search



Provide an extremely fast local search.



Requirements:



\- Search all words in all Quranic verses.

\- Search starts immediately while typing.

\- No search button required.

\- Match beginning, middle, and end of words.

\- Search is insensitive to diacritics.

\- Normalize relevant Arabic variations, including:

&#x20; - أ

&#x20; - إ

&#x20; - آ

&#x20; - ا

&#x20; - ي

&#x20; - ى

&#x20; - hamza variations

&#x20; - diacritics

&#x20; - Quranic symbols

&#x20; - relevant Unicode Arabic/Quranic characters



Important:



The normalized search representation must be separate from the immutable Quran text.



Use SQLite FTS or another suitable high-performance local search engine.



Search results:



\- Show only a short matching excerpt.

\- Do NOT show surah name.

\- Do NOT show ayah number.

\- Highlight matching characters.

\- Tapping a result opens the original ayah in full Uthmani text.



\---



\## 8. Data Architecture



Strictly separate immutable Quran data from user data.



\### Quran Data



\- Surah ID

\- Ayah ID

\- Uthmani original text

\- Word/token information

\- Search-normalized representation



\### User Data



\- Categories

\- Ayah-category relationships

\- Highlights

\- Highlight colors

\- Notes

\- Last reading position

\- Settings



The Quran dataset must never be modified by user actions.



\---



\## 9. Navigation



Navigation must preserve state.



Example:



Home

→ Category

→ Ayah

→ Ayah position in Quran



When returning:



\- Restore previous position.

\- Preserve classifications.

\- Preserve highlights.

\- Preserve notes.

\- Preserve reading state.



Android system Back button must work correctly.



\---



\## 10. Performance



Priority order:



1\. Very fast application startup.

2\. Very fast local search.

3\. Fast Quran rendering.

4\. Offline-first operation.

5\. Avoid unnecessary data reloads.

6\. Efficient SQLite/local storage.

7\. Separate static Quran data from mutable user data.



Do not introduce unnecessary animations, network requests, or heavy dependencies.



\---



\## 11. UI / UX



Design requirements:



\- Arabic RTL.

\- Modern.

\- Clean.

\- Minimal.

\- Comfortable for long reading sessions.

\- Dark mode.

\- Quran text is the visual priority.

\- Avoid distracting animations and decorative elements.

\- Avoid unnecessary UI controls.

\- The three-dot category button must remain small and unobtrusive.



\---



\## 12. Offline-First



The application must remain fully usable without internet access for core functions:



\- Quran reading

\- Categories

\- Classification

\- Highlighting

\- Notes

\- Search

\- Reading position

\- Settings



Internet should only be required for cloud synchronization or other explicitly online functionality.



\---



\## 13. OneDrive Backup / Synchronization



User data must eventually support OneDrive backup and synchronization.



Sync must protect against:



\- Device loss

\- Device replacement

\- Local data loss



Important:



\- Immutable Quran data should not be unnecessarily synchronized as user data.

\- User-created data is the primary synchronization target.

\- Conflict handling must be designed before implementation.

\- Never allow synchronization to overwrite or corrupt the original Quran dataset.



\---



\## 14. AI Usage



AI may later assist with:



\- Analysis of user-classified verses.

\- Discovering patterns in the user's manually created categories.

\- Organizing or analyzing personal notes.

\- Generating analytical summaries from user data.



AI must NOT:



\- Generate Quranic text.

\- Modify Quranic text.

\- Replace the trusted Quran source.

\- Automatically classify verses.

\- silently change user classifications.

\- silently modify user notes.



Any future AI feature must clearly distinguish:



`Quran Source Data`

from

`User Data`

from

`AI Analysis`.



\---



\## 15. Prohibited Features



Do not add:



\- Tafsir.

\- Hadith.

\- Automatic AI verse classification.

\- AI-generated Quran text.

\- Unrequested features.

\- Unnecessary UI elements.

\- Decorative elements that distract from reading.

\- Any modification of the original Quran text.



Do not add functionality merely because it is technically possible.



\---



\## 16. Development Principles



\- Flutter + Dart.

\- Android is the primary target.

\- Clean and scalable architecture.

\- Local-first data architecture.

\- Minimize dependencies.

\- Prefer reliable, mature packages.

\- Keep Quran data immutable.

\- Write tests for critical functionality.

\- Validate Quran data before production use.

\- Keep code simple and maintainable.

\- Avoid premature complexity.



\---



\## 17. Testing Requirements



Before release, test at minimum:



\### Quran Integrity

\- Full Quran validation.

\- All 114 surahs.

\- All verses.

\- Unicode and Quranic symbols.



\### Search

\- Arabic normalization.

\- Diacritics.

\- Hamza variants.

\- Beginning/middle/end matching.

\- Large result sets.

\- Instant search performance.



\### Classification

\- Add verse to category.

\- Remove verse from category.

\- Multiple categories per verse.

\- Custom category.

\- State persistence.



\### Highlighting

\- Single word.

\- Multiple words.

\- Multiple highlights.

\- Different colors.

\- Arabic diacritics.

\- Quranic symbols.

\- Persistence after restart.



\### Navigation

\- Back navigation.

\- Category → ayah.

\- Search → ayah.

\- Resume last reading position.



\### Data

\- App restart.

\- Database integrity.

\- Backup/restore.

\- OneDrive synchronization.

\- Conflict handling.



\---



\## 18. Development Order



Do not build the entire application at once.



Recommended sequence:



1\. Project specification.

2\. Quran source acquisition.

3\. Quran integrity validation tool.

4\. Immutable Quran data layer.

5\. Database schema.

6\. Core application architecture.

7\. Quran reader.

8\. Category system.

9\. Search engine.

10\. Highlighting system.

11\. Notes.

12\. Reading-position persistence.

13\. Settings.

14\. OneDrive backup/synchronization.

15\. Full testing.

16\. Performance optimization.

17\. AI analysis layer.

18\. Release build.



\---



\## 19. Critical Rule



When requirements are unclear, STOP and ask before implementing.



Do not invent requirements.



Do not expand the scope without explicit approval.



The project priority is:



Accuracy → Data integrity → Performance → Usability → Design → Future AI features.

