# Using KVM/`libvirt` and Cockpit to create and manage virtual machines

While KVM and `libvirt` are great tools for virtualization on Debian GNU/Linux, some virtual machine management tasks can be easier to accomplish with the Cockpit web-based graphical user interface.

## Install Cockpit

In order to use Cockpit to manage virtual machines, you need to install both `cockpit` and `cockpit-machines`.

```console
# apt install cockpit cockpit-machines
```

You can then access the Cockpit interface in your web browser at the address `https://my_server.my_domain.tld:9090/`.


## Prepare installation image

Going forward, let’s assume you want to create a new virtual machine running FreeBSD.

On the hypervisor machine, download latest FreeBSD 15 image for the ARM64 architecture.

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


## Set up a storage pool for virtual machines

For KVM and `libvirt` to manage effectively the storage associated with your virtual machines, you will need to set up a dedicated storage pool. This isn’t in the sense of a dedicated ZFS pool; in fact, this can be created deep inside of your existing ZFS pool named `hypervisor`.

A common place to put the storage associated with KVM/`libvirt` virtual machines is `/var/lib/libvirt/images`. In [a previous guide](debian-root-on-zfs-ampere-altra.md#create-zfs-pool-and-datasets-for-permanent-debian-install), we already created a ZFS dataset named `hypervisor/var/lib/libvirt/images`.

Here’s how you can define a corresponding KVM/`libvirt` storage pool with the ZFS storage driver. First install `libvirt-daemon-driver-storage-zfs`.

```console
# apt install libvirt-daemon-driver-storage-zfs
```

Then define the storage pool with `--type zfs`, start it now, and make sure it starts automatically in the future.

```console
# virsh pool-define-as --name hypervisor-vm-pool \
      --type zfs \
      --source-name hypervisor/var/lib/libvirt/images
# virsh pool-start hypervisor-vm-pool
# virsh pool-autostart hypervisor-vm-pool
```


## Create a virtual machine with managed storage

With the `hypervisor-vm-pool` set up above, you can now create a volume for a new virtual machine. Feel free to customize the name `my_vm` to your liking, as well as the storage capacity of 200 GB.

```console
# virsh vol-create-as hypervisor-vm-pool my_vm-disk0 200G
```

Even though Cockpit’s virtual machines management interface is generally easier to use for most simple tasks, on my Debian KVM hypervisor, it would consistently fail to create the virtual machine with Secure Boot enabled. Sadly, the FreeBSD installer couldn’t even start with this kind of virtual machine firmware.

Using the command-line on the hypervisor machine does the trick to create the virtual machine though.

```console
# virt-install \
      --connect qemu:///system \
      --name my_vm \
      --memory 32768 \
      --vcpus 8 \
      --cdrom /var/lib/libvirt/images/iso/FreeBSD-15.0-RELEASE-arm64-aarch64-dvd1.iso \
      --disk vol=hypervisor-vm-pool/my_vm-disk0,bus=scsi \
      --os-variant freebsd14.2 \
      --boot firmware=efi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no \
      --graphics vnc \
      --noautoconsole
```

Here are some of the important parts of this command.
 - The machine’s name is set to `my_vm`.
 - The machine is given 32 GB of RAM and 8 vCPUs as host passthrough.
 - The FreeBSD OS image is mounted as a CD-ROM.
 - The disk image is provided as a volume with the SCSI bus.
	 - Getting the disk to be visible by FreeBSD is a bit tricky, as it wouldn’t recognize the disk with `bus=virtio`.
	 - As a viable alternative, the drive works consistently with FreeBSD using `bus=scsi`.
 - The OS variant is set to `freebsd14.2`, which is the most recent FreeBSD version known by `libvirt`.
 - The boot firmware is specifically configured with Secure Boot disabled.

Go over to Cockpit to find your new virtual machine, and open its console. You should see it boot nicely into the FreeBSD installer.

Enjoy your new virtual machine!