FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://virtio.cfg"
DEPENDS:append = " dtc-native"

QEMU_CONSOLE_DTB = "bcm2711-rpi-4-b-qemu-console.dtb"

# Keep the stock Raspberry Pi device trees. Only add the built-in options
# required by the QEMU virt regression harness.
do_configure:append() {
    cat ${UNPACKDIR}/virtio.cfg >> ${B}/.config
    oe_runmake -C ${B} olddefconfig
}

do_compile:append() {
    source_dtb="${B}/arch/${ARCH}/boot/dts/broadcom/bcm2711-rpi-4-b.dtb"
    qemu_dtb="${B}/arch/${ARCH}/boot/dts/broadcom/${QEMU_CONSOLE_DTB}"

    install -m 0644 "$source_dtb" "$qemu_dtb"
    ${STAGING_BINDIR_NATIVE}/fdtput -t s "$qemu_dtb" \
        /aliases serial0 /soc/serial@7e201000
    ${STAGING_BINDIR_NATIVE}/fdtput -t s "$qemu_dtb" \
        /aliases serial1 /soc/serial@7e215040
    ${STAGING_BINDIR_NATIVE}/fdtput -t s "$qemu_dtb" \
        /chosen stdout-path serial0:115200n8
    ${STAGING_BINDIR_NATIVE}/fdtput -t s "$qemu_dtb" \
        /soc/serial@7e201000/bluetooth status disabled
}

do_install:append() {
    install -m 0644 \
        "${B}/arch/${ARCH}/boot/dts/broadcom/${QEMU_CONSOLE_DTB}" \
        "${D}/${KERNEL_DTBDEST}/${QEMU_CONSOLE_DTB}"
}

do_deploy:append() {
    qemu_dtb_deploydir="${DEPLOYDIR}"
    if [ -n "${KERNEL_DEPLOYSUBDIR}" ]; then
        qemu_dtb_deploydir="${DEPLOYDIR}/${KERNEL_DEPLOYSUBDIR}"
    fi
    install -d "$qemu_dtb_deploydir"
    install -m 0644 \
        "${D}/${KERNEL_DTBDEST}/${QEMU_CONSOLE_DTB}" \
        "$qemu_dtb_deploydir/${QEMU_CONSOLE_DTB}"
}
