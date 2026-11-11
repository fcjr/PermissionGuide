use permissionguide_media::{Media, run, teaser::Teaser};
use fframes::StaticMediaProvider;

fn main() -> std::process::ExitCode {
    let media = Media::prepare().expect("media");
    run(&Teaser::new(&media), &media, "out/permissionguide-teaser.mp4")
}
