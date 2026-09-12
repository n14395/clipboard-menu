#!/bin/bash
# ClipboardMenu — build, package, sign and publish.
#
#   ./build.sh                 build the production build/ClipboardMenu.app
#   ./build.sh --dmg           …and package it into build/ClipboardMenu.dmg
#   ./build.sh --sign          …Developer ID sign the .app and .dmg, notarize and staple
#   ./build.sh --publish vN.N  tag, push and cut a GitHub release from build/ClipboardMenu.dmg
#
# Flags combine — `./build.sh --sign --publish v1.2` signs, notarizes and releases in
# one go. `--publish` on its own does not rebuild: it requires build/ClipboardMenu.dmg to
# already exist.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ClipboardMenu"
BUILD_DIR="$PWD/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
BUNDLE_ID="com.n14395.clipboardMenu"
ENTITLEMENTS=""

# Exported from ~/.zshrc. The literal fallback keeps the script working when it is
# run from a shell that never sourced it (cron, a GUI runner, `env -i`).
DEV_TEAM_IDENTITY="${DEV_TEAM_IDENTITY:-Developer ID Application: Nicholas Fay (P52946XHRJ)}"
NOTARY_PROFILE="notary-profile"

die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; }

WANT_DMG=0
WANT_SIGN=0
PUBLISH_VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg)   WANT_DMG=1 ;;
        --sign)  WANT_SIGN=1 ;;
        --publish)
            [[ $# -ge 2 ]] || die "--publish needs a version argument, e.g. --publish v1.2"
            PUBLISH_VERSION="$2"; shift ;;
        --publish=*) PUBLISH_VERSION="${1#*=}" ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown flag: $1 (try --help)" ;;
    esac
    shift
done

# vN.N or vN.N.N — anything else is a typo we would rather catch before tagging.
if [[ -n "$PUBLISH_VERSION" ]]; then
    [[ "$PUBLISH_VERSION" =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
        || die "--publish needs a version like v1.2 or v1.2.3 (got: '$PUBLISH_VERSION')"
    VERSION_NUM="${PUBLISH_VERSION#v}"
fi

# Full Xcode, not the bare Command Line Tools: xcodebuild refuses to run under
# CLT, and even SwiftPM needs Xcode's toolchain for the SwiftUI macro plugins.
# Set DEVELOPER_DIR for this process only — the system default is left alone.
if [[ -z "${DEVELOPER_DIR:-}" ]] && ! xcode-select -p 2>/dev/null | grep -q '\.app'; then
    for xc in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [[ -d "$xc" ]]; then export DEVELOPER_DIR="$xc/Contents/Developer"; break; fi
    done
fi

# xcodebuild is extremely chatty, and `xcodebuild | grep` throws away its exit
# status — which would let a failed compile fall through to packaging whatever
# stale bundle happened to be lying around. Filter the noise, keep the status.
xcb() {
    local log
    log="$(mktemp "${TMPDIR:-/tmp}/xcodebuild.XXXXXX")"
    if ! xcodebuild "$@" >"$log" 2>&1; then
        grep -E "error:|BUILD FAILED" "$log" | tail -30
        echo "xcodebuild failed — full log: $log" >&2
        return 1
    fi
    grep -E "^\*\* BUILD" "$log" || true
    rm -f "$log"
}

# A plain drag-to-install image: the app plus an /Applications symlink, nothing
# else. Staged under build/ so the volume contains exactly those two items and
# no stray DerivedData.
DMG_STAGING="$BUILD_DIR/.dmg-staging"
cleanup() { rm -rf "$DMG_STAGING"; return 0; }
trap cleanup EXIT

make_dmg() {
    [[ -d "$APP_PATH" ]] || die "$APP_PATH not found — build it first"
    step "Packaging $APP_NAME.dmg"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    # ditto, not cp: it preserves the code signature and extended attributes.
    ditto "$APP_PATH" "$DMG_STAGING/$APP_NAME.app"
    ln -s /Applications "$DMG_STAGING/Applications"
    rm -f "$DMG_PATH"
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" \
        -fs HFS+ -format UDZO -ov -quiet "$DMG_PATH"
    rm -rf "$DMG_STAGING"
    echo "    $DMG_PATH"
}

# codesign never recurses into nested code, and the notary service rejects a
# bundle whose frameworks / app extensions / bundled helper binaries still carry
# an older signature. So sign inside-out, deepest path first, then the bundle
# itself. Entitlements are read back off each item and re-applied: a bare
# --force re-sign silently drops them, which would break sandboxing and TCC.
sign_one() {
    local target="$1" ent="" args=()
    if [[ "$target" == "$APP_PATH" && -n "$ENTITLEMENTS" && -f "$ENTITLEMENTS" ]]; then
        args+=(--entitlements "$ENTITLEMENTS")
    else
        ent="$(mktemp "${TMPDIR:-/tmp}/entitlements.XXXXXX")"
        if codesign -d --entitlements - --xml "$target" 2>/dev/null | grep -q '<plist'; then
            codesign -d --entitlements - --xml "$target" 2>/dev/null >"$ent"
            # get-task-allow is the debugger entitlement Xcode injects into
            # development-signed builds. The notary service rejects any binary
            # that still requests it, so drop it before re-signing.
            /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' \
                "$ent" >/dev/null 2>&1 || true
            args+=(--entitlements "$ent")
        else
            rm -f "$ent"; ent=""
        fi
    fi
    codesign --force --options runtime --timestamp \
        ${args[@]+"${args[@]}"} --sign "$DEV_TEAM_IDENTITY" "$target"
    [[ -n "$ent" ]] && rm -f "$ent"
    echo "    signed ${target#$BUILD_DIR/}"
}

sign_bundle() {
    local inner
    while IFS= read -r inner; do
        sign_one "$inner"
    done < <(
        {
            find "$APP_PATH/Contents" \
                \( -name '*.framework' -o -name '*.appex' -o -name '*.xpc' \
                   -o -name '*.app' -o -name '*.bundle' -o -name '*.dylib' \
                   -o -name '*.so' \) 2>/dev/null
            # Loose Mach-O helpers: bundled CLIs in Resources, login items…
            find "$APP_PATH/Contents" -type f -perm -u+x 2>/dev/null \
                | while IFS= read -r f; do
                      file -b "$f" 2>/dev/null | grep -q 'Mach-O' && printf '%s\n' "$f"
                  done
        } | grep -v "/Contents/MacOS/[^/]*$" \
          | sort -u | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-
    )
    sign_one "$APP_PATH"
}

sign_and_notarize() {
    step "Developer ID signing $APP_NAME.app"
    echo "    identity: $DEV_TEAM_IDENTITY"
    sign_bundle

    make_dmg

    step "Developer ID signing $APP_NAME.dmg"
    codesign --force --timestamp --sign "$DEV_TEAM_IDENTITY" "$DMG_PATH"

    step "Verifying the .dmg signature"
    if ! codesign --verify --verbose=2 "$DMG_PATH"; then
        die "codesign --verify failed for $DMG_PATH — not submitting for notarization"
    fi

    step "Notarizing (this waits on Apple; usually a few minutes)"
    local out rc=0 status uuid
    out="$(xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)" || rc=$?
    printf '%s\n' "$out"
    [[ $rc -eq 0 ]] || die "notarytool submit failed (exit $rc)"

    status="$(printf '%s\n' "$out" | awk -F': *' '/^ *status:/ {print $2; exit}')"
    uuid="$(printf '%s\n' "$out"   | awk -F': *' '/^ *id:/     {print $2; exit}')"
    if [[ "$status" != "Accepted" ]]; then
        if [[ -n "$uuid" ]]; then
            step "Fetching the notarization log"
            xcrun notarytool log "$uuid" --keychain-profile "$NOTARY_PROFILE" \
                "$BUILD_DIR/notary-log.json" || true
            echo "    log written to $BUILD_DIR/notary-log.json"
        fi
        die "notarization returned status: ${status:-unknown}"
    fi

    step "Stapling the ticket"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"

    step "Gatekeeper assessment"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"

    step "Notarized and stapled: $DMG_PATH"
}

publish() {
    step "Publishing $PUBLISH_VERSION"
    [[ -f "$DMG_PATH" ]] \
        || die ".dmg not found: $DMG_PATH — run ./build.sh --dmg (or --sign) first"
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || die "$PWD is not inside a git repository — cannot tag or release"
    command -v gh >/dev/null 2>&1 || die "the GitHub CLI (gh) is not installed"
    git remote get-url origin >/dev/null 2>&1 \
        || die "this repository has no 'origin' remote — cannot push the tag"

    local versioned="$BUILD_DIR/$APP_NAME-$VERSION_NUM.dmg"
    cp -f "$DMG_PATH" "$versioned"
    echo "    $versioned"

    git tag -a "$PUBLISH_VERSION" -m "Release $PUBLISH_VERSION"
    git push origin "$PUBLISH_VERSION"
    gh release create "$PUBLISH_VERSION" "$versioned" --verify-tag --generate-notes
}

build_app() {
    step "Building $APP_NAME (Release)"
    local derived="$BUILD_DIR/.derived"
    xcb -project ClipboardMenu.xcodeproj -scheme ClipboardMenu \
        -configuration Release -derivedDataPath "$derived" build

    rm -rf "$APP_PATH"
    ditto "$derived/Build/Products/Release/ClipboardMenu.app" "$APP_PATH"
    echo "    $APP_PATH"
}

mkdir -p "$BUILD_DIR"

if [[ $WANT_SIGN -eq 1 ]]; then
    build_app
    sign_and_notarize
elif [[ $WANT_DMG -eq 1 ]]; then
    build_app
    make_dmg
elif [[ -z "$PUBLISH_VERSION" ]]; then
    build_app
fi

if [[ -n "$PUBLISH_VERSION" ]]; then
    publish
fi

exit 0
