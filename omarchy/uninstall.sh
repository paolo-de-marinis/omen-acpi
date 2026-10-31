#!/usr/bin/env bash
#
# Copyright (C) 2026 Paolo De Marinis, Juan Miguel Garcia
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Omarchy adapter: removes the DSDT override installed by omarchy/install.sh
# and rebuilds Omarchy's boot images so the firmware's original DSDT is used.
set -Eeuo pipefail
export PATH="/usr/bin:/bin"

readonly AML_TARGET="/etc/initcpio/acpi_override/omen-acpi-dsdt.aml"
readonly HOOK_CONF="/etc/mkinitcpio.conf.d/zz-omen-acpi.conf"

[[ $EUID -eq 0 ]] || { printf 'ERROR: Run as root (sudo).\n' >&2; exit 1; }

if [[ -e /etc/systemd/system/omen-acpi-bios-guard.service ]]; then
    systemctl disable omen-acpi-bios-guard.service 2>/dev/null || true
    rm -f /etc/systemd/system/omen-acpi-bios-guard.service
    rm -rf /usr/local/lib/omen-acpi
    systemctl daemon-reload
    printf 'Removed the BIOS-change guard.\n'
fi

if [[ ! -e "$AML_TARGET" && ! -e "$HOOK_CONF" ]]; then
    printf 'No OMEN ACPI override is installed.\n'
    exit 0
fi

rm -f -- "$AML_TARGET" "$HOOK_CONF"
rmdir --ignore-fail-on-non-empty /etc/initcpio/acpi_override 2>/dev/null || true

printf 'Rebuilding Omarchy boot images without the override...\n'
limine-mkinitcpio
printf '\nRemoved. Reboot to return to the firmware DSDT.\n'
