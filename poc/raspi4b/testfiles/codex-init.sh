#!/bin/sh
# QEMU raspi4b의 PID 1로 실행해 로그인/getty 없이 T3를 완료한다.

mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true

sh /root/hosttest/run-tests.sh > /root/hosttest/result.txt 2>&1
rc=$?
cat /root/hosttest/result.txt > /dev/ttyAMA1
echo "CODEX_TEST_RC=$rc" > /dev/ttyAMA1
sync
poweroff -f
while :; do sleep 60; done
