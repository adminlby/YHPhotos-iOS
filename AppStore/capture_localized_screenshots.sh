#!/bin/zsh

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <language> <locale>" >&2
    exit 64
fi

language="$1"
locale="$2"
system_language="$language"
if [[ "$language" == "zh-Hant" ]]; then
    # The project does not yet ship a zh-Hant string-catalog locale. Keep the
    # source-language UI instead of allowing iOS to fall back to English.
    system_language="zh-Hans"
fi
iphone_device="122D5648-D201-4FDC-9661-28ECF78DD0A3"
ipad_device="3AF19CCC-5EDF-48A0-9CA4-612C614A7E74"
bundle_id="com.yhphotos.app"
app_path="/tmp/YHPhotosDerived/Build/Products/Debug-iphonesimulator/YHPhotos.app"
root_dir="${0:A:h}"
iphone_output="${root_dir}/Raw-${language}"
ipad_output="${root_dir}/Raw-iPad-${language}"

mkdir -p "$iphone_output" "$ipad_output"

xcrun simctl install "$iphone_device" "$app_path"
xcrun simctl install "$ipad_device" "$app_path"

capture() {
    local device="$1"
    local screen="$2"
    local destination="$3"

    xcrun simctl launch --terminate-running-process "$device" "$bundle_id" \
        -AppStoreDemo \
        -AppStoreScreen "$screen" \
        -AppStoreDemoLanguage "$language" \
        -AppleLanguages "(${system_language})" \
        -AppleLocale "$locale"
    sleep 3
    xcrun simctl io "$device" screenshot --type=png "$destination"
}

capture "$iphone_device" discover "$iphone_output/01-discover.png"
capture "$iphone_device" aviation "$iphone_output/02-aviation.png"
capture "$iphone_device" photo "$iphone_output/03-photo.png"
capture "$iphone_device" map "$iphone_output/04-map.png"
capture "$iphone_device" tools "$iphone_output/05-tools.png"
capture "$iphone_device" inspector "$iphone_output/06-inspector.png"

capture "$ipad_device" discover "$ipad_output/01-discover.png"
capture "$ipad_device" photo "$ipad_output/02-photo.png"
capture "$ipad_device" tools "$ipad_output/03-tools.png"

echo "Captured localized screenshots for ${language}."
