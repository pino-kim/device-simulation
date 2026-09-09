WKS_FILE:raspberrypi4-64 = "sdimage-raspberrypi-portable.wks"

# Exercise a software-rendered Wayland desktop over the QEMU PCIe
# virtio-gpu device.  The compositor uses DRM/KMS for scanout and Pixman
# for rendering, so emulated V3D acceleration is not required.
IMAGE_FEATURES:append:raspberrypi4-64 = " weston"

# Keep the Weston diagnostic clients explicit: these are used to validate
# surface composition, continuous SHM updates, EGL, and presentation timing.
IMAGE_INSTALL:append:raspberrypi4-64 = " weston-examples"

# Provide userspace erase/read/write tools for QEMU SPI NOR validation.
IMAGE_INSTALL:append:raspberrypi4-64 = " mtd-utils"
