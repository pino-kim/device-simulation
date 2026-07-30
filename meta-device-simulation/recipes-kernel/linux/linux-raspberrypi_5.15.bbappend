FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://virtio.cfg"

do_configure:append() {
    cat ${WORKDIR}/virtio.cfg >> ${B}/.config
    cd ${B}
    oe_runmake olddefconfig
}
