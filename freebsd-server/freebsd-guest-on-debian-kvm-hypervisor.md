# FreeBSD guest virtual machine on Debian KVM hypervisor host

Once your Debian host machine is set up with [KVM/`libvirt` and Cockpit to create and manage virtual machines](../debian-kvm-hypervisor/debian-kvm-libvirt-cockpit.md), you might want to install FreeBSD as a guest in a new virtual machine.

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


## Create a ZFS volume for the virtual machine

In order to create a new virtual machine named `my_vm`, the first step is to create a new ZFS volume; let’s create this volume with a capacity of 200 GB.

```console
# virsh vol-create-as hypervisor-vm-pool my_vm-disk0 200G
```


## Create the virtual machine

Even though Cockpit’s virtual machines management interface is generally easier to use for most simple tasks, on my Debian KVM hypervisor, it would consistently fail to create the virtual machine with Secure Boot enabled. Sadly, the FreeBSD installer couldn’t even start with this kind of virtual machine firmware.

Using the command line on the hypervisor machine does the trick to create the virtual machine though.

```console
# virt-install \
      --connect qemu:///system \
      --name my_vm \
      --memory 131072 \
      --vcpus 32 \
      --cdrom /var/lib/libvirt/images/iso/FreeBSD-15.0-RELEASE-arm64-aarch64-dvd1.iso \
      --disk vol=hypervisor-vm-pool/my_vm-disk0,bus=scsi \
      --os-variant freebsd14.2 \
      --boot firmware=efi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no \
      --graphics vnc \
      --noautoconsole
```

Here are some of the important parts of this command.
 - The machine’s name is set to `my_vm`.
 - The machine is given 128 GB of RAM and 32 vCPUs as host passthrough.
 - The FreeBSD OS image is mounted as a CD-ROM.
 - A disk is provided using the volume created previously.
	 - The volume for `libvirt` is `hypervisor-vm-pool/my_vm-disk0`.
	 - As shown before, it is backed by a ZFS volume.
	 - The disk is connected to the virtual machine using the SCSI bus.
	 - Using the `virtio` would probably have been a bit better, but the FreeBSD installer could not see the disk with that configuration.
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

Find the device identifier of the disk by looking at the output of the following command.

```console
# camcontrol devlist
```

The output should look like this, showing the disk connected via SCSI bus as `da0`.

```console
<QEMU QEMU HARDDISK 2.5+>          at scbus0 target 0 lun 0 (pass0, da0)
<QEMU QEMU CD-ROM 2.5+>            at scbus0 target 0 lun 1 (pass1, cd0)
```

Create a new GPT partition table, and the three partitions needed for FreeBSD.

```console
# gpart create -s gpt da0

# gpart add -a 4k -t efi -l boot -s 200m da0
# gpart add -a 4k -t freebsd-swap -l swap -s 10g da0
# gpart add -a 4k -t freebsd-zfs -l system da0
```

Create the ZFS pool with relevant datasets.

```console
# zpool create -o ashift=12 -o altroot=/mnt -m none system /dev/gpt/system
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

Prepare EFI mount point.

```console
# mkdir /mnt/boot
# cd /mnt/boot
# mkdir efi
# newfs_msdos /dev/gpt/boot
# mount_msdosfs /dev/gpt/boot /mnt/boot/efi
```

Prepare `fstab` file.

```console
# cat << EOF > /tmp/bsdinstall_etc/fstab
# Device            Mountpoint      FStype      Options         Dump    Pass#
/dev/gpt/boot       /boot/efi       msdosfs     rw              0       0

/dev/gpt/swap       none            swap        sw              0       0
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

Power off the machine.

```console
# poweroff
```


## First boot into installed FreeBSD system

When the virtual machine is properly shut down, eject the FreeBSD installation media using Cockpit’s virtual machines management interface.

Then, start the virtual machine again.

After a few seconds, you should be greeted with the FreeBSD login prompt in your console!