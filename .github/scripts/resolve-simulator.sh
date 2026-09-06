#!/bin/bash
#
# Resolves a concrete iPhone simulator UDID on the newest installed iOS
# runtime and fails loudly when there is none.
#
# Why not a hardcoded `-destination 'platform=iOS Simulator,name=iPhone 16'`:
# device names and runtimes belong to the runner image's Xcode, not to this
# repo. When the image drops a device name, a hardcoded destination turns the
# only test job red for a reason unrelated to the code — and the tempting
# "fix" is to loosen the destination until it silently resolves to something
# nobody chose. Resolving by UDID keeps the destination exact, prints which
# device and runtime were actually used, and exits non-zero (with the full
# device list) when the assumption breaks.
#
# Writes `udid` and `device` to $GITHUB_OUTPUT when running under Actions;
# always echoes them so the run log records the toolchain that produced it.

set -euo pipefail

device=$(xcrun simctl list devices available --json | jq -r '
  [ .devices
    | to_entries[]
    | (.key | capture("SimRuntime\\.iOS-(?<maj>[0-9]+)-(?<min>[0-9]+)$") // empty) as $v
    | .value[]
    | select(.isAvailable and (.name | startswith("iPhone")))
    | { major: ($v.maj | tonumber), minor: ($v.min | tonumber), name: .name, udid: .udid }
  ]
  | sort_by(.major, .minor) | reverse
  | (.[0] // empty) as $newest
  | map(select(.major == $newest.major and .minor == $newest.minor))
  | sort_by(.name)
  | (.[0] // empty)
  | "\(.udid)\t\(.name)\tiOS \(.major).\(.minor)"
')

if [ -z "$device" ]; then
  echo "::error::No available iPhone simulator found. The runner image's Xcode" \
       "ships no iOS runtime this job can use — pin a different image or Xcode."
  xcrun simctl list devices available
  exit 1
fi

udid=${device%%$'\t'*}
name_and_os=${device#*$'\t'}

echo "Simulator: ${name_and_os//$'\t'/ — } (${udid})"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "udid=${udid}"
    echo "device=${name_and_os//$'\t'/ — }"
  } >> "$GITHUB_OUTPUT"
fi
