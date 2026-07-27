#!/usr/bin/env python3
"""Drive a serial-only QEMU boot and propagate the guest test result."""

from __future__ import annotations

import argparse
import pathlib
import shlex
import sys

import pexpect


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--qemu", required=True)
    parser.add_argument("--kernel", required=True)
    parser.add_argument("--disk", required=True)
    parser.add_argument("--dtb")
    parser.add_argument("--share")
    parser.add_argument("--mode", choices=("virt", "raspi4b"), required=True)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    if args.mode == "virt":
        if not args.share:
            parser.error("--share is required for virt mode")
        command = [
            args.qemu, "-M", "virt", "-cpu", "cortex-a72", "-m", "2048",
            "-smp", "4", "-nographic", "-no-reboot", "-kernel", args.kernel,
            "-append", "root=/dev/vda2 rootwait rw console=ttyAMA0 "
            "earlycon=pl011,0x9000000",
            "-drive", f"file={args.disk},format=raw,if=none,id=hd0",
            "-device", "virtio-blk-pci,drive=hd0",
            "-fsdev", f"local,id=fs0,path={args.share},security_model=none",
            "-device", "virtio-9p-pci,fsdev=fs0,mount_tag=hostshare",
        ]
        test_command = (
            "mkdir -p /mnt/host && "
            "mount -t 9p -o trans=virtio,version=9p2000.L "
            "hostshare /mnt/host && "
            "sh /mnt/host/run-tests.sh > /mnt/host/result.txt 2>&1; "
            "rc=$?; echo CODEX_TEST_RC=$rc"
        )
    else:
        if not args.dtb:
            parser.error("--dtb is required for raspi4b mode")
        command = [
            args.qemu, "-M", "raspi4b", "-cpu", "cortex-a72", "-m", "2G",
            "-nographic", "-no-reboot", "-kernel", args.kernel,
            "-dtb", args.dtb,
            "-drive", f"file={args.disk},format=raw,if=sd",
            "-append", "console=ttyAMA1,115200 earlycon=pl011,0xfe201000 "
            "root=/dev/mmcblk1p2 rootwait rw "
            "init=/root/hosttest/codex-init.sh",
        ]
        test_command = (
            "sh /root/hosttest/run-tests.sh "
            "> /root/hosttest/result.txt 2>&1; "
            "rc=$?; echo CODEX_TEST_RC=$rc"
        )

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
            if args.mode == "raspi4b":
                child.expect(pexpect.EOF)
                test_rc = 0
                print("Guest init completed and QEMU powered down")
            else:
                boot_state = child.expect(
                    [
                        r"login:",
                        r"root@[^#\r\n]*# ",
                        r"\r\n[^ \r\n]+:~# ",
                    ]
                )
                if boot_state == 0:
                    child.sendline("root")
                    child.expect([r"root@[^#\r\n]*# ", r"# "])
                    print("Guest login succeeded")
                else:
                    print("Guest serial auto-login succeeded")
                child.sendline(test_command)
                child.expect(r"CODEX_TEST_RC=(\d+)")
                test_rc = int(child.match.group(1))
                child.sendline("sync; poweroff -f")
                child.expect(pexpect.EOF)
        except (pexpect.TIMEOUT, pexpect.EOF) as exc:
            print(f"QEMU automation failed: {exc}", file=sys.stderr)
            child.close(force=True)
            return 2

    if test_rc:
        print(f"Guest test failed with exit code {test_rc}", file=sys.stderr)
        return test_rc
    print("Guest test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
