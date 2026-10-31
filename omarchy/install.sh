#!/usr/bin/env bash
#
# Copyright (C) 2026 Paolo De Marinis, Juan Miguel Garcia
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Omarchy adapter: installs a DSDT override built by scripts/02-build-dsdt.sh
# through mkinitcpio's standard acpi_override hook, then rebuilds Omarchy's
# Limine unified kernel images with limine-mkinitcpio.
#
# Unlike the CachyOS workflow, Omarchy boots unified kernel images (UKI), so the
# override cannot live in a separate Limine test entry: it applies to every
# Omarchy boot. A snapper snapshot is taken first so Limine keeps a bootable
# pre-override entry. Windows and the BIOS are never touched.
set -Eeuo pipefail
umask 022
export PATH="/usr/bin:/bin"

readonly EXPECTED_PRODUCT="OMEN Gaming Laptop 16-ap0xxx"
readonly EXPECTED_BOARD="8E35"
readonly EXPECTED_BIOS="F.13"
readonly S5_OEM_REVISION="0107200a"
readonly COMBINED_OEM_REVISION="0107200b"
readonly AML_TARGET="/etc/initcpio/acpi_override/omen-acpi-dsdt.aml"
readonly HOOK_CONF="/etc/mkinitcpio.conf.d/zz-omen-acpi.conf"
readonly GUARD_TARGET="/usr/local/lib/omen-acpi/bios-guard.sh"
readonly GUARD_UNIT="/etc/systemd/system/omen-acpi-bios-guard.service"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PROBE="$SCRIPT_DIR/../scripts/00-probe-boot.sh"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    printf 'Usage: sudo %s BUILD_ARCHIVE\n' "$0"
    printf '       sudo %s --guard-only\n\n' "$0"
    printf 'BUILD_ARCHIVE is the omen-dsdt-f13-*-build-*.tar.gz created by scripts/02-build-dsdt.sh.\n'
    printf '%s\n' '--guard-only installs only the BIOS-change guard for an existing override.'
}

# Boot service that removes the override automatically if the BIOS changes.
install_guard() {
    install -D -m 0755 "$SCRIPT_DIR/bios-guard.sh" "$GUARD_TARGET"
    install -D -m 0644 "$SCRIPT_DIR/omen-acpi-bios-guard.service" "$GUARD_UNIT"
    systemctl daemon-reload
    systemctl enable omen-acpi-bios-guard.service
    printf 'Installed the BIOS-change guard (omen-acpi-bios-guard.service).\n'
}

[[ $# -eq 1 && "$1" != -h && "$1" != --help ]] || { usage; [[ "${1:-}" == -h || "${1:-}" == --help ]]; exit $?; }
[[ $EUID -eq 0 ]] || die "Run as root (sudo)."

if [[ "$1" == --guard-only ]]; then
    [[ -e "$AML_TARGET" ]] || die "No override is installed; run the full install instead."
    install_guard
    exit 0
fi

archive="$(realpath -- "$1")"
[[ -f "$archive" ]] || die "Build archive not found: $archive"

for cmd in limine-mkinitcpio tar sha256sum od install; do
    command -v "$cmd" >/dev/null 2>&1 || die "Missing command: $cmd (is this Omarchy?)"
done
[[ -f /usr/lib/initcpio/install/acpi_override ]] || die "mkinitcpio acpi_override hook not found"

product="$(cat /sys/class/dmi/id/product_name)"
board="$(cat /sys/class/dmi/id/board_name)"
bios="$(cat /sys/class/dmi/id/bios_version)"
[[ "$product" == "$EXPECTED_PRODUCT" && "$board" == "$EXPECTED_BOARD" && "$bios" == "$EXPECTED_BIOS" ]] \
    || die "Machine mismatch: '$product' / '$board' / '$bios' (expected $EXPECTED_PRODUCT / $EXPECTED_BOARD / $EXPECTED_BIOS)"

[[ ! -e "$AML_TARGET" && ! -e "$HOOK_CONF" ]] \
    || die "An OMEN ACPI override is already installed. Run omarchy/uninstall.sh first."

if [[ -x "$PROBE" ]]; then
    "$PROBE" --require-stock >/dev/null || die "The running boot is not a clean stock boot."
fi

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
tar -xzf "$archive" -C "$work"
build_dir="$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -1)"
[[ -f "$build_dir/DSDT.aml" && -f "$build_dir/SHA256SUMS" ]] || die "Archive does not contain DSDT.aml and SHA256SUMS"
(cd "$build_dir" && sha256sum --quiet -c SHA256SUMS) || die "Build archive checksum verification failed"

# ACPI table header: signature at offset 0, OEM revision (little-endian u32) at offset 24.
signature="$(head -c 4 "$build_dir/DSDT.aml")"
revision="$(od -An -tx4 -j24 -N4 "$build_dir/DSDT.aml" | tr -d ' ')"
[[ "$signature" == "DSDT" ]] || die "DSDT.aml has an invalid table signature"
case "$revision" in
    "$S5_OEM_REVISION") variant="s5" ;;
    "$COMBINED_OEM_REVISION") variant="combined" ;;
    *) die "Unexpected DSDT OEM revision 0x$revision" ;;
esac
printf 'Verified %s override (OEM revision 0x%s).\n' "$variant" "$revision"

if command -v snapper >/dev/null 2>&1; then
    printf 'Creating a snapper snapshot before installing...\n'
    snapper -c root create -d "before omen-acpi $variant override" || printf 'Warning: snapshot failed; continuing.\n' >&2
fi

install -D -m 0644 "$build_dir/DSDT.aml" "$AML_TARGET"
printf '# Added by omen-acpi omarchy/install.sh: load %s early.\nHOOKS+=(acpi_override)\n' "$AML_TARGET" > "$HOOK_CONF"
chmod 0644 "$HOOK_CONF"

printf 'Rebuilding Omarchy boot images...\n'
if ! limine-mkinitcpio; then
    rm -f -- "$AML_TARGET" "$HOOK_CONF"
    limine-mkinitcpio || true
    die "Boot image rebuild failed; the override was removed again."
fi

install_guard

printf '\nInstalled the %s DSDT override. Reboot, then verify with:\n' "$variant"
printf '  sudo scripts/00-probe-boot.sh --human   (expect revision 0x%s)\n' "$revision"
printf 'Remove it at any time with: sudo omarchy/uninstall.sh\n'
