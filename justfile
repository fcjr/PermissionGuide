set shell := ["env", "-u", "SDKROOT", "-u", "DEVELOPER_DIR", "bash", "-euo", "pipefail", "-c"]

pk_dir := "Examples/PermissionKitDemo"
pk_app := pk_dir / "build/PermissionKitDemo.app"
pk_id := "com.example.permissionkitdemo"

inst_dir := "Examples/InstallerDemo"
inst_out := inst_dir / "build"
inst_pkg := inst_out / "InstallerDemo.pkg"
inst_id := "com.example.installerdemo"

default:
    @just --list

# Build the library
build:
    swift build

# Build, then open PermissionKitDemo.app
demo: build-demo
    open {{pk_app}}

# Build, then open InstallerDemo.pkg
demo-pkg: build-pkg
    open {{inst_pkg}}

# Build and ad-hoc sign PermissionKitDemo.app (TCC needs a real app bundle)
build-demo:
    #!/usr/bin/env bash
    set -euo pipefail
    unset SDKROOT DEVELOPER_DIR
    cd {{pk_dir}}
    swift build -c release
    BIN=$(swift build -c release --show-bin-path)
    APP=build/PermissionKitDemo.app
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS"
    cp "$BIN/PermissionKitDemo" "$APP/Contents/MacOS/"
    cp Resources/Info.plist "$APP/Contents/"
    codesign --force --sign - "$APP"
    echo "Built {{pk_app}}"

# Build InstallerDemo.app, its SetupPane.bundle plugin, and InstallerDemo.pkg
build-pkg:
    #!/usr/bin/env bash
    set -euo pipefail
    unset SDKROOT DEVELOPER_DIR
    cd {{inst_dir}}
    swift build -c release
    BIN=$(swift build -c release --show-bin-path)
    OUT=build
    rm -rf "$OUT"
    mkdir -p "$OUT/root" "$OUT/plugins"

    # The app. The installer launches it in the background to check and perform steps.
    APP="$OUT/root/InstallerDemo.app"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$BIN/InstallerDemo" "$APP/Contents/MacOS/"
    cp Resources/App-Info.plist "$APP/Contents/Info.plist"

    # A throwaway root certificate for the certificate step. Its private key is deleted
    # right away, so nothing can ever be signed with it.
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=InstallerDemo Root CA" \
        -keyout "$OUT/ca.key" -outform der -out "$APP/Contents/Resources/DemoRootCA.cer" 2>/dev/null
    rm "$OUT/ca.key"
    codesign --force --sign - "$APP"

    # The installer plugin: a bundle whose executable is the plugin's dynamic library.
    PLUGIN="$OUT/plugins/SetupPane.bundle"
    mkdir -p "$PLUGIN/Contents/MacOS"
    cp "$BIN/libInstallerDemoPlugin.dylib" "$PLUGIN/Contents/MacOS/InstallerDemoPlugin"
    cp Resources/Plugin-Info.plist "$PLUGIN/Contents/Info.plist"
    cp Resources/InstallerSections.plist "$OUT/plugins/"
    codesign --force --sign - "$PLUGIN"

    # Keep the app from being relocated to some other copy of it (like the one in build/).
    pkgbuild --root "$OUT/root" --analyze "$OUT/component.plist" >/dev/null
    plutil -replace 0.BundleIsRelocatable -bool NO "$OUT/component.plist"
    pkgbuild --root "$OUT/root" --component-plist "$OUT/component.plist" \
        --identifier {{inst_id}}.pkg --version 1.0 \
        --install-location /Applications "$OUT/component.pkg" >/dev/null
    productbuild --distribution Resources/distribution.xml --package-path "$OUT" \
        --plugins "$OUT/plugins" "$OUT/InstallerDemo.pkg" >/dev/null
    echo "Built {{inst_pkg}}"

# Reset TCC grants for both demos (ad-hoc signing makes each rebuild a new app)
reset:
    -tccutil reset All {{pk_id}}
    -tccutil reset All {{inst_id}}

# Remove the installed InstallerDemo.app and its receipt
uninstall-pkg:
    -tccutil reset All {{inst_id}}
    sudo rm -rf /Applications/InstallerDemo.app
    -sudo pkgutil --forget {{inst_id}}.pkg

# Delete all build output
clean:
    rm -rf .build {{pk_dir}}/.build {{pk_dir}}/build {{inst_dir}}/.build {{inst_out}}
