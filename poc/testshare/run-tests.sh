#!/bin/sh
# 게스트(에뮬된 보드) 안에서 자동 실행되는 테스트 스크립트.
# ★ 이 파일과 같은 폴더(testshare/)에 당신의 앱 바이너리를 두고 여기서 호출하면
#   이미지 재빌드 없이 "바이너리만 교체 → 자동테스트"가 됩니다.
echo "=== 게스트 자동테스트 시작 ==="
echo "uname : $(uname -a)"
echo "arch  : $(uname -m)"
echo "distro: $(cat /etc/os-release 2>/dev/null | grep PRETTY | cut -d= -f2)"
echo
test_rc=0

# --- 예시: 교체 대상 앱 바이너리 실행 지점 ---
if [ -x /mnt/host/myapp ]; then
    echo "[myapp 실행]"
    /mnt/host/myapp --selftest
    test_rc=$?
    echo "myapp exit=$test_rc"
else
    echo "(myapp 없음 — testshare/에 바이너리를 두면 여기서 실행됩니다)"
fi

echo
if [ "$test_rc" -eq 0 ]; then
    echo "PASS: 테스트 통과"
else
    echo "FAIL: myapp selftest 실패"
fi
echo "=== 게스트 자동테스트 종료 ==="
exit "$test_rc"
