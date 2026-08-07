# FreeBSD on Ampere Altra Server

## Hardware configuration

 - **Motherboard:** ASRock Rack ALTRAD8UD2-1L2Q
 - **Processor:** Ampere Altra Q64-30 64-Core 3.00GHz  Processor
 - **Memory:** 256 GB of Samsung DDR4 (PC4-25600), ECC Registered, Dual-rank
 - **Add-in card:** Icy Dock ExpressSlot Slide 4 Bay M.2 NVMe SSD Adapter Card
 - **System storage:** Three Samsung 990 PRO 2 TB - NVMe PCIe 4.0 M.2 2280 SSD


## Hybrid virtualization approach

After an initial challenging attempt to install FreeBSD on the bare-metal hardware [^1], I resolved to install FreeBSD as a virtual machine instead, using [Debian as a KVM Hypervisor](../debian-kvm-hypervisor/debian-root-on-zfs-ampere-altra.md) on this server.

[^1]: For a summary of the challenges I encountered when trying to install FreeBSD directly on this hardware, please check this thread in the Ampere Computing Developers’ Community Forum:  
[ALTRAD8UD2-1L2Q + Ampere Altra Q64-30 + FreeBSD 15.0-RELEASE installer won’t boot](https://community.amperecomputing.com/t/altrad8ud2-1l2q-ampere-altra-q64-30-freebsd-15-0-release-installer-wont-boot/3288).

Nevertheless, since one of the main goals I had was to use FreeBSD as the operating system for a large storage server, in this guide, I will focus on installing FreeBSD on the physical NVMe drives mentioned above, using PCIe passthrough from the hypervisor to the virtual machine.

I suppose you could call this setup a hybrid between bare-metal and virtualized. Effectively, this is going to be an installation of FreeBSD on bare-metal storage devices, using virtualized hardware for everything else (processor, memory, networking interface).

To be more specific, I’ll be using the following virtualization settings.
 - **Processor**: 8 vCPUs as host passthrough
 - **Memory**: 32 GB


## Prepare installation image

On the hypervisor machine, download latest FreeBSD 15 image for ARM64 architecture.

```console
# cd /var/lib/libvirt/images/iso
# wget https://download.freebsd.org/releases/ISO-IMAGES/15.0/FreeBSD-15.0-RELEASE-arm64-aarch64-dvd1.iso
```

Verify its checksum.

```console
# wget https://download.freebsd.org/releases/ISO-IMAGES/15.0/CHECKSUM.SHA512-FreeBSD-15.0-RELEASE-arm64-aarch64
# shasum -c -a 512 --ignore-missing CHECKSUM.SHA512-FreeBSD-15.0-RELEASE-arm64-aarch64
```

If the checksum matches, you should see the following output.

```console
FreeBSD-15.0-RELEASE-arm64-aarch64-dvd1.iso: OK
```

Cleanup the checksum file.

```console
# rm -f CHECKSUM.SHA512-FreeBSD-15.0-RELEASE-arm64-aarch64
# cd -
```


## Create the virtual machine

### Prepare FreeBSD operating system NVMe drives for PCIe passthrough

Please follow the separate guide on this topic:  
[PCIe passthrough for virtual machines on Debian KVM Hypervisor](../debian-kvm-hypervisor/debian-pcie-passthrough.md)

Once you’re done setting this up, make sure the three Samsung NVMe drives are correctly configured for PCIe passthrough.

```console
# lspci -nnk | grep -i "Non-volatile memory" -A 3
0000:01:00.0 Non-Volatile memory controller [0108]: Samsung Electronics Co Ltd NVMe SSD Controller S4LV008[Pascal] [144d:a80c]
	Subsystem: Samsung Electronics Co Ltd Device [144d:a801]
	Kernel driver in use: vfio-pci
	Kernel modules: nvme
0000:02:00.0 Non-Volatile memory controller [0108]: Samsung Electronics Co Ltd NVMe SSD Controller S4LV008[Pascal] [144d:a80c]
	Subsystem: Samsung Electronics Co Ltd Device [144d:a801]
	Kernel driver in use: vfio-pci
	Kernel modules: nvme
0000:03:00.0 Non-Volatile memory controller [0108]: Samsung Electronics Co Ltd NVMe SSD Controller S4LV008[Pascal] [144d:a80c]
	Subsystem: Samsung Electronics Co Ltd Device [144d:a801]
	Kernel driver in use: vfio-pci
	Kernel modules: nvme
```

This output above shows these devices are ready to be used by a virtual machine with PCIe passthrough because of this important line, which is present for each drive.

```console
	Kernel driver in use: vfio-pci
```

Also make note of the PCIe addresses of these devices.
 - `0000:01:00.0`
 - `0000:02:00.0`
 - `0000:03:00.0`

### Create the virtual machine

Even though [Cockpit’s virtual machines management interface](../debian-kvm-hypervisor/debian-kvm-libvirt-cockpit.md) is generally easier to use for most simple tasks, on my Debian KVM hypervisor, it would consistently fail to create the virtual machine with Secure Boot enabled. Sadly, the FreeBSD installer couldn’t even start with this kind of virtual machine firmware.

Using the command-line on the hypervisor machine does the trick to create the virtual machine though.

```console
# virt-install \
      --connect qemu:///system \
      --name my_server \
      --memory 32768 \
      --vcpus 8 \
      --cdrom /var/lib/libvirt/images/iso/FreeBSD-15.0-RELEASE-arm64-aarch64-dvd1.iso \
      --disk none \
      --host-device pci_0000_01_00_0 \
      --host-device pci_0000_02_00_0 \
      --host-device pci_0000_03_00_0 \
      --os-variant freebsd14.2 \
      --boot firmware=efi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no \
      --graphics vnc \
      --noautoconsole
```

Here are some of the important parts of this command.
 - The machine’s name is set to `my_server`.
 - The machine is given 32 GB of RAM and 8 vCPUs as host passthrough.
 - The FreeBSD OS image is mounted as a CD-ROM.
 - No disk is provided, because we don’t want a disk image for this machine.
 - The system NVMe drives are passed through with the `--host-device` option.
	 - These match the PCIe addresses noted above.
	 - However they’re formatted the same way as the output of `virsh nodedev-list --cap pci`.
 - The OS variant is set to `freebsd14.2`, which is the most recent FreeBSD version known by `libvirt`.
 - The boot firmware is specifically configured with Secure Boot disabled.


## Install FreeBSD

Go over to Cockpit to find your new virtual machine, and open its console. You should see it boot nicely into the FreeBSD installer.

Go through the initial setup for FreeBSD.

### Initial installer dialogs

Here’s a quick description of what you should do in the first few dialogs of the FreeBSD installer.

 - **Welcome**
	 - Select the *Install* option.
 - **Keymap Selection**
	 - Select *Continue with default keymap* if you use a US QWERTY keyboard, or select a more specific keymap if you require it.
 - **Set Hostname**
	 - Enter a hostname in the format `my_server.my_domain.tld`.
 - **Select Installation Type**
	 - Select the *Packages (Tech Preview)* option.
 - **Network or Offline Installation**
	 - Select the *Network* option.
 - **Network Configuration**
	 - Select the *Auto* option for now.

### Partitioning

When you reach the partitioning dialog, select the *Shell* option.

Find the device identifiers of the SSD drives to install the system on by looking at the output of the following command.

```console
# camcontrol devlist
```

Going forward, let’s assume that `nda0`, `nda1` and `nda2` are the device identifiers of the SSD drives to install the system on.

Find the serial number of each of the SSD drives by looking at the output of one of the following commands.

```console
# dmesg | grep -i nda0 | grep -i "serial number"
# nvmecontrol identify nvme0 | grep -i "serial number"
```

Going forward, we will refer to these serial numbers as `sn0`, `sn1` and `sn2` respectively for `nda0`, `nda1` and `nda2`.

Destroy previous partition table on the drives, if any.

```console
# gpart destroy -F nda0
# gpart destroy -F nda1
# gpart destroy -F nda2
```

If those drives have previously been used as vdevs of a previous ZFS pool, you may want to zero out a few sectors at the beginning and at the end of the drives to prevent an annoying warning later on with the `zpool create` command. In order to do that, create a new temporary script named `wipe_drive` with the following command:

```console
# cat << 'EOF' > /tmp/wipe_drive
#! /bin/sh
#
# wipe_drive
#
# Utility script to completely wipe the contents of a storage block device.
#
# This is built for FreeBSD, and simply zeroes out a few sectors
# at the beginning and end of the block device.
#

drive_id=$1

if [ -z ${drive_id} ]
then
    /bin/echo "usage: $0 <drive_id>" >&2
    /bin/echo "" >&2
    /bin/echo "Completely wipes the contents of a storage block device." >&2
    /bin/echo "" >&2
    /bin/echo "You may find the valid <drive_id> by using commands such as:" >&2
    /bin/echo "# camcontrol devlist" >&2
    /bin/echo "# nvmecontrol devlist" >&2
    /bin/echo "# geom disk list" >&2
    exit 1
fi

/bin/echo "About to completely wipe the contents of /dev/${drive_id}..."
/bin/echo ""

/sbin/geom disk list ${drive_id}

/bin/echo -n "Are you sure you want to completely wipe the contents of /dev/${drive_id}? [yes/no] "
read confirmation_text

if [ $(/bin/echo ${confirmation_text} | /usr/bin/tr '[:upper:]' '[:lower:]') != yes ]
then
    /bin/echo "Aborting due to non-affirmative answer: ${confirmation_text}." >&2
    exit
fi

/usr/sbin/diskinfo ${drive_id} | \
while read disk sector_size size sectors other
do
    /bin/echo "Deleting MBR, GPT Primary, ZFS(L0L1)/other partition table..."
    /bin/dd if=/dev/zero of=/dev/${drive_id} bs=${sector_size} count=8192
    /bin/echo "Deleting GEOM metadata, GPT Secondary(L2L3)..."
    /bin/dd if=/dev/zero of=/dev/${drive_id} bs=${sector_size} oseek=$(expr ${sectors} - 8192) count=8192
done
EOF
```

Make the script executable, and wipe the relevant drives.

```console
# chmod +x /tmp/wipe_drive

# /tmp/wipe_drive nda0
# /tmp/wipe_drive nda1
# /tmp/wipe_drive nda2
```

Create new GPT partition tables.

```console
# gpart create -s gpt nda0
# gpart create -s gpt nda1
# gpart create -s gpt nda2
```

Going forward, for partitioning purposes, we’ll be using GPT labels that include the serial number of the respective drive, as `-sn0`, `-sn1` and `-sn2`. While this is pretty verbose, the GPT labels will be used very rarely, and for the occasional disaster recovery scenario, it may be more convenient to have the serial number embedded in the GPT label, to make sure no mistake is made about which drive to take offline.

Create partitions for ZFS.

```console
# gpart add -a 4k -t efi -l boot-sn0 -s 200m nda0
# gpart add -a 4k -t freebsd-swap -l swap-sn0 -s 100g nda0
# gpart add -a 4k -t freebsd-zfs -l system-sn0 nda0

# gpart add -a 4k -t efi -l boot-sn1 -s 200m nda1
# gpart add -a 4k -t freebsd-swap -l swap-sn1 -s 100g nda1
# gpart add -a 4k -t freebsd-zfs -l system-sn1 nda1

# gpart add -a 4k -t efi -l boot-sn2 -s 200m nda2
# gpart add -a 4k -t freebsd-swap -l swap-sn2 -s 100g nda2
# gpart add -a 4k -t freebsd-zfs -l system-sn2 nda2
```

For good measure, in case you just recreated similar partitions to those that used to exist on these drives, you can clear any pre-existing ZFS label for the system partitions.

```console
# zpool labelclear -f /dev/gpt/system-sn0
# zpool labelclear -f /dev/gpt/system-sn1
# zpool labelclear -f /dev/gpt/system-sn2
```

Create the ZFS pool with relevant datasets.

```console
# zpool create -o ashift=12 -o altroot=/mnt -m none system mirror /dev/gpt/system-sn0 /dev/gpt/system-sn1 /dev/gpt/system-sn2
# zfs set mountpoint=/ system
# zfs set checksum=blake3 system
# zfs set compression=lz4 system
# zfs set atime=off system
# zpool set bootfs=system system

# zfs create -o exec=on -o setuid=off system/tmp
# chmod 1777 /mnt/tmp

# zfs create -o compression=gzip -o setuid=off system/home

# zfs create -o canmount=off system/usr
# zfs create system/usr/local
# zfs create -o setuid=off system/usr/ports
# zfs create -o compression=off -o exec=off -o setuid=off system/usr/ports/distfiles
# zfs create -o compression=off -o exec=off -o setuid=off system/usr/ports/packages
# zfs create -o exec=off -o setuid=off system/usr/src
# zfs create system/usr/obj

# zfs create -o canmount=off system/var
# zfs create -o compression=gzip -o exec=off -o setuid=off system/var/backups
# zfs create -o exec=off -o setuid=off system/var/audit
# zfs create -o exec=off -o setuid=off system/var/crash
# zfs create -o exec=off -o setuid=off system/var/db
# zfs create -o exec=on -o setuid=off system/var/db/pkg
# zfs create -o exec=off -o setuid=off system/var/empty
# zfs create -o compression=gzip -o exec=off -o setuid=off system/var/log
# zfs create -o compression=gzip -o exec=off -o setuid=off -o atime=on system/var/mail
# zfs create -o exec=off -o setuid=off system/var/run
# zfs create -o exec=on -o setuid=off system/var/tmp
# chmod 1777 /mnt/var/tmp
```

Prepare EFI mount points.

```console
# mkdir /mnt/boot
# cd /mnt/boot
# mkdir efi
# newfs_msdos /dev/gpt/boot-sn0
# mount_msdosfs /dev/gpt/boot-sn0 /mnt/boot/efi
# ln -s efi efi0

# mkdir efi1
# newfs_msdos /dev/gpt/boot-sn1
# mount_msdosfs /dev/gpt/boot-sn1 /mnt/boot/efi1

# mkdir efi2
# newfs_msdos /dev/gpt/boot-sn2
# mount_msdosfs /dev/gpt/boot-sn2 /mnt/boot/efi2
```

Prepare `fstab` file.

```console
# cat << EOF > /tmp/bsdinstall_etc/fstab
# Device            Mountpoint      FStype      Options         Dump    Pass#
/dev/gpt/boot-sn0   /boot/efi       msdosfs     rw,failok       0       0
/dev/gpt/boot-sn1   /boot/efi1      msdosfs     rw,failok       0       0
/dev/gpt/boot-sn2   /boot/efi2      msdosfs     rw,failok       0       0

/dev/gpt/swap-sn0   none            swap        sw              0       0
/dev/gpt/swap-sn1   none            swap        sw              0       0
/dev/gpt/swap-sn2   none            swap        sw              0       0
EOF
```

Type `exit` in the shell and proceed with the installation as normal.

### Select system components

In the **Select System Components** dialog, a few options are pre-selected.
 - `base`: The complete base system (includes `devel` and `optional`)
 - `kernel-dbg`: Debug symbols for the kernel
 - `lib32`: 32-bit compatibility libraries

It’s pretty hard to believe that we would have anything meaningful to gain nowadays by installing the 32-bit compatibility libraries, so you may want to deselect the `lib32` components.

For good measure, you may want to select the following components as well.
 - `devel`: C/C++ compilers and related utilities
 - `optional`: Optional software (excluding compilers)

In summary, here are the components you should consider selecting in this dialog.
 - `base`: The complete base system (includes `devel` and `optional`)
 - `devel`: C/C++ compilers and related utilities
 - `kernel-dbg`: Debug symbols for the kernel
 - `optional`: Optional software (excluding compilers)

Once you validate your selection, the installer will download relevant packages from the network, and install them.

### Final steps in the installer

Here’s a quick description of what you should do in the last few dialogs of the FreeBSD installer.

 - **Set root password**
	 - Enter the password you wish to use for the `root` administrator account.
 - **Time Zone Selector** and subsequent dialogs about country and region
	 - Select the continent and country you reside in.
	 - If you live in a country that has multiple time zones, you may be presented with a list of available timezones.
	 - For example, if you live in California, in the dialog *United States of America Time Zones*, select the *Pacific* timezone.
	 - Confirm the timezone abbreviation in the next dialog.
 - **Time & Date**
	 - Confirm the time and date are accurate.
 - **System Configuration**
	 - Select services you require for your server.
	 - For example, you may want to select the following services.
		 - `sshd`: Secure shell daemon
		 - `ntpd`: Synchronize system and network time
		 - `ntpd_sync_on_start`: Sync time on `ntpd` startup, even if offset is high
		 - `dumpdev`: Enable kernel crash dumps to `/var/crash`
 - **System Hardening**
	 - Select system security hardening options you require for your server.
	 - For example, you may want to select the following options.
		 - `0 hide_uids`: Hide processes running as other users
		 - `1 hide_gids`: Hide processes running as other groups
		 - `2 hide_jail`: Hide processes running in jails
		 - `3 read_msgbuf`: Disable reading kernel message buffer for unprivileged users
		 - `4 proc_debug`: Disable process debugging facilities for unprivileged users
		 - `5 random_pid`: Randomize the PID of newly created processes
		 - `6 clear_tmp`: Clean the `/tmp` filesystem on system startup
		 - `7 disable_syslogd`: Disable opening `syslogd` network socket (disables remote logging)
		 - `8 secure_console`: Enable console password prompt
		 - `9 disable_ddtrace`: Disallow DTrace destructive mode
 - **Add User Accounts**
	 - A more detailed set of steps for creating unprivileged user accounts is available in [this guide](freebsd-unprivileged-user.md).
	 - If you wish to follow those instructions later on, feel free to decline adding a user account in this step of the installer.
 - **Final Configuration**
	 - Select the *Finish* option to apply configuration and exit the installer.

### Manual configuration

This dialog offers the option to *open a shell in the new system*; accept this by selecting the *Yes* option.

Configure ZFS to load and mount the file systems automatically at boot.

```console
# echo 'zfs_enable="YES"' >> /etc/rc.conf
```

Replicate contents of EFI boot partition from the first drive to the second drive.

```console
# cd /boot/efi1
# cp -av ../efi0/* .

# cd /boot/efi2
# cp -av ../efi0/* .
```

Power off the machine.

```console
# poweroff
```


## First boot into installed FreeBSD system

When the virtual machine is properly shut down, eject the FreeBSD installation media using Cockpit’s virtual machines management interface.

Then change the boot order of the virtual machine, to include the FreeBSD operating system NVMe drives, and move them to the top.

Finally, start the virtual machine again.

After a few seconds, you should be greeted with the FreeBSD login prompt in your console!