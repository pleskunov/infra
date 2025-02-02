#!/bin/bash

# This script automates the installation of the base system.
# It currently supports only Arch Linux (systemd) in UEFI mode (Secure Boot must be disabled).
#
# Dual boot configurations are not supported at this time due to the complexity of partitioning.
#
# Copyright (c) 2025 Pavel Pleskunov.
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or (at
# your option) any later version.
#
# lumapi_connector is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
# USA

set -x
set -oue pipefail

# Settings
target_disk="$1"
hostname="$2"
username="$3"
tz="/usr/share/zoneinfo/America/Montreal"
cryptroot_device="cryptroot"
core_packages=("base" "base-devel" "linux" "linux-lts" "linux-firmware" "grub" "efibootmgr" "networkmanager" "openssh" "gnupg" "neovim" "git" "htop" "chrony" "curl" "wget")
daemons="chronyd NetworkManager"
install_second_stage=false
post_install_script_url="https://raw.githubusercontent.com/pleskunov/infra/refs/heads/main/post-install.sh"
test_mode=true

# Check if we running as root
if ! [ "${EUID:-$(id -u)}" -eq 0 ]; then
  echo "The script must be run as root!"
  exit 1
fi

# Partition the disk
echo "Partitioning the disk..."
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk -n "${target_disk}"
  g # create a new empty GPT partition table
  n # add a new partition
  1 # partition number 1
    # default, first sector is the beginning of the disk
  +500M # last sector - allocate 500 MiB for the EFI partition
  n # add a new partition
  2 # partition number 2
    # default, first sector is after the last sector of partition 1
  +2G # last sector - allocate 2 GiB for the boot partition
  n # add a new partition
  3 # partition number 3
    # default, first sector is after the last sector of partition 2
    # default, last sector - extend partition 3 to the end of the disk
  t # change a partition type
  1 # select partition 1
  1 # change type of partition 1 to EFI System
  p # print the in-memory partition table
  w # write the table to disk and exit
  q # quit without saving changes
EOF

# Get the partition's list
mapfile -t partitions < <(fdisk -l "${target_disk}" | awk '/^\/dev/ && /[123]/{print $1}')

echo "Encrypting the root partition..."
cryptsetup --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha512 --pbkdf argon2id \
    --iter-time 4000 --verify-passphrase --use-urandom luksFormat "${partitions[2]}"

echo "Preparing the encrypted root partition..."
cryptsetup luksOpen "${partitions[2]}" "$cryptroot_device"

echo "Formatting the partitions..."
mkfs.fat -F 32 "${partitions[0]}"
mkfs.ext4 "${partitions[1]}"
mkfs.ext4 /dev/mapper/"$cryptroot_device"

echo "Mounting the file systems..."

mount /dev/mapper/"$cryptroot_device" /mnt

mkdir -p /mnt/boot
mount "${partitions[1]}" /mnt/boot

mkdir -p /mnt/boot/efi
mount "${partitions[0]}" /mnt/boot/efi


echo "Installing essential packages..."
pacstrap -K /mnt "${core_packages[@]}"

echo "Generating fstab configuration..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "Configuring the new system..."

# Set the time zone
arch-chroot /mnt ln -sf "${tz}" /etc/localtime

# Update the hardware clock
arch-chroot /mnt hwclock --systohc

# Prepare the locales
arch-chroot /mnt sed -i '/^#.*en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=en_US.UTF-8" >> /mnt/etc/locale.conf

# Set the hostname
echo "${hostname}" >> /mnt/etc/hostname

echo "Configuring initramfs..."
# Backup the default mkinitcpio configuration
arch-chroot /mnt cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak

arch-chroot /mnt sed -i '/^HOOKS=/s/^/#/' /etc/mkinitcpio.conf
arch-chroot /mnt sed -i '/^#HOOKS=/a HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)' /etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P

echo "Configuaring the bootloader..."
# Backup the default bootloader configuration
arch-chroot /mnt cp /etc/default/grub /etc/default/grub.bak

# Get the UUID of the encrypted root partition
cryptdevice_uuid=$(arch-chroot /mnt blkid -t TYPE="crypto_LUKS" -o value -s UUID)
arch-chroot /mnt sed -i '/^GRUB_CMDLINE_LINUX=/s/^/#/' /etc/default/grub
arch-chroot /mnt sed -i '/^#GRUB_CMDLINE_LINUX=/a GRUB_CMDLINE_LINUX="cryptdevice=UUID='"${cryptdevice_uuid}"':cryptroot root=/dev/mapper/cryptroot"' /etc/default/grub

# Install the bootloader
arch-chroot /mnt grub-install --target=x86_64-efi
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

echo "Enabling daemons..."
for daemon in $daemons; do
  arch-chroot /mnt systemctl enable "${daemon}"
done

echo "Setting the password for root..."
arch-chroot /mnt passwd

echo "Creating a normal user..."
arch-chroot /mnt useradd -m -G wheel "$username"
arch-chroot /mnt passwd "$username"

if "${install_second_stage}"; then
  echo "Downloading the post-install script..."
  arch-chroot /mnt curl --proto '=https' --tlsv1.2 -o "/home/${username}/post-install.sh" -sSf "$post_install_script_url"
fi

if ! "${test_mode}"; then
  # Unmount all the file systems
  umount -R /mnt
  # Close the encrypted root partition
  crypsetup luksclose cryptroot
fi

echo "Installation of the base system is completed. Please, reboot the system to continue."
exit 0
