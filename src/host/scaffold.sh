#!/bin/bash
#
# These scripts will create a series of privileged containers for convenience,
# but will eventually move to root-based unprivileged containers.
#
cd ~root
# Automatically adapt to host architecture
hostArch=$(uname -m)
targetArch="unsupported"
case $hostArch in
	"x86_64" | "amd64")
		targetArch="amd64"
		;;
	"arm64" | "armv8l" | "aarch64")
		targetArch="arm64"
		;;
esac
# Fetch the LXC container subnet
lxcSubNet="$(ip addr show lxcbr0 | grep "inet " | awk -F ' *|:' '/inet/{print $3}' | cut -d'/' -f1 | cut -d'.' -f1,2,3)"
lxcSubNet=${lxcSubNet:-10.0.3}
# Define names for the containers
names=( "web" "mix" "pod" )
# web: Web servers, static files, etc
# mix: Mixnet access, port forwarders for mixnet exposure, etc
# pod: Actual host for running Docker/Podman containers
startOrder=1
for name in ${names[@]}; do
	# Set the config file name to write to
	lxcPath="${PREFIX}/var/lib/lxc/${name}"
	lxcConf="${lxcPath}/config"
	lxcRoot="${lxcPath}/rootfs"
	# In this file, slim Debian containers are being created.
	if [ ! -f "gel.zip" ]; then
		curl -Lo "gel.zip" "https://github.com/ltgcgo/gel/releases/latest/download/slimdeb.zip"
	fi
	# Create seperate LXC containers for different purposes
	lxc-create -t download -n "${name}" -- --dist debian --release bookworm --arch $targetArch
	# Set autostart
	echo -e "\nlxc.start.order = ${startOrder}\nlxc.start.auto = 1\nlxc.start.delay = 4" >> "${lxcConf}"
	# Enable FUSE
	echo -e "lxc.mount.entry = /dev/fuse dev/fuse none bind,create=file,rw 0 0" >> "${lxcConf}"
	# Assign static IPs
	echo -e "lxc.net.0.ipv4.address = ${lxcSubNet}.$((startOrder + 4))/24\nlxc.net.0.ipv4.gateway = auto" >> "${lxcConf}"
	# Copy the Gel setup file into the container
	cp -v gel.zip "${lxcRoot}/root/gel.zip"
	# Configure Gel
	lxc-attach -n web -u 0 -g 0 -- "bash <(curl -Ls https://github.com/ltgcgo/gel/releases/latest/download/install.sh)"
	# Start the container
	lxc-start -n "${name}"
	# Increase the start order
	startOrder=$(($startOrder+1))
done
# Enable TUN device in "mix"
echo -e "lxc.mount.entry = /dev/net dev/net none bind,create=dir\nlxc.cgroup2.devices.allow = c 10:200 rwm" >> "${lxcConf}"
exit