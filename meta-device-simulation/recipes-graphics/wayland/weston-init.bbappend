FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:raspberrypi4-64 = " file://weston-autolaunch.ini"

do_install:append:raspberrypi4-64() {
    cat ${UNPACKDIR}/weston-autolaunch.ini >> \
        ${D}${sysconfdir}/xdg/weston/weston.ini
}
