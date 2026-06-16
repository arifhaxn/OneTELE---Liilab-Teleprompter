# OneTele

A minimal docx-driven teleprompter. Load a `.docx`, and each paragraph becomes
one on-screen question. Arrow keys move between them. Defaults are tuned to sit
in the same position/size as a centered Word page (black text on white).

## Run it (web browser)

You need the Flutter SDK installed. Then:

```bash
# 1. Create a fresh project shell (generates web/, android/, etc.)
flutter create onetele_app

# 2. Copy these two files into it, replacing the originals:
#    - pubspec.yaml      -> onetele_app/pubspec.yaml
#    - lib/main.dart     -> onetele_app/lib/main.dart
cp pubspec.yaml onetele_app/pubspec.yaml
cp lib/main.dart onetele_app/lib/main.dart

cd onetele_app

# 3. Fetch packages and run in Chrome
flutter pub get
flutter run -d chrome
```

For a deployable build: `flutter build web` → serve the `build/web` folder.

## Controls

| Key            | Action                |
|----------------|-----------------------|
| → / ↓ / PageDn | Next question         |
| ← / ↑ / PageUp | Previous question     |
| Home / End     | First / last question |
| B              | Toggle black/white bg |
| H              | Hide / show controls  |

Bottom bar: open file, prev/next, counter, background toggle, hide, and three
sliders — **Font** (size), **Width** (column wrap width), **Top** (vertical
position). Hidden controls return via the small button (top-right) or `H`.

## Notes / assumptions

- **One paragraph = one question.** Blank paragraphs are skipped. Line breaks
  inside a single paragraph are preserved (shown as multiple lines of the same
  question).
- Default font size and top offset are computed from your viewport so they match
  the reference screenshot regardless of screen resolution.
