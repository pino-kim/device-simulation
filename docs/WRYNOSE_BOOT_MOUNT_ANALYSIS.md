# Wrynose Raspberry Pi 4 `/boot` mount analysis

## Symptom

The Wrynose image mounts its root filesystem from `/dev/mmcblk1p2` under the
QEMU `raspi4b` machine, but systemd previously waited about 90 seconds for a
different device:

```text
Timed out waiting for device /dev/mmcblk0p1.
Dependency failed for /boot.
Dependency failed for Local File Systems.
```

This is independent of the PL011/Bluetooth console problem. The root
filesystem and SD emulation are already working when this message appears.

## Where `/dev/mmcblk0p1` came from

The stock rootfs created by `base-files` does not contain an active `/boot`
entry. The stock meta-raspberrypi WKS describes the boot partition as follows:

```text
part /boot --source bootimg-partition --ondisk mmcblk0 --fstype=vfat ...
```

During WIC assembly, `DirectPlugin.update_fstab()` adds entries for mounted
partitions other than `/`. Without `--use-uuid` or `--use-label`, it combines
the WKS disk name and partition number. For an MMC disk it inserts `p` before
the number, producing:

```text
/dev/mmcblk0p1  /boot  vfat  defaults  0  0
```

The QEMU BCM2711 model enumerates the attached SD image as `mmcblk1`, so its
actual partitions are `/dev/mmcblk1p1` and `/dev/mmcblk1p2`. The WKS disk name
therefore does not describe the runtime device name in both environments.

## Why Kirkstone appeared unaffected

The official Kirkstone meta-raspberrypi WKS also uses `--ondisk mmcblk0`, and
the Kirkstone OE-Core WIC implementation performs the same device-name fstab
generation. The issue was therefore present in the image format rather than
introduced by Wrynose.

The old automated harness allowed 300 seconds for boot and printed only the
last six QEMU output lines. A 90-second systemd device timeout could expire and
the later login/test could still pass without exposing the earlier warning.
Tests using `init=/bin/sh` bypassed systemd and fstab processing entirely. In
addition, the Kirkstone DTB left the PL011 console usable, so login remained
possible after the mount timeout. Wrynose exposed the situation more clearly
because its stock DTB caused a separate PL011/Bluetooth ownership problem.

## Fix

`sdimage-raspberrypi-portable.wks` adds `--use-uuid` to `/boot`. WIC then uses
the generated FAT filesystem UUID in the final fstab instead of a kernel
enumeration-dependent path:

```text
UUID=F244-890E  /boot  vfat  defaults  0  0
```

The UUID in the tested fstab matched the boot filesystem UUID reported by
`blkid`. This keeps one WIC usable when the same SD partition is enumerated as
`mmcblk0p1` on hardware and `mmcblk1p1` in QEMU.

The test harness also derives the rootfs byte offset from the WIC partition
table. This replaces the Kirkstone-specific fixed sector and prevents host-side
test injection from targeting the wrong location when partition sizes change.

## Validation

- Yocto Wrynose 6.0.2/Linux 6.18.33 completed all 5,716 build tasks.
- The final WIC fstab used the FAT filesystem UUID for `/boot`.
- The fstab UUID and the actual FAT UUID matched.
- QEMU 11.0.3 mounted `/boot` without waiting for `/dev/mmcblk0p1`.
- Login, guest test execution, `/boot` unmount, and poweroff completed in about
  18 seconds.
- The complete raspi4b harness reported `PASS: T3 raspi4b 테스트 통과`.
