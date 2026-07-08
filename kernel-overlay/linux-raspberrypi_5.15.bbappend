# PoC: QEMU -M virt 에서 보드 rootfs를 부팅하기 위해 virtio/9p 드라이버를 커널에 built-in으로 추가
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://virtio.cfg"

# 레시피 종류와 무관하게 확실히 적용: do_configure 후 .config에 병합하고 olddefconfig로 의존성 정리
do_configure:append() {
    cat ${WORKDIR}/virtio.cfg >> ${B}/.config
    cd ${B}
    oe_runmake olddefconfig
}
