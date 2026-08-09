# Homelab Documentation

This repository contains documentation on setting up a Debian KVM Hypervisor and various services running on FreeBSD for a production small scale homelab.

## Key technologies

A number of technology choices for my homelab derive from two key decisions.

 - ARM64 architecture for its great balance of power and efficiency;
 - ZFS storage for its end-to-end data integrity guarantees combined with its fantastic storage management features.

Consequently, back in January 2026 when I set this up, I couldn’t use something like Proxmox VE since it wasn’t supported on ARM64. [^1] [^2]

[^1]: On Proxmox VE for ARM64 being unsupported up until the first half of 2026: [Proxmox VE on aarch64 (arm64)](https://forum.proxmox.com/threads/proxmox-on-aarch64-arm64.121925/page-5#post-789519)

[^2]: Eventually, [Proxmox VE became officially supported on ARM64 in August 2026](https://forum.proxmox.com/threads/proxmox-virtual-environment-now-available-for-64-bit-arm-arm64.185527/); but it’s worth noting that it’s only fully supported on the NVIDIA Grace Hopper and NVIDIA Vera platforms, with other ARM64 based platforms getting best-effort support; based on [Jeff Geerling’s early experiments on an Ampere Altra Max platform](https://forum.proxmox.com/threads/testing-proxmox-ve-on-ampere-altra-max-armv8.185541/), Proxmox VE 9.2 might not be ready for prime time on this kind of platform yet.

That’s why I went with a KVM Hypervisor approach instead.


## Physical server nodes

In order to have a decently high ceiling for performance and expandability while keeping power consumption manageable, I tend to gravitate towards consolidating most of my services in a single powerful physical server node.

However, I’m also beginning to embrace a disaggregation approach in one particular area: GPU compute, mostly for the purpose of AI and machine learning inference.

### Main server for virtualization and storage

A key architectural decision for this server was to use an Ampere Altra processor, which is a powerful processor with high core count, while remaining energy efficient.

One of the important consequences of this choice is that it’s a PCIe 4.0 platform.

 - **Chassis**: Supermicro CSE-846BE1C8-R1K23B4 4U Chassis
	 - Power supplies and fans replaced with quieter Noctua models.
	 - Power distribution board replaced for another one with PCIe power connectors.
 - **Motherboard:** ASRock Rack ALTRAD8UD2-1L2Q
	 - **General purpose networking**
		 - Broadcom BCM57414 NIC with 2 SFP28 cages (25 Gb/s)
		 - Intel i210 NIC with 1 RJ45 port (1 Gb/s)
	 - **Dedicated management networking (IPMI)**
		 - Realtek RTL8211E with 1 RJ45 port (1 Gb/s)
 - **Processor:** Ampere Altra Q64-30 64-Core 3.00GHz  CPU
 - **Memory:** 256 GB of Samsung DDR4 (PC4-25600), ECC Registered
 - **Hypervisor storage**
	 - **Add-in cards:** 2 × Icy Dock ExpressSlot Slide 4 Bay M.2 NVMe SSD Adapter Card
	 - **Fast NVMe SSDs**
		 - **System**: 2 × Samsung 990 PRO 2 TB - NVMe M.2 2280 SSD
		 - **FreeBSD VM**: 3 × Samsung 990 PRO 2 TB - NVMe M.2 2280 SSD
		 - **Incubator VMs**: 2 × Samsung 990 PRO 4 TB - NVMe M.2 2280 SSD
 - **Mass tiered storage**
	 - **Host bus adapter**: Broadcom 9500-16i Tri-Mode Storage Adapter
	 - **Storage backplane**: Single SAS-3 expander with 8 NVMe (Supermicro BPN-SAS3-846EL1-N8)
	 - **Hard drives**: 6 × WD Red Plus 14 TB NAS Internal Hard Drive
	 - **Fast NVMe SSDs**
		 - 4 × Samsung PM9A3 1.92 TB NVMe Enterprise SSD
		 - 2 × Intel Optane 905P Series 960 GB

### GPU compute node for AI inference

For GPU compute, I chose the Acer Veriton GN100 AI Mini Workstation, which is powered by the NVIDIA GB10 Grace Blackwell superchip, equipped with a large amount of unified memory at a reasonable price and power envelope. The addition of a ConnectX-7 NIC is a great bonus, and offers the potential of expanding to a cluster of GPU compute nodes down the road.

This mini workstation is Acer’s variant of the NVIDIA DGX Spark, and it has been found to have the coolest overall thermal profile in a thorough comparison of NVIDIA GB10 based workstations by StorageReview. [^3]

[^3]: [Acer Veriton GN100 Review: A Standout in the NVIDIA Spark Ecosystem](https://www.storagereview.com/review/acer-veriton-gn100-review-a-standout-in-the-nvidia-spark-ecosystem)

 - **Model**: Acer Veriton GN100 AI Mini Workstation
 - **Processor**: NVIDIA GB10 (Grace Blackwell Superchip) 20-core Arm CPU
 - **GPU**: NVIDIA Blackwell GPU (integrated)
 - **Memory**: 128 GB LPDDR5x, unified system memory
 - **Storage**: 4 TB NVMe SSD (PCIe 4.0)
 - **Network**
	 - One RJ45 (10 Gb/s)
	 - NVIDIA ConnectX-7 NIC (200 Gb/s × 2 QSFP)


## Documentation overview

These documents are produced in the course of my journey to set up my own server infrastructure for personal use, largely to increase my level of digital sovereignty.

While each document attempts to cover its own topic thoroughly, it’s possible that some document will rely on pre-requisites covered in another document. Sometimes, that may be explicitly called out, whereas in other instances it may not be obvious.

If you suspect there may be an unspecified pre-requisite in any of these documents, it may be helpful to know the order of documents which corresponds to how I configured my own server.

### Debian KVM Hypervisor

 1. [Debian with Root on ZFS on Ampere Altra Server](debian-kvm-hypervisor/debian-root-on-zfs-ampere-altra.md)
 2. [Creating an unprivileged user on Debian](debian-kvm-hypervisor/debian-unprivileged-user.md)
 3. [Fix environment variables for administrator account on Debian](debian-kvm-hypervisor/debian-fix-root-environment-variables.md)
 4. [Useful command-line tools for Debian](debian-kvm-hypervisor/debian-command-line-tools.md)
 5. [Networking configuration for Debian KVM Hypervisor](debian-kvm-hypervisor/debian-networking-configuration.md)
 6. [Using KVM/`libvirt` and Cockpit to create and manage virtual machines](debian-kvm-hypervisor/debian-kvm-libvirt-cockpit.md)
 7. [PCIe passthrough for virtual machines on Debian KVM Hypervisor](debian-kvm-hypervisor/debian-pcie-passthrough.md)

### DGX Spark

 1. [Dedicated compute fabric (25 Gb/s) between DGX Spark and separate virtualization/storage server](dgx-spark/dgx-spark-dedicated-compute-fabric-with-25gbe-passive-dac.md)

### FreeBSD Server

 1. [FreeBSD on Ampere Altra Server](freebsd-server/freebsd-ampere-altra.md)
 2. [Remote access with SSH on FreeBSD](freebsd-server/freebsd-remote-access-ssh.md)
 3. [Synchronizing time with NTP on FreeBSD](freebsd-server/freebsd-network-time-synchronization-ntp.md)
 4. [Network file sharing with NFS on FreeBSD](freebsd-server/freebsd-network-file-sharing-nfs.md)
 5. [FreeBSD guest virtual machine on Debian KVM hypervisor host](freebsd-server/freebsd-guest-on-debian-kvm-hypervisor.md)
 6. [Custom package management for FreeBSD with `poudriere`](freebsd-server/freebsd-poudriere.md)
 7. [Useful command-line tools for FreeBSD](freebsd-server/freebsd-command-line-tools.md)
 8. [Using a Unicode locale on FreeBSD](freebsd-server/freebsd-unicode-locale.md)
 9. [Creating an unprivileged user on FreeBSD](freebsd-server/freebsd-unprivileged-user.md)
 10. [Mount special file systems on FreeBSD](freebsd-server/freebsd-special-file-systems.md)
 11. [Modular system configuration on FreeBSD](freebsd-server/freebsd-modular-system-configuration.md)
 12. [Modular periodic scripts configuration on FreeBSD](freebsd-server/freebsd-modular-periodic-scripts-configuration.md)
 13. [Configuring firewall for FreeBSD with `pf`](freebsd-server/freebsd-firewall.md)
 14. [Authoritative DNS server on FreeBSD with BIND](freebsd-server/freebsd-dns-bind.md)
 15. [Faster DNS zone replication on FreeBSD with `nsnotifyd`](freebsd-server/freebsd-faster-dns-replication-nsnotifyd.md)
