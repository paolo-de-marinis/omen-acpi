# Omarchy adapter

This directory adapts the OMEN ACPI Toolkit to [Omarchy](https://omarchy.org/),
which boots Limine **unified kernel images (UKI)** built by `limine-mkinitcpio`
instead of the CachyOS kernel entries the main workflow expects.

The ACPI analysis, collection, transformation and verification are the
upstream scripts, unchanged. Only the installation step differs: the verified
`DSDT.aml` is loaded through mkinitcpio's standard `acpi_override` hook and the
UKI is rebuilt.

## Tested on

| Property    | Value                                         |
| ----------- | --------------------------------------------- |
| DMI product | `OMEN Gaming Laptop 16-ap0xxx`                |
| Mainboard   | `8E35`                                        |
| BIOS        | `F.13`                                        |
| GPU         | NVIDIA GeForce RTX 5060 Laptop GPU (hybrid)   |
| Driver      | `nvidia-open-dkms` 615.78.08                  |
| OS          | Omarchy 4.0.6, kernel `7.2.8-9-omarchy`       |
| Variant     | `s5`                                          |

Before the override, a shutdown left the laptop warm with fans off, draining
15–50 % of the battery in 25–35 minutes (Linux kernels 7.2 and LTS 6.18, BIOS
F.13 is the latest). Hibernation showed the same symptom. Windows shut down
normally. With the `s5` override, the battery went from 92 % to 91 % over 35
minutes powered off and the laptop stayed cool.

## Differences from the CachyOS workflow

- **No separate test entry.** A UKI embeds its initramfs, so the override
  applies to every Omarchy boot. `install.sh` creates a snapper snapshot first;
  its Limine snapshot entry boots without the override.
- **Kernel updates keep the override.** The hook lives in
  `/etc/mkinitcpio.conf.d/`, so every UKI rebuild includes it.
- **Windows and the BIOS are untouched.** The table is replaced in memory by
  the Linux kernel only.

## Usage

```bash
sudo pacman -S --needed acpica

# 1. Confirm a clean stock boot
sudo scripts/00-probe-boot.sh --human

# 2. Collect the local DSDT (kept outside the repository)
mkdir -p ~/.local/share/omen-acpi
OMEN_ACPI_OUTPUT_DIR=~/.local/share/omen-acpi ./scripts/01-collect-acpi.sh

# 3. Build and verify the s5 variant (no system changes)
OMEN_ACPI_OUTPUT_DIR=~/.local/share/omen-acpi \
  ./scripts/02-build-dsdt.sh s5 ~/.local/share/omen-acpi/omen-ap0006sl-acpi-source-*.tar.gz

# 4. Install and rebuild the Omarchy boot images
sudo omarchy/install.sh ~/.local/share/omen-acpi/omen-dsdt-f13-s5-build-*.tar.gz

# 5. Reboot and confirm the override (expect OEM revision 0107200A)
journalctl -b -k | grep -E 'Table Upgrade|ACPI: DSDT'
```

Remove it at any time:

```bash
sudo omarchy/uninstall.sh
```

**Before a BIOS update**, uninstall first: the override is built from the F.13
table and must not be loaded on other firmware.

## BIOS-change guard

`install.sh` also enables `omen-acpi-bios-guard.service`. On every boot it
compares the board and BIOS version with `8E35` / `F.13`; if they differ, it
removes the override, rebuilds the boot images and writes a notice to
`/var/lib/omen-acpi/BIOS-CHANGED.txt` and the journal
(`journalctl -t omen-acpi-bios-guard`). The boot on which the change is detected
has already loaded the old table, so the guard is a safety net, not a
replacement for uninstalling before updating the BIOS.

For an override installed before the guard existed:

```bash
sudo omarchy/install.sh --guard-only
```

`uninstall.sh` removes the guard together with the override.

## Recovery

If Omarchy does not boot after installing, pick the most recent snapshot entry
in the Limine menu (it predates the override), then run
`sudo omarchy/uninstall.sh`.

## Safety

Read the upstream [README](../README.md) safety model. This adapter has been
validated on one machine only. Never commit or share the collected DSDT or the
built AML: they are HP firmware and contain machine-derived data.
