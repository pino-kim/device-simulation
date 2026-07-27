#!/bin/sh
# raspi4b(BCM2711) 게스트 안에서 실행되는 테스트. 결과는 result.txt 로 회수됨.
# ★ 앱 바이너리는 이 폴더(testfiles/)에 myapp 로 넣으면 여기서 실행된다.
echo "=== [raspi4b/T3] 게스트 자동테스트 시작 ==="
echo "uname   : $(uname -a)"
echo "machine : $(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')"
echo "-- SoC 커널 노드(BCM2711 확인) --"
ls /proc/device-tree/soc/ 2>/dev/null | grep -iE "mailbox|dma|gpio|mmc|serial" | tr '\n' ' '; echo
echo "-- MMC/블록 디바이스 --"
ls /dev/mmcblk* 2>/dev/null | tr '\n' ' '; echo
test_rc=0

if [ -x /root/hosttest/myapp ]; then
    echo "[myapp 실행]"
    /root/hosttest/myapp --selftest
    test_rc=$?
    echo "myapp exit=$test_rc"
else
    echo "(myapp 없음 — testfiles/에 바이너리를 두면 여기서 실행)"
fi

if [ "$test_rc" -eq 0 ]; then
    echo "PASS: T3 raspi4b 테스트 통과"
else
    echo "FAIL: myapp selftest 실패"
fi
echo "=== 종료 ==="
exit "$test_rc"
