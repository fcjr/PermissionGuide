use permissionguide_media::{Media, run, clips::{Clip, ClipKind}};
use fframes::StaticMediaProvider;

fn main() -> std::process::ExitCode {
    let media = Media::prepare().expect("media");
    run(&Clip { media: &media, kind: ClipKind::Installer }, &media, "out/installer.mp4")
}
