#!/usr/bin/env bash
#
# Copyright (C) 2026 Paolo De Marinis, Juan Miguel Garcia
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Boot-time guard for the Omarchy adapter. The DSDT override is built from the
# BIOS F.13 table; if the firmware identity changes (for example after a BIOS
# update), the override is removed and the boot images are rebuilt, so the next
# boot uses the firmware's own DSDT. The current boot already loaded the old
# table, which is why uninstalling before a BIOS update is still preferred.
set -Eeuo pipefail
export PATH="/usr/bin:/bin"

readonly EXPECTED_BOARD="8E35"
readonly EXPECTED_BIOS="F.13"
readonly AML_TARGET="/etc/initcpio/acpi_override/omen-acpi-dsdt.aml"
readonly HOOK_CONF="/etc/mkinitcpio.conf.d/zz-omen-acpi.conf"
readonly NOTICE="/var/lib/omen-acpi/BIOS-CHANGED.txt"

log() { printf '%s\n' "$*"; logger -t omen-acpi-bios-guard -p user.warning -- "$*" 2>/dev/null || true; }

[[ -e "$AML_TARGET" || -e "$HOOK_CONF" ]] || exit 0

board="$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)"
bios="$(cat /sys/class/dmi/id/bios_version 2>/dev/null || true)"

if [[ "$board" == "$EXPECTED_BOARD" && "$bios" == "$EXPECTED_BIOS" ]]; then
    exit 0
fi

log "Firmware changed (board '$board', BIOS '$bios'; override built for $EXPECTED_BOARD $EXPECTED_BIOS). Removing the DSDT override."
rm -f -- "$AML_TARGET" "$HOOK_CONF"
rmdir --ignore-fail-on-non-empty /etc/initcpio/acpi_override 2>/dev/null || true

if limine-mkinitcpio >/dev/null 2>&1; then
    log "DSDT override removed and boot images rebuilt. Reboot to use the firmware DSDT, then test shutdown again."
else
    log "DSDT override files removed, but rebuilding the boot images failed. Run 'sudo limine-mkinitcpio' manually."
fi

install -D -m 0644 /dev/null "$NOTICE"
printf '%s: BIOS changed to %s (board %s). The OMEN ACPI override built for %s was removed.\n' \
    "$(date '+%F %T')" "$bios" "$board" "$EXPECTED_BIOS" > "$NOTICE"
