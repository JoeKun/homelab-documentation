# Debian with Root on ZFS on Ampere Altra Server

The first step to setting up my Debian KVM Hypervisor was to install Debian GNU/Linux on my physical server with root on ZFS.

While the main inspiration for this setup comes from [OpenZFS’s Getting Started guide for Debian Trixie Root on ZFS](https://openzfs.github.io/openzfs-docs/Getting%20Started/Debian/Debian%20Trixie%20Root%20on%20ZFS.html), achieving this setup on an Ampere Altra-based server is more challenging, due to the lack of a Debian 13 Trixie Live CD for ARM64.

## Hardware configuration

### Ampere Altra system

 - **Motherboard:** ASRock Rack ALTRAD8UD2-1L2Q
 - **Processor:** Ampere Altra Q64-30 64-Core 3.00GHz  CPU
 - **Memory:** 256 GB of Samsung DDR4 (PC4-25600), ECC Registered
 - **Add-in card:** Icy Dock ExpressSlot Slide 4 Bay M.2 NVMe SSD Adapter Card
 - **Hypervisor system storage:** 2 × Samsung 990 PRO 2 TB - NVMe M.2 2280 SSD

### Installation media

Instead of using a live CD, we’ll need two USB flash drives. We’ll use the first drive for a regular Debian 13 Trixie installer image for ARM64, and the second one will be our destination for a temporary install of the operating system which will serve the same purpose as a Live CD.

The two USB flash drives will only be used at install time.


## Prepare installation media

On another computer, such as a Mac laptop, download the latest Debian 13 Trixie image for ARM64 architecture.

```console
$ curl -O -L https://cdimage.debian.org/debian-cd/13.2.0/arm64/iso-dvd/debian-13.2.0-arm64-DVD-1.iso
```

Verify its checksum.

```console
$ curl -O -L https://cdimage.debian.org/debian-cd/13.2.0/arm64/iso-dvd/SHA512SUMS
$ shasum -c -a 512 --ignore-missing SHA512SUMS
```

You should see the following output:

```console
debian-13.2.0-arm64-DVD-1.iso: OK
```

You can safely remove the checksum file at this point.

```console
$ rm -f SHA512SUMS
```

Find the device identifier for the USB flash drive to be used for installing Debian by looking at the output of the following command.

```console
$ diskutil list
```

Let’s assume going forward that the USB flash drive corresponds to `/dev/disk38`.

Make sure to unmount all volumes from the USB flash drive.

```console
$ diskutil unmountDisk /dev/disk38
```

Expand the image to the USB flash drive using the following command.

```console
$ sudo dd if=debian-13.2.0-arm64-DVD-1.iso of=/dev/disk38 bs=4m
```

You will likely be met with a standard macOS system dialog that says:

> The disk you attached was not readable by this computer.

You can safely dismiss this dialog by pressing the *Ignore* button.


## BIOS configuration

If you intend to use NVMe M.2 disks in a PCIe 4.0 Expansion Card Adapter as noted above, you will need to set up the relevant PCIe slot with PCIe bifurcation.

In this specific scenario, assuming you insert the add-in card in slot 5 of the ASRock Rack ALTRAD8UD2-1L2Q motherboard, then you need to configure PCIe output *PCIE5* for PCIe bifurcation.

Hence, enter the BIOS, and navigate to:

 * *Advanced* tab
 * *Chipset Configuration* menu
 * *PCIE Link Width* menu

Then select *PCIE5 Link Width*, and then select the option `4x4x4x4`.

Then navigate to the *Exit* tab, and select *Save Changes and Exit*.


## Install Debian Trixie onto the secondary USB flash drive

Connect both USB flash drives to the server, and boot the server into the first USB flash drive with the Debian Trixie installer.

When you’re presented with the GRUB menu for the installer, select *Graphical Install*.

Here’s a quick description of what you should do in the first few dialogs of the Debian installer.

 - **Select a language**
	 - Select the language you want to use for the installer.
	 - The following dialogs are documented below assuming the *English* language was selected.
 - **Select your location**
	 - Select the country you reside in.
	 - For example, if you live in California, you may select *United States*.
 - **Configure the keyboard**
	 - Select the keymap you would like to use, such as *American English*.
 - **Load installer components from installation media**
	 - Nothing to select here; just wait until the next dialog appears.
 - **Configure network**
	 - You may be asked to wait a few seconds here with a message like *Detecting link on enP2p3s0; please wait…*.
	 - Eventually, if your system has multiple network interfaces, this dialog will likely ask you to select your primary network interface.
	 - For example, with this system, you may select *enP2p3s0: Intel Corporation i210 Gigabit Network Connection*.
	 - You may be asked to wait a few seconds here once again with messages like:
		 - *Detecting link on enP2p3s0; please wait…*
		 - *Waiting for link-local address…*
		 - *Configuring the network with DHCP*
		 - *Network autoconfiguration has succeeded*
	 - When asked to enter the hostname for this system, please enter a hostname in the format `my_server`.
	 - When asked to enter the domain name for this system, please enter a domain name in the format `my_domain.tld`.
 - **Set up users and passwords**
	 - If you would like to allow direct password-based access via the `root` account, then enter your `root` password twice.
	 - When asked to enter the *Full name for the new user*, enter something like *John Smith*.
	 - When asked to enter the *Username for your account*, enter something like `john`.
	 - When asked to *Choose a password for the new user*, enter the desired password for the unprivileged user twice.
 - **Configure the clock**
	 - For example, if you live in California, you may want to select the *Pacific* timezone.
 - **Partition disks**
	 - You may be asked to wait a few seconds here with messages like:
		 - *Loading additional components*
		 - *Starting up the partitioner*
	 - When asked to select the *Partitioning method*, select the *Guided - use entire disk* method.
	 - Select the desired disk corresponding to the second USB flash drive.
	 - When asked to select a *Partitioning scheme*, select the *All files in one partition (recommended for new users)* scheme.
	 - Please review the proposed partitioning changes, and if you agree with them, select *Finish partitioning and write changes to disk*.
	 - You may be presented with one more screen to confirm the changes to partition tables and partitions. If you agree with the changes, below the question *Write the changes to disk?*, select *Yes*.
 - **Install the base system**
	 - You may be asked to wait a few seconds or a few minutes here with messages like *Installing the base system*.
 - **Configure the package manager**
	 - When asked if you want to *Scan extra installation media*, select *No*.
	 - When asked if you want to *Use a network mirror*, select *Yes*.
	 - Select the *Debian archive mirror country* that is closest to you, such as *United States*.
	 - Select the *Debian archive mirror* that is closest to you, such as *deb.debian.org*.
	 - Enter any relevant HTTP proxy information if needed.
	 - You may be asked to wait a few minutes here with messages like:
		 - *Configuring apt*
		 - *Select and install software*
 - **Configuring popularity-contest**
	 - When asked whether you want to *Participate in the package usage survey*, select *No*.
 - **Software selection**
	 - When asked to *Choose software to install*, please make sure the following options are selected:
		 - *… GNOME* in the *Debian desktop environment* section.
		 - *SSH server*
		 - *standard system utilities*
 - **Select and install software**
	 - You may be asked to wait a few minutes here with messages like:
		 - *Select and install software*
 - **Finish the installation**
	 - Remove the USB flash drive with the installation media now.
	 - Select the *Continue* button to reboot.


## Prepare temporary Debian install environment

Boot into the temporary Debian install, and log into your unprivileged user account.

If the destination disk has been used before (with partitions at the same offsets), previous filesystems (e.g. the ESP) will automount if not disabled. To prevent this problem, disable automounting by running the following command in the Terminal:

```console
$ gsettings set org.gnome.desktop.media-handling automount false
```

Most steps of the forthcoming installation process require running as administrator, so switch to the `root` account with `su`, and add secure binary directories to the `PATH` environment variable.

```console
$ su
# export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"
```

A few changes need to be made to `/etc/apt/sources.list`. Remove the first entry for the Debian installation media, which should look like this:

```
deb cdrom:[Debian GNU/Linux 13.2.0 _Trixie_ - Official arm64 DVD Binary-1 with firmware 20251115-11:06]/ trixie contrib main non-free-firmware
```

Then edit the next entry from:

```
deb http://deb.debian.org/debian/ trixie main
```

to include `contrib` and `non-free-firmware` packages:

```
deb http://deb.debian.org/debian/ trixie main contrib non-free-firmware
```

Update the APT database of available packages.

```console
# apt update
```

Install a few relevant packages required for the installation process.

```console
# apt install linux-headers-generic
# apt install debootstrap gdisk zfsutils-linux
```

In the dialog titled *Configuring zfs-dkms*, review the notice about the incompatibility of open source licenses of Linux and OpenZFS, and make sure you feel comfortable with the limitations of this configuration.

The last few lines of console output from the previous install command should look similar to this.

```
Loading new zfs/2.3.2 DKMS files...
Building for 6.12.90+deb13.1-arm64

Building initial module zfs/2.3.2 for 6.12.90+deb13.1-arm64
Sign command: /lib/modules/6.12.90+deb13.1-arm64/build/scripts/sign-file
Signing key: /var/lib/dkms/mok.key
Public certificate (MOK): /var/lib/dkms/mok.pub
Certificate or key are missing, generating self signed certificate for MOK...

Running the pre_build script........... done.
Building module(s).................. done.
Signing module /var/lib/dkms/zfs/2.3.2/build/module/zfs.ko
Signing module /var/lib/dkms/zfs/2.3.2/build/module/spl.ko
Running the post_build script... done.
Installing /lib/modules/6.12.90+deb13.1-arm64/updates/dkms/zfs.ko.xz
Installing /lib/modules/6.12.90+deb13.1-arm64/updates/dkms/spl.ko.xz
Running depmod.... done.
Setting up libzfs6linux:arm64 (2.3.2-2) ...
Setting up g++-aarch64-linux-gnu (4:14.2.0-1) ...
Setting up g++-14 (14.2.0-19) ...
Setting up zfsutils-linux (2.3.2-2) ...
insmod /lib/modules/6.12.90+deb13.1-arm64/updates/dkms/spl.ko.xz 
insmod /lib/modules/6.12.90+deb13.1-arm64/updates/dkms/zfs.ko.xz 
Created symlink '/etc/systemd/system/zfs-import.target.wants/zfs-import-cache.service' → '/usr/lib/systemd/system/zfs-import-cache.service'.
Created symlink '/etc/systemd/system/zfs.target.wants/zfs-import.target' → '/usr/lib/systemd/system/zfs-import.target'.
Created symlink '/etc/systemd/system/zfs-mount.service.wants/zfs-load-module.service' → '/usr/lib/systemd/system/zfs-load-module.service'.
Created symlink '/etc/systemd/system/zfs.target.wants/zfs-load-module.service' → '/usr/lib/systemd/system/zfs-load-module.service'.
Created symlink '/etc/systemd/system/zfs.target.wants/zfs-mount.service' → '/usr/lib/systemd/system/zfs-mount.service'.
Created symlink '/etc/systemd/system/zfs.target.wants/zfs-share.service' → '/usr/lib/systemd/system/zfs-share.service'.
Created symlink '/etc/systemd/system/zfs-volumes.target.wants/zfs-volume-wait.service' → '/usr/lib/systemd/system/zfs-volume-wait.service'.
Created symlink '/etc/systemd/system/zfs.target.wants/zfs-volumes.target' → '/usr/lib/systemd/system/zfs-volumes.target'.
Created symlink '/etc/systemd/system/multi-user.target.wants/zfs.target' → '/usr/lib/systemd/system/zfs.target'.
zfs-import-scan.service is a disabled or a static unit, not starting it.
Setting up g++ (4:14.2.0-1) ...
update-alternatives: using /usr/bin/g++ to provide /usr/bin/c++ (c++) in auto mode
Setting up build-essential (12.12) ...
Processing triggers for initramfs-tools (0.148.4) ...
update-initramfs: Generating /boot/initrd.img-6.12.90+deb13.1-arm64
Processing triggers for libc-bin (2.41-12+deb13u3) ...
Processing triggers for man-db (2.13.1-1) ...
Setting up zfs-zed (2.3.2-2) ...
Created symlink '/etc/systemd/system/zed.service' → '/usr/lib/systemd/system/zfs-zed.service'.
Created symlink '/etc/systemd/system/zfs.target.wants/zfs-zed.service' → '/usr/lib/systemd/system/zfs-zed.service'.
```

Load the ZFS kernel module, and print the version of ZFS installed and loaded.

```console
# modprobe zfs
# zfs version
```

You should see output similar to this:

```
zfs-2.3.2-2
zfs-kmod-2.3.2-2
```


## Prepare target disks for Debian install with root on ZFS

All the shell commands shown in this entire section need to be executed in the same shell session, as they use local variables set up at the beginning so we can easily loop over the number of disks to be set up.

You may just reuse the previous shell session as `root`, which already has secure binary directories added to the `PATH` environment variable.

### Identify disks for the permanent Debian install

If you’re trying to install Debian on one or more NVMe disks, then you may want to use the `nvme` command-line utility to easily identify the right disks.

```console
# apt install nvme-cli
# nvme list
```

You may see output similar to this (the serial numbers in this output were redacted/altered).

```
Node                  Generic               SN                   Model                                    Namespace  Usage                      Format           FW Rev  
--------------------- --------------------- -------------------- ---------------------------------------- ---------- -------------------------- ---------------- --------
/dev/nvme9n1          /dev/ng9n1            S7ABCDEFGHIJKLM      Samsung SSD 990 PRO 2TB                  0x1          0.00  GB /   2.00  TB    512   B +  0 B   8B2QJXD7
/dev/nvme10n1         /dev/ng10n1           S7NOPQRSTUVWXYZ      Samsung SSD 990 PRO 2TB                  0x1          0.00  GB /   2.00  TB    512   B +  0 B   8B2QJXD7
```

From the first column named *Node*, you can derive the disk numeric identifiers, which are `nvme9n1` and `nvme10n1`.

```console
# DISK_NUMERIC_IDENTIFIERS=("nvme9n1" "nvme10n1")
```

In order to create the ZFS pool reliably, in a way that works seamlessly even if the numeric identifiers were to change between reboots, or after installing new hardware on the server, we want to find the equivalent of those device nodes that is based on a stable identifier, such as:

```
/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7ABCDEFGHIJKLM
```

You can do this with the following lines in your shell, where you first define an empty array named `DISK_STABLE_IDENTIFIERS` and then fill it in a simple loop that derives these stable identifiers reliably. Along the way, we’ll also gather the disk serial numbers into a dedicated array named `DISK_SERIAL_NUMBERS`, which will also come in handy.

```console
# DISK_STABLE_IDENTIFIERS=()
# DISK_SERIAL_NUMBERS=()
# NUMBER_OF_DISKS=${#DISK_NUMERIC_IDENTIFIERS[@]}
# for disk_numeric_identifier in "${DISK_NUMERIC_IDENTIFIERS[@]}"
  do
      possible_disk_stable_identifiers=$(ls -la /dev/disk/by-id | grep -v "nvme-eui.[0-9a-f]*")
      disk_stable_identifier=$(echo "${possible_disk_stable_identifiers}" | grep -o -- "nvme-.* -> ../../${disk_numeric_identifier}$" | head -n 1 | cut -d " " -f 1)
      disk_stable_identifier="/dev/disk/by-id/${disk_stable_identifier}"
      echo "Found stable identifier for ${disk_numeric_identifier}: ${disk_stable_identifier}"
      disk_serial_number=$(udevadm info --name=${disk_stable_identifier} --query=property --property=ID_SERIAL_SHORT --value)
      echo "Found serial number for ${disk_numeric_identifier}: ${disk_serial_number}"
      lsblk -o NAME,TYPE,PARTTYPENAME,PARTLABEL,LABEL,FSTYPE,MOUNTPOINT "${disk_stable_identifier}"
      DISK_STABLE_IDENTIFIERS+=("${disk_stable_identifier}")
      DISK_SERIAL_NUMBERS+=("${disk_serial_number}")
      echo
  done
```

Here’s what the output of those commands may look like:

```
Found stable identifier for nvme9n1: /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7ABCDEFGHIJKLM
Found serial number for nvme9n1: S7ABCDEFGHIJKLM
NAME    TYPE PARTTYPENAME PARTLABEL LABEL FSTYPE MOUNTPOINT
nvme9n1 disk

Found stable identifier for nvme10n1: /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7NOPQRSTUVWXYZ
Found serial number for nvme10n1: S7NOPQRSTUVWXYZ
NAME     TYPE PARTTYPENAME PARTLABEL LABEL FSTYPE MOUNTPOINT
nvme10n1 disk
```

Below the header with column names, you may see a lot more output if these disks already have partitions and/or if they have already been used to create an older ZFS pool. This output is designed to give you all the information about these disks to make sure you picked the ones you actually intended to use.

If this is wrong, then start over from the top of this section, and make sure to pick the correct disks for your system.

If the output looks good to you though, let’s proceed to erase those disks.

### Erase disks for permanent Debian install

Ensure swap partitions are not in use.

```console
# swapoff --all
```

Completely erase the disks identified above.

```console
# for disk_stable_identifier in "${DISK_STABLE_IDENTIFIERS[@]}"
  do
      echo "Completely erasing contents of: ${disk_stable_identifier}..."
      sgdisk --zap-all "${disk_stable_identifier}"
      partprobe "${disk_stable_identifier}"
      wipefs -a "${disk_stable_identifier}"
      blkdiscard -f "${disk_stable_identifier}"
      echo
  done
```

Here’s what the output of those commands may look like for each iteration of the loop:

```
Completely erasing contents of: /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7ABCDEFGHIJKLM...
Creating new GPT entries in memory.
GPT data structures destroyed! You may now partition the disk using fdisk or
other utilities.
blkdiscard: Operation forced, data will be lost!
```

### Partition disks for permanent Debian install

First, define a few variables for the different partitions.

```console
# BOOT_PART=1
# SWAP_PART=2
# POOL_PART=3
```

Then define some empty arrays for the different types of partitions, based on the relevant stable identifiers.

```console
# DISK_BOOT_PART_STABLE_IDENTIFIERS=()
# DISK_SWAP_PART_STABLE_IDENTIFIERS=()
# DISK_POOL_PART_STABLE_IDENTIFIERS=()
```

Define a variable for the desired size of the swap partitions, in gigabytes.

```console
# SWAP_PARTITION_SIZE="100G"
```

For each disk, create the following partitions:
 1. a boot partition, for the EFI system partition, of approximately 1 GB;
 2. a swap partition, of 100 GB (feel free to change this number in the variable above if needed);
 3. a ZFS partition with the remaining available space.

```console
# for ((i = 0; i < NUMBER_OF_DISKS; i++))
  do
      disk_stable_identifier="${DISK_STABLE_IDENTIFIERS[${i}]}"
      disk_serial_number="${DISK_SERIAL_NUMBERS[${i}]}"
      echo "Creating new partitions for ${disk_stable_identifier} (with serial number ${disk_serial_number})..."
      sgdisk -n "${BOOT_PART}:1M:+1G" -t "${BOOT_PART}:ef00" -c "${BOOT_PART}:hypervisor-boot-${disk_serial_number}" "${disk_stable_identifier}"
      sgdisk -n "${SWAP_PART}:0:+${SWAP_PARTITION_SIZE}" -t "${SWAP_PART}:8200" -c "${SWAP_PART}:hypervisor-swap-${disk_serial_number}" "${disk_stable_identifier}"
      sgdisk -n "${POOL_PART}:0:0" -t "${POOL_PART}:bf00" -c "${POOL_PART}:hypervisor-system-${disk_serial_number}" "${disk_stable_identifier}"
      partprobe "${disk_stable_identifier}"
      sgdisk -p "${disk_stable_identifier}"
      lsblk -o NAME,TYPE,PARTTYPENAME,PARTLABEL,LABEL,FSTYPE,MOUNTPOINT "${disk_stable_identifier}"
      DISK_BOOT_PART_STABLE_IDENTIFIERS+=("${disk_stable_identifier}-part${BOOT_PART}")
      DISK_SWAP_PART_STABLE_IDENTIFIERS+=("${disk_stable_identifier}-part${SWAP_PART}")
      DISK_POOL_PART_STABLE_IDENTIFIERS+=("${disk_stable_identifier}-part${POOL_PART}")
      echo
  done
```

Here’s what the output of those commands may look like for each iteration of the loop:

```
Creating new partitions for /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7ABCDEFGHIJKLM (with serial number S7ABCDEFGHIJKLM)...
Creating new GPT entries in memory.
The operation has completed successfully.
The operation has completed successfully.
The operation has completed successfully.
Disk /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7ABCDEFGHIJKLM: 3907029168 sectors, 1.8 TiB
Sector size (logical/physical): 512/512 bytes
Disk identifier (GUID): 35E1ECDC-09DF-4A0A-817E-EFC625B64651
Partition table holds up to 128 entries
Main partition table begins at sector 2 and ends at sector 33
First usable sector is 34, last usable sector is 3907029134
Partitions will be aligned on 2048-sector boundaries
Total free space is 2014 sectors (1007.0 KiB)

Number  Start (sector)    End (sector)  Size       Code  Name
   1            2048         2099199   1024.0 MiB  EF00  hypervisor-boot-S7A...
   2         2099200       211814399   100.0 GiB   8200  hypervisor-swap-S7A...
   3       211814400      3907029134   1.7 TiB     BF00  hypervisor-system-S...
NAME         TYPE PARTTYPENAME PARTLABEL                         LABEL FSTYPE MOUNTPOINT
nvme9n1     disk                                                                         
├─nvme9n1p1 part EFI System   hypervisor-boot-S7ABCDEFGHIJKLM
├─nvme9n1p2 part Linux swap   hypervisor-swap-S7ABCDEFGHIJKLM
└─nvme9n1p3 part Solaris root hypervisor-system-S7ABCDEFGHIJKLM
```

### Create ZFS pool and datasets for permanent Debian install

Create a ZFS pool named `hypervisor` with a mirror vdev with all the pool partitions created above, based on their stable identifiers.

```console
# zpool create \
      -o ashift=12 \
      -o autotrim=on \
      -o compatibility=grub2 \
      -o cachefile=/etc/zfs/zpool.cache \
      -o altroot=/mnt \
      -m none \
      hypervisor mirror "${DISK_POOL_PART_STABLE_IDENTIFIERS[@]}"
```

Create relevant datasets with reasonable attributes.

```console
# zfs set mountpoint=/ hypervisor
# zfs set compression=lz4 hypervisor
# zfs set acltype=posix hypervisor
# zfs set xattr=sa hypervisor
# zfs set atime=off hypervisor
# zpool set bootfs=hypervisor hypervisor

# zfs create -o compression=gzip -o setuid=off hypervisor/home

# zfs create -o canmount=off hypervisor/usr
# zfs create hypervisor/usr/local

# zfs create -o canmount=off hypervisor/var
# zfs create -o canmount=off hypervisor/var/lib
# zfs create hypervisor/var/lib/libvirt
# zfs create -o recordsize=64k hypervisor/var/lib/libvirt/images
# zfs create -o recordsize=1M hypervisor/var/lib/libvirt/images/iso
# chmod 711 /mnt/var/lib/libvirt/images /mnt/var/lib/libvirt/images/iso
# zfs create -o compression=gzip -o exec=off -o setuid=off hypervisor/var/log
# zfs create -o compression=gzip -o exec=off -o setuid=off -o atime=on hypervisor/var/mail
```

Now that we have partitions set up and an empty ZFS pool created with basic datasets, we can proceed to install Debian onto it.


## Install Debian with root on ZFS onto the target disks

First, mount a `tmpfs` at `/run`.

```console
# mkdir /mnt/run
# mount -t tmpfs tmpfs /mnt/run
# mkdir /mnt/run/lock
```

Install the base system.

```console
# debootstrap trixie /mnt
```

The output of this command is pretty long, and looks something like this:

```
I: Target architecture can be executed
I: Retrieving InRelease 
I: Checking Release signature
I: Valid Release signature (key id 41587F7DB8C774BCCF131416762F67A0B2C39DE4)
I: Retrieving Packages 
I: Validating Packages 
I: Resolving dependencies of required packages...
I: Resolving dependencies of base packages...
I: Checking component main on http://deb.debian.org/debian...
I: Retrieving adduser 3.152
I: Validating adduser 3.152
I: Retrieving apt 3.0.3
I: Validating apt 3.0.3
I: Retrieving apt-utils 3.0.3
I: Validating apt-utils 3.0.3
I: Retrieving base-files 13.8+deb13u5
I: Validating base-files 13.8+deb13u5
[...]
I: Configuring fdisk...
I: Configuring ifupdown...
I: Configuring libc-bin...
I: Base system installed successfully.
```


## Configure freshly installed Debian system

### Hostname

Configure the hostname for your server.

```console
# hostname my_server.my_domain.tld
# hostname > /mnt/etc/hostname
# echo -e '127.0.1.1\tmy_server.my_domain.tld my_server' >> /mnt/etc/hosts
```

### Initial network configuration

Find your network interface name by looking at the output of the following command:

```console
# ip addr show
```

For the 1 Gb/s ethernet interface on this motherboard, the interface name is `enP2p3s0`.

For this initial installation, configure this network interface with DHCP using Debian’s traditional networking configuration.

```console
# cat << EOF > /mnt/etc/network/interfaces.d/enP2p3s0
auto enP2p3s0
iface enP2p3s0 inet dhcp
EOF
```

### Debian package sources

Add relevant Debian package sources to APT’s `sources.list` file, including regular packages, security packages, and updates packages.

```console
# cat << EOF > /mnt/etc/apt/sources.list
deb http://deb.debian.org/debian trixie main contrib non-free-firmware
deb-src http://deb.debian.org/debian trixie main contrib non-free-firmware

deb http://deb.debian.org/debian-security trixie-security main contrib non-free-firmware
deb-src http://deb.debian.org/debian-security trixie-security main contrib non-free-firmware

deb http://deb.debian.org/debian trixie-updates main contrib non-free-firmware
deb-src http://deb.debian.org/debian trixie-updates main contrib non-free-firmware
EOF
```

### Prepare for switching to `chroot` to finalize Debian install setup

Some of the final stages of the install process require switching to a `chroot` to complete the setup of this fresh Debian install. However, we’ll need some of the disk environment variables from the current shell session to be made available in this separate `chroot` session.

To make this easier, please stash all of these variables into a helper script named `setup_disk_environment_variables`, which will be available in the `chroot` environment.

```console
# touch /mnt/root/setup_disk_environment_variables
# echo "BOOT_PART=${BOOT_PART}" >> /mnt/root/setup_disk_environment_variables
# echo "SWAP_PART=${SWAP_PART}" >> /mnt/root/setup_disk_environment_variables
# echo "NUMBER_OF_DISKS=${NUMBER_OF_DISKS}" >> /mnt/root/setup_disk_environment_variables

# echo "DISK_STABLE_IDENTIFIERS=()" >> /mnt/root/setup_disk_environment_variables
# for disk_stable_identifier in "${DISK_STABLE_IDENTIFIERS[@]}"
  do
      echo "DISK_STABLE_IDENTIFIERS+=(\"${disk_stable_identifier}\")" >> /mnt/root/setup_disk_environment_variables
  done

# echo "DISK_SERIAL_NUMBERS=()" >> /mnt/root/setup_disk_environment_variables
# for disk_serial_number in "${DISK_SERIAL_NUMBERS[@]}"
  do
      echo "DISK_SERIAL_NUMBERS+=(\"${disk_serial_number}\")" >> /mnt/root/setup_disk_environment_variables
  done

# echo "DISK_BOOT_PART_STABLE_IDENTIFIERS=()" >> /mnt/root/setup_disk_environment_variables
# for disk_boot_part_stable_identifier in "${DISK_BOOT_PART_STABLE_IDENTIFIERS[@]}"
  do
      echo "DISK_BOOT_PART_STABLE_IDENTIFIERS+=(\"${disk_boot_part_stable_identifier}\")" >> /mnt/root/setup_disk_environment_variables
  done

# echo "DISK_SWAP_PART_STABLE_IDENTIFIERS=()" >> /mnt/root/setup_disk_environment_variables
# for disk_swap_part_stable_identifier in "${DISK_SWAP_PART_STABLE_IDENTIFIERS[@]}"
  do
      echo "DISK_SWAP_PART_STABLE_IDENTIFIERS+=(\"${disk_swap_part_stable_identifier}\")" >> /mnt/root/setup_disk_environment_variables
  done
```

### Finalize Debian install setup inside of a `chroot`

Bind the virtual filesystems from the temporary system to the new system and `chroot` into it.

```console
# cd /mnt
# mount --make-private --rbind /dev  /mnt/dev
# mount --make-private --rbind /proc /mnt/proc
# mount --make-private --rbind /sys  /mnt/sys
# chroot /mnt /bin/bash --login
# cd
# source /root/setup_disk_environment_variables
```

#### Basic system environment

Configure the basic system environment.

```console
# apt update
# apt install console-setup locales
```

Here’s a quick description of what you should do in the dialogs presented by this install command.

 - **Configuring keyboard**
	 - Select the *Keyboard layout* you would like to use, such as *English (US)*.
 - **Configuring console-setup**
	 - For the *Encoding to use on the console*, select *UTF-8*.

Then reconfigure a few additional packages.

```console
# dpkg-reconfigure locales tzdata keyboard-configuration console-setup
```

Here’s what you should do in the dialogs presented by this reconfigure command.

 - **Configuring locales**
	 - For *Locales to be generated*, make sure to select at least `en_US.UTF-8`.
	 - For the *Default locale for the system environment*, select `en_US.UTF-8`.
 - **Configuring tzdata** and subsequent dialogs about geographic area and time zone
	 - Select the geographic area and time zone for the city or region you reside in.
	 - For example, if you live in California, in the dialog asking for your *Time zone*, select the *Los_Angeles* timezone.
 - **Configuring keyboard**
	 - For your *Keyboard model*, select *Generic 105-key PC*.
	 - Select the *Keyboard layout* you would like to use, such as *English (US)*.
	 - For the *Key to function as AltGr*, select *The default for the keyboard layout*.
	 - For the *Compose key*, select *No compose key*.
 - **Configuring console-setup**
	 - For the *Encoding to use on the console*, select *UTF-8*.
	 - For the *Character set to support*, select *# Latin 1 and Latin 5 - western Europe and Turkic languages*.
	 - For the *Font for the console*, select *Fixed*.
	 - For the *Font size*, select *8x16*.

Install an NTP service to synchronize time.

```console
# apt install systemd-timesyncd
```

Set a root password.

```console
# passwd
```

Install SSH server if you intend to log into this machine remotely.

```console
# apt install openssh-server
```

Make sure to either edit the `PermitRootLogin` setting in `/etc/ssh/sshd_config`, or add your public SSH key in `/root/.ssh/authorized_keys`.

#### Install ZFS kernel modules using DKMS

Install ZFS in the `chroot` environment for the new system.

```console
# apt install dpkg-dev linux-headers-generic linux-image-generic
# apt install zfs-initramfs
```

In the dialog titled *Configuring zfs-dkms*, review the notice about the incompatibility of open source licenses of Linux and OpenZFS, and make sure you feel comfortable with the limitations of this configuration.

Enable `REMAKE_INITRD` to ensure that when DKMS rebuilds the ZFS kernel modules after a Linux kernel upgrade, it also regenerates the initramfs afterwards, using `update-initramfs`.

```console
# echo REMAKE_INITRD=yes > /etc/dkms/zfs.conf
```

#### Install GRUB for UEFI booting

To create the EFI system partition, you’ll need to install `dosfstools` first.

```console
# apt install dosfstools
```

Format the boot partition for the first disk as a FAT32 partition.

```console
# mkdosfs -F 32 -s 1 -n EFI "${DISK_BOOT_PART_STABLE_IDENTIFIERS[0]}"
```

Make an empty directory at `/boot/efi`.

```console
# mkdir /boot/efi
```

Create the `/etc/fstab` with a line about this boot partition in the first disk, and then mount this partition.

```console
# echo "${DISK_BOOT_PART_STABLE_IDENTIFIERS[0]}" \
       "/boot/efi" vfat "defaults,nofail,x-systemd.device-timeout=5" \
       0 0 > /etc/fstab
# mount /boot/efi
```

Install utilities to prepare the EFI system partition with GRUB.

```console
# apt install grub-efi-arm64 shim-signed
```

Remove `os-prober`, to avoid error messages from `update-grub`. `os-prober` is only necessary in dual-boot configurations.

```console
# apt purge os-prober
```

Verify that the ZFS boot filesystem is recognized by GRUB.

```console
# grub-probe /boot
```

If the output of this command is simply:

```
zfs
```

then you can proceed to refresh the initramfs.

```console
# update-initramfs -c -k all
```

You should see output similar to this:

```
update-initramfs: Generating /boot/initrd.img-6.12.90+deb13.1-arm64
```

Edit `/etc/default/grub` to:
 - specify the root ZFS dataset in the `GRUB_CMDLINE_LINUX` configuration entry;
 - add helpful options in that same `GRUB_CMDLINE_LINUX` entry to more effectively debug the Linux boot sequence;
 - remove `quiet` from `GRUB_CMDLINE_LINUX_DEFAULT`;
 - uncomment the `GRUB_TERMINAL` entry to make sure it’s set to `console`.

```
[...]

GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX="root=ZFS=hypervisor fbcon=nodefer logo.nologo loglevel=4 console=tty0"

[...]

GRUB_TERMINAL=console
```

Update the boot configuration.

```console
# update-grub
```

You should see output similar to this:

```
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-6.12.90+deb13.1-arm64
Found initrd image: /boot/initrd.img-6.12.90+deb13.1-arm64
Adding boot menu entry for UEFI Firmware Settings ...
done
```

Install the boot loader.

```console
# grub-install --target=arm64-efi --efi-directory=/boot/efi \
     --bootloader-id=debian --recheck --no-floppy
```

You should see output similar to this:

```
Installing for arm64-efi platform.
Installation finished. No error reported.
```

#### Mirror GRUB and set up swap partitions

First unmount temporarily the primary boot partition, and navigate to the `/boot` directory.

```console
# umount /boot/efi
# cd /boot
```

Then, for each secondary disk:
 - mirror the contents of the primary EFI system partition to the secondary boot partition;
 - create a new secondary boot entry in the EFI boot manager;
 - add a line to the `/etc/fstab` about this secondary boot partition.

Additionally, in this loop, for all disks including the primary one:
 - prepare the swap partition;
 - add a line to the `/etc/fstab` about the swap partition.

```console
# for ((i = 0; i < NUMBER_OF_DISKS; i++))
  do
      disk_stable_identifier="${DISK_STABLE_IDENTIFIERS[${i}]}"
      if [[ ${i} -eq 0 ]]
      then
          ln -s efi efi0
      else
          disk_boot_part_stable_identifier="${DISK_BOOT_PART_STABLE_IDENTIFIERS[${i}]}"
          echo "Mirroring contents of primary EFI system partition: ${DISK_BOOT_PART_STABLE_IDENTIFIERS[0]} to secondary EFI system partition ${disk_boot_part_stable_identifier}..."
          dd if="${DISK_BOOT_PART_STABLE_IDENTIFIERS[0]}" of="${disk_boot_part_stable_identifier}"
          efibootmgr -c -g -d "${disk_stable_identifier}" -p ${BOOT_PART} \
              -L "debian-$((i + 1))" -l "\EFI\DEBIAN\GRUBAA64.EFI"
          mkdir "efi${i}"
          echo "${disk_boot_part_stable_identifier}" \
              "/boot/efi${i}" vfat "defaults,nofail,x-systemd.device-timeout=5" \
              0 0 >> /etc/fstab
      fi
      disk_swap_part_stable_identifier="${DISK_SWAP_PART_STABLE_IDENTIFIERS[${i}]}"
      echo "Preparing SWAP partition at ${disk_swap_part_stable_identifier}..."
      mkswap "${disk_swap_part_stable_identifier}"
      echo "${disk_swap_part_stable_identifier}" \
          none swap "sw,pri=1,nofail,x-systemd.device-timeout=5" \
          0 0 >> /etc/fstab
      echo
  done
```

You should see output similar to this:

```
Preparing SWAP partition at /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7ABCDEFGHIJKLM-part2...
Setting up swapspace version 1, size = 100 GiB (107374182400 bytes)
no label, UUID=d8b526e0-7efc-4995-9d34-195d1dd4a2b2

Mirroring contents of primary EFI system partition: /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7ABCDEFGHIJKLM-part1 to secondary EFI system partition /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7NOPQRSTUVWXYZ-part1...
2097152+0 records in
2097152+0 records out
1073741824 bytes (1.1 GB, 1.0 GiB) copied, 34.4139 s, 31.2 MB/s
[... redacted output from efibootmgr ...]
Preparing SWAP partition at /dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7NOPQRSTUVWXYZ-part2...
Setting up swapspace version 1, size = 100 GiB (107374182400 bytes)
no label, UUID=2caa0e1e-4b46-44cd-b7a3-4a08e1f0a88c
```

#### Fix filesystem mount ordering

We need to activate `zfs-mount-generator`. This makes `systemd` aware of the separate mountpoints, which is important for things like `/var/log` and `/var/tmp`.

```console
# mkdir /etc/zfs/zfs-list.cache
# touch /etc/zfs/zfs-list.cache/hypervisor
# zed -F &
```

Verify that `zed` updated the cache by making sure this new file is not empty.

```console
# cat /etc/zfs/zfs-list.cache/hypervisor
```

Once this file has data, stop `zed` by bringing it back to the foreground:

```console
# fg
```

and pressing Ctrl-C.

Now fix the paths to eliminate `/mnt`:

```console
# sed -Ei "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/*
```

#### Prepare for first boot

Create a ZFS snapshot of the initial installation.

```console
# zfs snapshot -r hypervisor@after-install-before-first-boot
```

Exit from the `chroot` environment.

```console
# exit
# cd
```

Back in the temporary Debian install, run these commands to unmount all filesystems.

```console
# mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | \
      xargs -i{} umount -lf {}
# zpool export -a
```

If export failed due to busy error, mounting it on boot will fail. You will need to reboot into the new permanent Debian system, wait for the `initramfs` prompt to come up, and enter the following:

```console
(initramfs) zpool import -f hypervisor
(initramfs) exit
```

Either way, power off the machine, remove the USB flash drive with the temporary Debian install, and power the machine back on.


## First boot into the fresh Debian install with root on ZFS

After forcibly importing the ZFS pool in the `(initramfs)` prompt if needed, wait for the newly installed system to boot normally.

Then login as `root`.

### Upgrade the minimal system

```console
# apt update
# apt upgrade
# apt dist-upgrade
```

### Install a regular set of software

```console
# apt install tasksel
# tasksel --new-install
```

Select and install *Standard system utilities*.

And that’s it, you now have a fully functional minimal Debian 13 Trixie install with root on ZFS!