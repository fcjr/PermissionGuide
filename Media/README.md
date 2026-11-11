# PermissionGuide media

The README's GIFs and the release teaser, made with [fframes](https://fframes.studio).
Nothing here is a screen recording: the scenes redraw what the library shows, with the sizes
and texts taken from `Sources/PermissionGuide`. A real capture would need someone to grant a
permission and use Touch ID each time, so it couldn't be rendered again unattended.

| file | what |
| --- | --- |
| `src/timing.rs` | every time in the clips and the teaser |
| `src/lib.rs` | System Settings, the highlight, the side panel, the drag hint, the app window |
| `src/clips.rs` | the three README clips, and the installer window |
| `src/teaser.rs` | the teaser's six scenes |
| `sound/soundtrack.rs` | the teaser's music and interface sounds |
| `build.rs` | writes the soundtrack and copies the fonts into `media/` |

## Render

From the repository root:

```sh
just media    # everything
just gifs     # Assets/drag.gif, Assets/extension.gif, Assets/installer.gif
just teaser   # Media/out/permissionguide-teaser.mp4, 1920x1080 at 60 fps with sound
```

The GIFs are committed, because the README shows them. The teaser is not: render it when you
need it.

To check a moment without rendering a whole video:

```sh
cd Media
cargo build --release --bins
./target/release/clip-drag frame 5.2s      # frames/5.2s.png
./target/release/teaser strip -n 12        # a contact sheet, strip.png
./target/release/teaser timeline           # scenes and the audio track
```

## What it needs

- A Mac with Xcode's command line tools, Rust and `ffmpeg` (`brew install ffmpeg`), which
  turns the clips into GIFs. The videos themselves are encoded by VideoToolbox.
- **SF Pro** in `/Library/Fonts`, from <https://developer.apple.com/fonts/>. Apple's fonts
  can't be committed, so `build.rs` copies them, and Monaco, into `media/`.
- **An older macOS SDK, if you build on macOS 27.** Linked against the macOS 27 SDK, the
  proc-macro dylibs that fframes' `include_media_dir!` needs fail to load ("mis-aligned
  LINKEDIT string pool"). Point `SDKROOT` at an older SDK in `Media/.cargo/config.toml`,
  which git ignores:

  ```toml
  [env]
  SDKROOT = "<path to an older MacOSX SDK>"
  ```

  `Cargo.lock` pins fframes 1.2.0.

`render.sh` passes bindgen this Mac's target. Without it, a `LIBCLANG_PATH` that points at a
cross-compiling toolchain fails the build with "Unsupported architecture".

## Sound

`sound/soundtrack.rs` synthesizes the whole soundtrack from sine waves and seeded noise: no
samples, loops or third-party audio, so there is nothing to license, and the same source
always gives the same file. It is a 100 BPM bed in D major under interface sounds: a pop per
step in the hook, clicks, a whoosh when a window opens or closes, a chime when Touch ID
succeeds and another when the permission is granted, and a key press per typed character.

It reads its times from `src/timing.rs`, the same constants the scenes are drawn from. Every
scene starts on a bar (2.4 s), so keep scene lengths in multiples of `BEAT` if you change
them. `build.rs` runs it before the crate compiles and writes `media/soundtrack.wav`, which
the teaser plays through `Video::audio`. Levels are `MUSIC` and `SFX` at the top of the file.
