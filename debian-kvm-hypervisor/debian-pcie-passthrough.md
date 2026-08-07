# PCIe passthrough for virtual machines on Debian KVM Hypervisor

Once you have a [basic setup for your Debian KVM Hypervisor](debian-kvm-libvirt-cockpit.md), you may want to set up PCIe passthrough for some of your hardware so it can be directly used by a virtual machine.

## Ensure IOMMU support is enabled

If your hypervisor machine is running on an ARM64 based system such as one with an Ampere Altra processor, chances are IOMMU support is already enabled out of the box. You can check it by looking for `iommu` in the output of `dmesg`.

```console
# dmesg | grep -i iommu | head -n 2
```

You should see output similar to this:

```
[    0.269034] iommu: Default domain type: Translated
[    0.269036] iommu: DMA domain TLB invalidation policy: strict mode
```

If you see various mentions of `iommu` in the output of `dmesg` like this, then you’re all set here.

If you were to try this on an Intel-based server, or an AMD-based one, you would need to explicitly enable the relevant system IOMMU driver by adding a few specific arguments for the Linux kernel in the `GRUB_CMDLINE_LINUX_DEFAULT` setting inside of `/etc/default/grub`. To be more specific, you would need to add `intel_iommu=on iommu=pt` for an Intel-based server, and `amd_iommu=on iommu=pt` for an AMD-based server. You’d then need to run `update-grub` and reboot the server.

On ARM64 enterprise platforms however, like those with an Ampere Altra processor, this step is a lot easier because the Linux kernel defaults to automatically enabling and configuring the system IOMMU (known as the System Memory Management Unit, or SMMUv3) right out of the box.


## Enable `vfio`-related kernel modules

The next important one-time step is to enable on the hypervisor machine a few Linux kernel modules that are needed for PCIe passthrough. This can be achieved by creating a file named `/etc/modules-load.d/vfio.conf` including the list of the relevant kernel modules to load.

```console
# cat << EOF > /etc/modules-load.d/vfio.conf
# /etc/modules-load.d/vfio.conf
#
# Kernel modules to load for PCIe passthrough support

vfio
vfio_iommu_type1
vfio_pci
EOF
```

Then reboot the hypervisor machine.

```console
# reboot
```

Confirm the kernel modules are successfully loaded now.

```console
# lsmod | grep -E "vfio|iommu"
```

You should see output similar to this:

```
vfio_pci               12288  0
vfio_pci_core          81920  1 vfio_pci
vfio_iommu_type1       40960  0
vfio                   53248  3 vfio_pci_core,vfio_iommu_type1,vfio_pci
```


## Identify PCIe addresses of relevant devices

Next, you need to correctly identify the PCIe addresses of the relevant devices. Knowing the manufacturer and model name of the device is key.

### Simple example of a single Broadcom adapter card

If the device you want to passthrough is one that you only have a single unit of connected to your server, or if you have multiple units of the same manufacturer and model name and you want to set them all up with PCIe passthrough to the same virtual machine, looking at the output of `lspci` may be enough.

For example, you can view your devices in a tree-like diagram like this, which is interesting because it should correspond to the block diagram of your motherboard.

```console
# lspci -tv
```

You may see output similar to this.

```
-[0003:00]-+-00.0  Ampere Computing, LLC Altra PCI Express Root Complex B
           +-01.0-[01-02]----00.0-[02]----00.0  ASPEED Technology, Inc. ASPEED Graphics Family
           +-03.0-[03]--
           +-05.0-[04]----00.0  Samsung Electronics Co Ltd NVMe SSD Controller S4LV008[Pascal]
           \-07.0-[05]--
-[0004:00]-+-00.0  Ampere Computing, LLC Altra PCI Express Root Complex B
           +-01.0-[01]----00.0  Broadcom / LSI Fusion-MPT 12GSAS/PCIe Secure SAS38xx
           \-05.0-[02]--
-[0005:00]-+-00.0  Ampere Computing, LLC Altra PCI Express Root Complex B
           +-01.0-[01]--
           \-05.0-[02]--
```

Here, we see, among other things, an NVMe SSD from Samsung, and a Broadcom SAS adapter.

Deriving the full PCIe address from this tree-like diagram is a bit finicky, so you should probably confirm it with another simpler variant of the `lspci` output.

```console
# lspci -nnk | grep -A 3 "[0-9].*Broadcom / LSI"
```

You should see output similar to this:

```
0004:01:00.0 Serial Attached SCSI controller [0107]: Broadcom / LSI Fusion-MPT 12GSAS/PCIe Secure SAS38xx [1000:00e6]
	Subsystem: Broadcom / LSI 9500-16i Tri-Mode HBA [1000:4050]
	Kernel driver in use: mpt3sas
	Kernel modules: mpt3sas
```

So in this case, the full PCIe address for this Broadcom SAS card, is `0004:01:00.0`. We can also see here that this card is actually a Broadcom 9500-16i Tri-Mode Storage Adapter, and that it’s currently using the `mpt3sas` kernel driver.

### Advanced example of one of several identical NVMe drives

If you’re into high speed storage like I am, you might also want to passthrough one or more NVMe drives; however it’s a lot easier to end up with multiple drives of the same manufacturer and model name connected, and if you only want to passthrough specific ones, you need to be careful in this phase of identifying their PCIe addresses.

For this kind of scenario, the combination of `nvme list` and `lsblk` should prove to be very helpful. With `nvme list`, you can easily identify the model name and serial number for each of your NVMe drives, alongside their block device. You can then supplement this by confirming you’ve identified the correct drives by eyeballing the output of `lsblk`, which will show you the partitions on the drives, if any.

Let’s assume you identified `nvme8n1` as the drive you want to set up with PCIe passthrough. One of the easiest ways to identify the corresponding PCIe address of this device is by looking for `nvme8` (notice the removal of `n1` from what we found earlier) in the output of `dmesg`.

```console
# dmesg | grep "nvme8: pci function"
```

You may see output similar to this:

```
[    1.452348] nvme nvme8: pci function 0000:01:00.0
```

And there you go, the full PCIe address of this NVMe drive is `0000:01:00.0`.

Let’s confirm what this device looks like in the output of `lspci`.

```console
# lspci -nnk | grep -A 3 "0000:01:00.0"
```

You should see output similar to this:

```
0000:01:00.0 Non-Volatile memory controller [0108]: Samsung Electronics Co Ltd NVMe SSD Controller S4LV008[Pascal] [144d:a80c]
	Subsystem: Samsung Electronics Co Ltd Device [144d:a801]
	Kernel driver in use: nvme
	Kernel modules: nvme
```

This device actually corresponds to a Samsung SSD 990 PRO 2TB, although only `nvme list` could show us this model name.


## Reserve relevant devices for PCIe passthrough

Let’s reserve the devices identified above for PCIe passthrough.

 - Broadcom 9500-16i Tri-Mode Storage Adapter
	 - PCIe address: `0004:01:00.0`
	 - Kernel driver: `mpt3sas`
 - Samsung SSD 990 PRO 2TB
	 - PCIe address: `0000:01:00.0`
	 - Kernel driver: `nvme`

To do that, we’ll create a new script named `vfio-pci-override.sh` in `/etc/initramfs-tools/scripts/init-top`, which is meant to be executed at boot time.

```sh
#!/bin/sh
#
#  /etc/initramfs-tools/scripts/init-top/vfio-pci-override.sh
#
#  Server initialization script to reserve certain hardware devices
#  for PCIe passthrough.
#

PREREQ=""

prereqs()
{
    echo "$PREREQ"
}

case $1 in
    prereqs)
        prereqs
        exit 0
        ;;
esac

reserve_device_for_pcie_passthrough() {

    # Unbind from original driver (fails silently if not bound yet).
    echo "$2" > "/sys/bus/pci/drivers/$1/unbind" 2>/dev/null || true

    # Use driver_override to reserve these specific devices for vfio-pci.
    # This prevents ANY other driver from binding to them.
    echo "vfio-pci" > "/sys/bus/pci/devices/$2/driver_override"

    # Trigger driver binding - only vfio-pci can bind due to driver_override
    echo "$2" > "/sys/bus/pci/drivers_probe"

}

# Broadcom 9500-16i HBA
reserve_device_for_pcie_passthrough mpt3sas "0004:01:00.0"

# Samsung SSD 990 PRO 2TB drive
reserve_device_for_pcie_passthrough nvme "0000:01:00.0"
```

Update the permissions of this script so it can be executed.

```console
# chmod +x /etc/initramfs-tools/scripts/init-top/vfio-pci-override.sh
```

Now you need to refresh the initramfs so it includes this initialization script.

```console
# update-initramfs -c -k all
```

You should see output similar to this:

```
update-initramfs: Generating /boot/initrd.img-6.12.90+deb13.1-arm64
```

Then reboot the hypervisor machine.

```console
# reboot
```

Once the machine has successfully rebooted, check the corresponding devices again with `lspci`.

```console
# lspci -nnk | grep -A 3 -E "0000:01:00.0|0004:01:00.0"
```

You should see output similar to this:

```
0000:01:00.0 Non-Volatile memory controller [0108]: Samsung Electronics Co Ltd NVMe SSD Controller S4LV008[Pascal] [144d:a80c]
	Subsystem: Samsung Electronics Co Ltd Device [144d:a801]
	Kernel driver in use: vfio-pci
	Kernel modules: nvme
--
0004:01:00.0 Serial Attached SCSI controller [0107]: Broadcom / LSI Fusion-MPT 12GSAS/PCIe Secure SAS38xx [1000:00e6]
	Subsystem: Broadcom / LSI 9500-16i Tri-Mode HBA [1000:4050]
	Kernel driver in use: vfio-pci
	Kernel modules: mpt3sas
```

This output above shows these devices are ready to be used by a virtual machine with PCIe passthrough because of this important line, which is present for each device.

```console
	Kernel driver in use: vfio-pci
```


## Assign devices to a specific virtual machine

This is where, if you have an existing virtual machine created with KVM/`libvirt`, adding those devices to that machine is a lot easier with the [Cockpit web-based graphical user interface](debian-kvm-libvirt-cockpit.md).

In Cockpit, go to the *Virtual machines* section and select the virtual machine you’re interested in. Make sure to turn it off ahead of this operation.

Scroll down to the *Host devices* section, and click the *Add host device* button.

At the top of the modal form titled *Add host device*, switch the *Type* from *USB* to *PCI*.

Select the relevant devices, i.e. the ones with a PCIe address that matches what you entered above in the `/etc/initramfs-tools/scripts/init-top/vfio-pci-override.sh` script. Then click the *Add* button.

Quick tip by the way: if you care that these devices be discovered in a certain order by the virtual machine, then you can add them one at a time in this configuration user interface, in the order you want. After submitting the form multiple times, Cockpit may show the devices in a different order than you added them in, but this appears to be a display only quirk.

You’re all set! Start your virtual machine again, and you should see that it now has direct access to those additional PCIe devices!