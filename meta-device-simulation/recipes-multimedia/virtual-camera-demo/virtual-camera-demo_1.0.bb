SUMMARY = "V4L2 loopback and Wayland camera demonstration scripts"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://virtual-camera-feed \
           file://virtual-camera-preview \
"

S = "${UNPACKDIR}"

DEPENDS = "gstreamer1.0 gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad"

# This script-only recipe has no ELF linkage from which package QA can infer the
# dynamically split GStreamer plugin relationship. DEPENDS and RDEPENDS above
# deliberately describe the build/runtime sides, respectively.
INSANE_SKIP:${PN} += "build-deps"

RDEPENDS:${PN} = "bash kmod \
    gstreamer1.0 \
    gstreamer1.0-plugins-base-videotestsrc \
    gstreamer1.0-plugins-base-videoconvertscale \
    gstreamer1.0-plugins-good-video4linux2 \
    gstreamer1.0-plugins-bad-waylandsink \
"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/virtual-camera-feed ${D}${bindir}/
    install -m 0755 ${UNPACKDIR}/virtual-camera-preview ${D}${bindir}/
}
