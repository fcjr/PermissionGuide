//! Fills `media/` before the crate compiles, because `include_media_dir!` embeds whatever is
//! there: the soundtrack is synthesized from `sound/soundtrack.rs`, and the SF Pro fonts,
//! which can't be committed, are copied from the system.
use std::{fs, path::Path};

#[path = "src/timing.rs"]
mod timing;
#[path = "sound/soundtrack.rs"]
mod soundtrack;

/// SF Pro comes from Apple's font download; Monaco ships with macOS.
const FONTS: [&str; 7] = [
    "/Library/Fonts/SF-Pro-Text-Regular.otf",
    "/Library/Fonts/SF-Pro-Text-Medium.otf",
    "/Library/Fonts/SF-Pro-Text-Semibold.otf",
    "/Library/Fonts/SF-Pro-Display-Semibold.otf",
    "/Library/Fonts/SF-Pro-Display-Bold.otf",
    "/Library/Fonts/SF-Pro-Display-Black.otf",
    "/System/Library/Fonts/Monaco.ttf",
];

fn main() {
    for file in ["build.rs", "src/timing.rs", "sound/soundtrack.rs"] {
        println!("cargo:rerun-if-changed={file}");
    }
    let media = Path::new("media");

    for font in FONTS {
        let from = Path::new(font);
        let to = media.join(from.file_name().expect("font file name"));
        if to.exists() {
            continue;
        }
        if let Err(error) = fs::copy(from, &to) {
            panic!(
                "{} is missing ({error}). Install SF Pro from https://developer.apple.com/fonts/ and build again.",
                from.display()
            );
        }
    }

    // Only touch the file when it changes, so an unchanged soundtrack doesn't rebuild the crate.
    let wav = soundtrack::wav();
    let path = media.join("soundtrack.wav");
    if fs::read(&path).ok().as_deref() != Some(&wav[..]) {
        fs::write(&path, wav).expect("write media/soundtrack.wav");
    }
}
