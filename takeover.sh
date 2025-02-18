#!/bin/sh
set -e

TO=/takeover
OLD_INIT=$(readlink /proc/1/exe)
PORT=80

cd "$TO"

wget -qO- https://www.busybox.net/downloads/binaries/1.26.2-defconfig-multiarch/busybox-x86_64 > ./busybox && \
    echo '79b3c42078019db853f499852dac831afda935acf9df4c748c3bab914f1cf298  busybox' | sha256sum -c || exit 1
chmod +x ./busybox

if [ ! -e fakeinit ]; then
    ./busybox echo "Please compile fakeinit.c first"
    exit 1
fi

./busybox echo "Setting up target filesystem..."
./busybox rm -f etc/mtab
./busybox ln -s /proc/mounts etc/mtab
./busybox mkdir -p old_root

./busybox echo "Mounting pseudo-filesystems..."
./busybox mount -t tmpfs tmp tmp
./busybox mount -t proc proc proc
./busybox mount -t sysfs sys sys
if ! ./busybox mount -t devtmpfs dev dev; then
    ./busybox mount -t tmpfs dev dev
    ./busybox cp -a /dev/* dev/
    ./busybox rm -rf dev/pts
    ./busybox mkdir dev/pts
fi
./busybox mount --bind /dev/pts dev/pts

TTY="$(./busybox tty)"

./busybox echo "Checking and switching TTY..."

exec <"${TO}/${TTY}" >"${TO}/${TTY}" 2>"${TO}/${TTY}"

./busybox echo "Preparing init..."
./busybox cat >tmp/${OLD_INIT##*/} <<EOF
#!${TO}/busybox sh

exec <"${TO}/${TTY}" >"${TO}/${TTY}" 2>"${TO}/${TTY}"
cd "${TO}"

./busybox echo "Init takeover successful"
./busybox echo "Pivoting root..."
./busybox mount --make-rprivate /
./busybox pivot_root . old_root
./busybox echo "Chrooting and running init..."
exec ./busybox chroot . /fakeinit
EOF
./busybox chmod +x tmp/${OLD_INIT##*/}

./busybox echo "Starting secondary sshd"

./busybox chroot . /usr/bin/ssh-keygen -A
./busybox chroot . /usr/sbin/sshd -p $PORT -o PermitRootLogin=yes

./busybox echo "You should SSH into the secondary sshd now."

./busybox echo "About to take over init. This script will now pause for a few seconds."
./busybox echo "If the takeover was successful, you will see output from the new init."
./busybox echo "You may then kill the remnants of this session and any remaining"
./busybox echo "processes from your new SSH session, and umount the old root filesystem."

./busybox mount --bind tmp/${OLD_INIT##*/} ${OLD_INIT}

# request that the init(8) daemon re-execute itself
telinit u

./busybox sleep 1
