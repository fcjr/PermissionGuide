#!/bin/sh
# Rebuilds the README's GIFs (../Assets) and the release teaser (out/).
#   ./render.sh          everything
#   ./render.sh gifs     only the GIFs
#   ./render.sh teaser   only the teaser
set -eu
cd "$(dirname "$0")"
what="${1:-all}"

# bindgen (for fframes' FFmpeg bindings) needs a clang that targets this Mac. A LIBCLANG_PATH
# pointing at a cross toolchain otherwise fails with "Unsupported architecture".
export BINDGEN_EXTRA_CLANG_ARGS="${BINDGEN_EXTRA_CLANG_ARGS:---target=$(uname -m)-apple-macosx}"
cargo build --release --bins
bin="${CARGO_TARGET_DIR:-target}/release"
mkdir -p out ../Assets

if [ "$what" = all ] || [ "$what" = gifs ]; then
  for clip in drag extension installer; do
    "$bin/clip-$clip" render -o "out/$clip.mp4"
    ffmpeg -y -loglevel error -i "out/$clip.mp4" \
      -vf "scale=880:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
      -loop 0 "../Assets/$clip.gif"
    echo "Wrote Assets/$clip.gif"
  done
fi

if [ "$what" = all ] || [ "$what" = teaser ]; then
  "$bin/teaser" render -o out/permissionguide-teaser.mp4
  echo "Wrote Media/out/permissionguide-teaser.mp4"
fi
