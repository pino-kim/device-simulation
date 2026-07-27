FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://virtio.cfg"

do_configure:append() {
    cat ${UNPACKDIR}/virtio.cfg >> ${B}/.config
    oe_runmake -C ${B} olddefconfig
}
