#!/usr/bin/env python3
"""Boot patched raspi4b QEMU and verify guest/host ICMP over a TAP."""

from __future__ import annotations

import argparse
import pathlib
import shlex
import subprocess
import sys

import pexpect


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--qemu", required=True)
    parser.add_argument("--kernel", required=True)
    parser.add_argument("--dtb", required=True)
    parser.add_argument("--disk", required=True)
    parser.add_argument("--tap", required=True)
    parser.add_argument("--host-ip", required=True)
    parser.add_argument("--guest-cidr", required=True)
    parser.add_argument("--guest-mac", required=True)
    parser.add_argument(
        "--network-device",
        choices=("genet", "virtio-net-pci"),
        default="genet",
    )
    parser.add_argument("--guest-iface", default="eth0")
    parser.add_argument("--log", required=True)
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()

    guest_ip = args.guest_cidr.split("/", 1)[0]
    command = [
        args.qemu,
        "-M", "raspi4b",
        "-cpu", "cortex-a72",
        "-m", "2G",
        "-smp", "4",
        "-display", "none",
        "-monitor", "none",
        "-serial", "stdio",
        "-no-reboot",
        "-kernel", args.kernel,
        "-dtb", args.dtb,
        "-drive", f"file={args.disk},format=raw,if=sd",
        "-append",
        "earlycon=pl011,mmio32,0xfe201000 console=ttyAMA0,115200 "
        "root=/dev/mmcblk1p2 rootwait rw",
    ]
    if args.network_device == "genet":
        command.extend([
            "-nic",
            f"tap,model=bcm2838-genet,ifname={args.tap},script=no,"
            f"downscript=no,mac={args.guest_mac}",
            "-trace", "enable=bcm2838_genet_tx_request",
            "-trace", "enable=bcm2838_genet_tx",
            "-trace", "enable=bcm2838_genet_receive",
            "-trace", "enable=bcm2838_genet_rx_dma_ring_active",
            "-trace", "enable=bcm2838_genet_rx_dma",
            "-trace", "enable=bcm2838_genet_irq",
            "-trace", "enable=bcm2838_genet_phy_update_link",
        ])
    else:
        command.extend([
            "-netdev",
            f"tap,id=pcienet0,ifname={args.tap},script=no,downscript=no",
            "-device",
            f"virtio-net-pci,bus=pcie.1,netdev=pcienet0,"
            f"mac={args.guest_mac},disable-modern=off,disable-legacy=on,"
            "vectors=0",
        ])

    print("QEMU command:", shlex.join(command))
    log_path = pathlib.Path(args.log)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    with log_path.open("w", encoding="utf-8") as logfile:
        child = pexpect.spawn(
            command[0], command[1:], encoding="utf-8",
            codec_errors="replace", timeout=args.timeout,
        )
        child.logfile_read = logfile
        child.logfile_send = logfile
        try:
            state = child.expect([
                r"root@[^#\r\n]*# ",
                r"\r\n[^ \r\n]+:~# ",
                r"login:",
            ])
            if state == 2:
                child.sendline("root")
                child.expect([r"root@[^#\r\n]*# ", r"# "])

            guest_command = (
                f"ip link set {shlex.quote(args.guest_iface)} down && "
                f"ip link set {shlex.quote(args.guest_iface)} address "
                f"{shlex.quote(args.guest_mac)} && "
                f"ip link set {shlex.quote(args.guest_iface)} up && "
                f"ip addr flush dev {shlex.quote(args.guest_iface)} && "
                f"ip addr add {shlex.quote(args.guest_cidr)} "
                f"dev {shlex.quote(args.guest_iface)} && "
                "sleep 5 && "
                f"ping -c 3 -W 2 {shlex.quote(args.host_ip)}; "
                "rc=$?; echo CODEX_GUEST_PING_RC=$rc"
            )
            child.sendline(guest_command)
            child.expect(r"CODEX_GUEST_PING_RC=(\d+)")
            guest_rc = int(child.match.group(1))
            if guest_rc:
                print("Guest -> Host ping failed", file=sys.stderr)
                child.sendline(
                    f"for f in /sys/class/net/{shlex.quote(args.guest_iface)}"
                    "/statistics/*; do echo $f=$(cat $f); done; "
                    "cat /proc/interrupts; echo __CODEX_GENET_DIAG_DONE__"
                )
                child.expect(r"__CODEX_GENET_DIAG_DONE__")
                child.expect(r"__CODEX_GENET_DIAG_DONE__")

            host_ping = subprocess.run(
                ["ping", "-c", "3", "-W", "2", guest_ip],
                check=False,
            )
            if host_ping.returncode:
                print("Host -> Guest ping failed", file=sys.stderr)
                child.close(force=True)
                return 4
            if guest_rc:
                child.close(force=True)
                return 3

            child.sendline("sync; poweroff -f")
            child.expect(pexpect.EOF)
        except (pexpect.TIMEOUT, pexpect.EOF) as exc:
            print(f"TAP ping automation failed: {exc}", file=sys.stderr)
            child.close(force=True)
            return 2

    print(f"PASS: Guest({guest_ip}) <-> Host({args.host_ip}) 양방향 ping")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
