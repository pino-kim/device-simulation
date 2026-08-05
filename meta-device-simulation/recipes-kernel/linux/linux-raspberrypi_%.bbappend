FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://virtio.cfg"

# Keep the stock Raspberry Pi device trees. Only add the built-in options
# required by the QEMU virt regression harness.
do_configure:append() {
    cat ${UNPACKDIR}/virtio.cfg >> ${B}/.config
    oe_runmake -C ${B} olddefconfig
}
