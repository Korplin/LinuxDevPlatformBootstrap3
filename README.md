One-liner the student runs

wget -O devplatformbootstrap.sh https://raw.githubusercontent.com/Korplin/LinuxDevPlatformBootstrap3/main/devplatformbootstrap.sh && bash devplatformbootstrap.sh

Manual steps after the playbook finishes
Reboot the machine.
sudo reboot
Log in again.

This is needed so these changes actually take effect:

KDE Plasma / SDDM starts cleanly
docker, libvirt, and kvm group membership activates
zsh becomes the user’s default shell
NVIDIA / AMD / Intel / VM guest drivers load properly
Cursor appears in the KDE application menu

Tiny caveat goblin 🛠️: the Cursor AppImage URL installs whatever Cursor currently publishes as “latest,” so future Cursor changes could affect that one part. Everything else is pinned to apt repositories or Debian packages.
