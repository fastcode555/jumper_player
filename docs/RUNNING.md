# Jump Player — Running & Smoke Test Guide

## Prerequisites

- Flutter SDK ≥ 3.6 (`flutter --version`)
- For macOS: Xcode + CocoaPods (`pod --version`)
- For Linux: `mpv` / `libmpv` installed (see [Native deps](#native-dependencies))
- For Windows: nothing extra — libs are bundled by `media_kit_libs_video`
- For Android/iOS: a connected device or running simulator (`flutter devices`)

## Per-Platform Run Commands

### macOS (Desktop)

```bash
flutter run -d macos
```

Requires Xcode 14+ and macOS 12+. CocoaPods will be invoked automatically on
first run (`pod install` inside `macos/`).

### Linux (Desktop)

```bash
flutter run -d linux
```

Requires `libmpv` ≥ 0.35 to be installed. See [Native deps](#native-dependencies).

### Windows (Desktop)

```bash
flutter run -d windows
```

No extra system libraries needed — `media_kit_libs_video` bundles the native
DLLs that are copied next to the built executable.

### Android

Connect a device or start an AVD, then:

```bash
flutter devices          # verify device appears
flutter run -d android
```

### iOS

Start a simulator or connect a device, then:

```bash
flutter devices          # verify device appears
flutter run -d ios
```

---

## Native Dependencies

Jump Player uses [media_kit](https://pub.dev/packages/media_kit) (libmpv backend)
for video playback.

| Platform | How native libs are provided |
|----------|------------------------------|
| macOS    | Bundled via `media_kit_libs_video` — no manual install |
| Windows  | Bundled via `media_kit_libs_video` — no manual install |
| Android  | Bundled via `media_kit_libs_video` — no manual install |
| iOS      | Bundled via `media_kit_libs_video` — no manual install |
| Linux    | **Must install system MPV** (see below) |

### Linux — system MPV install

```bash
# Debian / Ubuntu
sudo apt install libmpv-dev mpv

# Arch
sudo pacman -S mpv

# Fedora
sudo dnf install mpv-libs mpv
```

For full setup guidance see the
[media_kit Linux setup docs](https://pub.dev/packages/media_kit#linux).

---

## Manual Smoke Checklist (P1)

> **Note:** This checklist requires a physical desktop GUI session. It cannot
> be run headlessly or in CI. A human tester must perform these steps on a
> macOS, Linux, or Windows machine.

1. **Launch** the app:
   ```bash
   flutter run -d macos   # or -d linux / -d windows
   ```
2. **Open a file:** Click the **打开文件** (Open File) button in the centre of
   the window.
3. **Pick a video:** In the native file picker, navigate to a local `.mp4` or
   `.mkv` file and confirm.
4. **Verify playback:** The video should start playing immediately in the player
   area. Audio should be audible (if the file has audio).
5. **Toggle play/pause:** Click the play/pause button (or press Space if
   keyboard shortcut is wired). The video should pause; clicking again should
   resume.

All five steps passing = P1 smoke test PASS.

---

## Running Tests & Static Analysis

```bash
# Unit + widget tests (all should pass)
flutter test

# Static analysis (should report "No issues found!")
flutter analyze
```

## Building (compile + link check)

```bash
# macOS debug build — verifies native linking against media_kit libs
flutter build macos --debug
```

A successful build confirms the native mpv/AVFoundation integration is wired
correctly. The app bundle is written to `build/macos/Build/Products/Debug/`.

---

## Manual Smoke Checklist (P2 — Media Library)

> Requires a desktop GUI session; run by a human.

1. Launch: `flutter run -d macos` (or `-d linux` / `-d windows`).
2. Click **打开文件夹** and pick a folder containing several episode videos
   (nested "one episode per subfolder" OR flat — both work).
3. The right sidebar lists every video found under that folder, ordered by
   episode number, with the current episode highlighted (amber).
4. Click an episode in the sidebar → it jumps to and plays that episode.
5. Click **上一集 / 下一集** (skip-previous / skip-next) → switches correctly;
   buttons disable at the first / last episode.
6. Let an episode play to the end → it auto-advances to the next episode
   (and does NOT skip two — verifies the completion=true-only guard).
7. Click the top-left playlist icon → the sidebar collapses / expands.
8. The P1 **打开文件** single-file open still works.

All steps passing = P2 smoke test PASS.

---

## Manual Smoke Checklist (P2.5 — Control Bar)

> Requires a desktop GUI session; run by a human.

1. Launch: `flutter run -d macos`.
2. There is a bottom control bar with icons: open-file, open-folder,
   previous, play/pause, next, fullscreen — hovering shows a tooltip on each.
3. No floating buttons cover the center of the video anymore.
4. Click fullscreen -> the window goes fullscreen and the icon flips to
   exit-fullscreen; click again -> exits.
5. Open file / open folder, play/pause, previous/next all work from the bar.

All steps passing = P2.5 smoke test PASS.
