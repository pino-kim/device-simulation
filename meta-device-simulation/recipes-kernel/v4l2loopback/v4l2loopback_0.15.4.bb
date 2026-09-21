SUMMARY = "V4L2 loopback video device"
DESCRIPTION = "Out-of-tree V4L2 driver used to provide a synthetic camera device"
HOMEPAGE = "https://github.com/v4l2loopback/v4l2loopback"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=b234ee4d69f5fce4486a80fdaf4a4263"

SRC_URI = "git://github.com/v4l2loopback/v4l2loopback.git;protocol=https;branch=main"
# Commit referenced by the signed v0.15.4 tag. Pin the commit rather than the
# annotated tag object so BitBake's source revision is unambiguous.
SRCREV = "0f9ee86760b7f2bea174b7e3e7a1d38845da0ab4"

inherit module

EXTRA_OEMAKE += "KERNEL_DIR=${STAGING_KERNEL_DIR}"

MAKE_TARGETS = "v4l2loopback.ko"
MODULES_INSTALL_TARGET = "install"

KERNEL_MODULE_AUTOLOAD += "v4l2loopback"
KERNEL_MODULE_PROBECONF += "v4l2loopback"
module_conf_v4l2loopback = "options v4l2loopback video_nr=10 card_label=QEMU-Virtual-Camera exclusive_caps=1 max_buffers=4"
