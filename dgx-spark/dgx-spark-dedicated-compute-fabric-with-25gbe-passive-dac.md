# Dedicated compute fabric (25 Gb/s) between DGX Spark and separate virtualization/storage server

For a small homelab that uses a disaggregation approach for GPU compute, you may want to set up a dedicated compute fabric between your GPU compute node and your main virtualization/storage server.

This guide will show you how to establish an inexpensive, persistent, and medium-speed (25 Gb/s) link using a passive Direct Attach Copper (DAC) cable between a virtualization/storage server and an NVIDIA GB10 Grace Blackwell based workstation similar to the NVIDIA DGX Spark.

## Tradeoffs between Direct Attach Copper solution and optimized network switch based approach

While 25 Gb/s is a much lower speed than what the ConnectX-7 NIC in the Spark can achieve, this approach can be a good fit as a starting point if the virtualization/storage server already has a built-in NIC with SFP28 cages for 25 Gb/s networking, and you’re not ready to devote one of the precious PCIe slots on your server motherboard to a very fast NIC.

Furthermore, if you’re willing to accept this compromise of a more medium speed of 25 Gb/s for this kind of a very small setup with only two nodes, you can avoid the large expense of a network switch optimized for the capabilities of the ConnectX-7 NIC in the Spark. Such switches, like the [Mikrotik CRS804 DDQ](https://mikrotik.com/product/crs804_ddq) or the [Mikrotik CRS812 DDQ](https://mikrotik.com/product/crs812_ddq) usually go for well over $1,000.

On the flip-side, in order to use an SFP28 Direct Attach Copper cable, we need to contend with the fact that the Spark only has QSFP cages, which are not directly compatible with an SFP28 connector. Thankfully, there is a simple and inexpensive solution to this problem: a QSA28 adapter.

A QSA28 adapter is a passive mechanical converter that enables a smooth cost-effective connection between a single lane transceiver/cable and a quad lane port. It allows you to connect the SFP28 DAC cable to one of the QSFP ports on the Spark.

Here are the specific items I ended up purchasing for this connection.

 - **SFP28 DAC cable**: 10Gtek 25GBASE-CR SFP28 passive direct attach copper cable
 - **QSA28 adapter**: 10Gtek QSFP28 to SFP28 adapter, compatible with Mellanox MAM1Q00A-QSA28

These items can be purchased for less than $100 combined, and are readily available via online retailers.

Now let’s review the hardware configuration of the two nodes we’re about to connect.


## Hardware configuration

Please check the [parent README document for detailed configuration of the hardware](../README.md#physical-server-nodes) used in this guide.

Let‘s summarize the main points related to networking though.

### Main server for virtualization and storage

 - **Motherboard:** ASRock Rack ALTRAD8UD2-1L2Q
 - **Network**: Broadcom BCM57414 NIC with 2 SFP28 cages (25 Gb/s)

This server was set up following the various guides listed [here](../README.md#debian-kvm-hypervisor), including this relevant [guide on networking](../debian-kvm-hypervisor/debian-networking-configuration.md) where you can see how to transition from the traditional networking configuration to using NetworkManager.

It’s configured with the hostname `my_server`.

### GPU compute node for AI inference

This node is the Acer Veriton GN100 AI Mini Workstation, Acer’s variant of the NVIDIA DGX Spark.

 - **Model**: Acer Veriton GN100 AI Mini Workstation
 - **Processor**: NVIDIA GB10 (Grace Blackwell Superchip) 20-core Arm CPU
 - **GPU**: NVIDIA Blackwell GPU (integrated)
 - **Network**
	 - One RJ45 (10 Gb/s)
	 - NVIDIA ConnectX-7 NIC (200 Gb/s × 2 QSFP)

This workstation was set up with the name `spark`, or more colloquially *the Spark*.


## Network signaling considerations

The Spark’s ConnectX-7 NIC exposes two physical QSFP cages which are arranged with a pretty unusual topology. [^1] These ports are NDR-class, meaning they natively operate at 200 Gb/s using PAM4 signaling.

[^1]: See the great deep dive on the networking topology of the ConnectX-7 NIC in this great article from ServeTheHome: [The NVIDIA GB10 ConnectX-7 200GbE Networking is Really Different](https://www.servethehome.com/the-nvidia-gb10-connectx-7-200gbe-networking-is-really-different/)

Conversely, `my_server`’s onboard Broadcom BCM57414 NIC provides two SFP28 ports running at up to 25 Gb/s using NRZ signaling — a different modulation scheme from PAM4.

Since a QSA28 adapter is a passive mechanical converter between a QSFP cage and an SFP28 receptacle, it simply wires the first lane of the QSFP connector straight through to the SFP28 side with no rate conversion or re-timing.

Despite the mismatch in native signaling rates, the ConnectX-7 NIC can fall back to 25 Gb/s NRZ on a single lane when presented with an SFP28 module, but this requires manually forcing the link speed on both sides, as auto-negotiation alone settles at 10 Gb/s.


## Network design

The compute fabric uses a dedicated `/24` subnet that does not overlap with the main LAN and is not routed through the router for the LAN, making it suitable for high-bandwidth compute workloads and as a foundation for future RoCEv2/RDMA configuration.

To be more specific, we’ll be using the `10.7.0.0/24` subnet for this compute fabric.

Neither host is configured with a default gateway on this interface, so all traffic on `10.7.0.x` stays strictly between the server and the Spark.

| Address      | Host        | Interface     |
|--------------|-------------|---------------|
| 10.7.0.1     | `my_server` | `enP2s1f0np0` |
| 10.7.0.2     | `spark`     | `enp1s0f0np0` |
| 10.7.0.3–254 | —           | Reserved      |

The Spark’s second ConnectX-7 interface on the same physical port (`enP2p1s0f0np0`) is left unaddressed. It shares the same physical wire as `enp1s0f0np0` via the QSA28 adapter and has no independent use in this configuration.


## Physical connection

On the Spark, when nothing is plugged to the QSFP cages for the ConnectX-7 NIC, it appears that the firmware decides there’s no reason to keep the associated resources alive, and tears them down to save power. Due to this optimization, it may be safer to start with the physical connections after powering off the Spark.

Insert the QSA28 adapter into the first QSFP cage on the Spark (i.e. the one closest to the 10 Gb/s RJ45 port).

Then insert one end of the SFP28 DAC cable to the QSA28 adapter, and the other end to the server’s first SFP28 port. With the ASRock Rack ALTRAD8UD2-1L2Q motherboard, that is the SFP28 cage at the bottom.

Power the Spark back on.


## Preliminary link checks

### Required software packages

As we turn to software configuration for this network connection, make sure you have the `ethtool` and `iperf3` packages installed on both machines.

```console
# apt install ethtool iperf3
```

### Check the link on the Spark

Once the Spark is fully up and running, run the following command to check the state of this link.

```console
# ip link show | grep -E "enp1s0f0np0|enP2p1s0f0np0"
```

You may see output similar to this.

```
3: enp1s0f0np0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
5: enP2p1s0f0np0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
```

Seeing those two network interfaces listed with the `state UP` indicator confirms that the physical link is working.

### Check the link on the virtualization/storage server

Then, on the virtualization and storage server, check the recent messages from the `bnxt` driver in the output of `dmesg`.

```console
# dmesg | grep -i bnxt | tail -30
```

You may see a line similar to this.

```
[21524.539598] bnxt_en 0002:01:00.0 enP2s1f0np0: NIC Link is Up, 10000 Mbps (NRZ) full duplex, Flow control: none
```

Now you can check more information about this network interface.

```console
# ethtool enP2s1f0np0 | grep -E "Speed|Duplex|Auto-negotiation|Port|Link detected"
```

You may see output similar to this.

```
	Speed: 10000Mb/s
	Duplex: Full
	Auto-negotiation: on
	Port: Direct Attach Copper
	Link detected: yes
```

As you can see, the BCM57414 NIC detected the DAC, trained and auto-negotiated a link at 10 Gb/s (NRZ).

This is a good start, but we clearly have more work to do for this link to be set up at a 25 Gb/s speed.


## Configure the network connection on the virtualization/storage server

Create a new NetworkManager connection for the compute fabric interface, assigning a static IP address, forcing the link to 25 Gb/s, and ensuring no default gateway is installed via this interface.

```console
# nmcli connection add \
    type ethernet \
    ifname enP2s1f0np0 \
    con-name compute-fabric \
    ipv4.method manual \
    ipv4.addresses 10.7.0.1/24 \
    ipv4.never-default true \
    ipv6.method disabled \
    802-3-ethernet.speed 25000 \
    802-3-ethernet.duplex full \
    connection.autoconnect yes
```

Bring up the connection.

```console
# nmcli connection up compute-fabric
```


## Configure the network connection on the Spark

Create an equivalent NetworkManager connection on the Spark.

```console
# nmcli connection add \
    type ethernet \
    ifname enp1s0f0np0 \
    con-name compute-fabric \
    ipv4.method manual \
    ipv4.addresses 10.7.0.2/24 \
    ipv4.never-default true \
    ipv6.method disabled \
    802-3-ethernet.speed 25000 \
    802-3-ethernet.duplex full \
    connection.autoconnect yes
```

Bring up the connection.

```console
# nmcli connection up compute-fabric
```


## Test the connection

### Confirm the link is up

On the virtualization/storage server, confirm the link is up at the expected speed.

```console
# ethtool enP2s1f0np0 | grep -E "Speed|Duplex|Auto-negotiation|Port|Link detected"
```

You should see the following output.

```
	Speed: 25000Mb/s
	Duplex: Full
	Auto-negotiation: off
	Port: Direct Attach Copper
	Link detected: yes
```

Similarly, on the Spark, confirm the link is up at the expected speed.

```console
# ethtool enp1s0f0np0 | grep -E "Speed|Duplex|Auto-negotiation|Port|Link detected"
```

You should see the following output.

```
	Speed: 25000Mb/s
	Duplex: Full
	Auto-negotiation: off
	Port: Direct Attach Copper
	Link detected: yes
```

### Verify connectivity

Confirm bidirectional connectivity with ping from each host.

From the Spark, ping the virtualization/storage server at address `10.7.0.1`.

```console
# ping -c4 10.7.0.1
```

From the virtualization/storage server, ping the Spark at address `10.7.0.2`.

```console
# ping -c4 10.7.0.2
```

You may see output similar to this.

```
PING 10.7.0.2 (10.7.0.2) 56(84) bytes of data.
64 bytes from 10.7.0.2: icmp_seq=1 ttl=64 time=2.23 ms
64 bytes from 10.7.0.2: icmp_seq=2 ttl=64 time=0.688 ms
64 bytes from 10.7.0.2: icmp_seq=3 ttl=64 time=0.553 ms
64 bytes from 10.7.0.2: icmp_seq=4 ttl=64 time=0.453 ms

--- 10.7.0.2 ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3018ms
rtt min/avg/max/mdev = 0.453/0.981/2.232/0.726 ms
```

Both directions should show zero packet loss and sub-millisecond round-trip times after the first packet.

### Verify throughput

With `iperf3` installed on both hosts, run a throughput test to confirm the link is performing near line rate.

On the Spark, start an `iperf3` server.

```console
# iperf3 -s
```

On the virtualization/storage server, run the client with four parallel streams. The `-P 4` flag opens four parallel TCP streams because a single stream rarely saturates a 25 Gb/s link on its own due to TCP congestion control and single-core packet generation limits.

```console
# iperf3 -c 10.7.0.2 -t 10 -P 4
```

Expected aggregate throughput is approximately 23.4 Gb/s, which is around 93% of the theoretical 25 Gb/s line rate after protocol overhead.

You may also want to run a similar test in reverse, with the virtualization/storage server running the `iperf3` server instead.


## Tidy up NetworkManager connections on the Spark

When NetworkManager first encounters the ConnectX-7 interfaces at boot, it auto-generates DHCP connections for each one. Now that we have set up a `compute-fabric` connection, these are stale and can be removed for clarity.

### Inspect network devices and connections

You can get some initial insight into which network devices are connected and which connections they map to with the following command.

```console
# nmcli device status
```

You may see output similar to this.

```
DEVICE          TYPE      STATE                   CONNECTION
enP7s7          ethernet  connected               Wired connection 3
wlP9s9          wifi      connected               YourWiFiNetwork
enp1s0f0np0     ethernet  connected               compute-fabric
lo              loopback  connected (externally)  lo
docker0         bridge    connected (externally)  docker0
enP2p1s0f0np0   ethernet  disconnected            --
p2p-dev-wlP9s9  wifi-p2p  disconnected            --
enP2p1s0f1np1   ethernet  unavailable             --
enp1s0f1np1     ethernet  unavailable             --
```

Next up, you can list all the connections with the following command.

```console
# nmcli -f NAME,TYPE,DEVICE connection show
```

You may see output similar to this.

```
NAME                TYPE      DEVICE
Wired connection 3  ethernet  enP7s7
YourWiFiNetwork     wifi      wlP9s9
compute-fabric      ethernet  enp1s0f0np0
lo                  loopback  lo
docker0             bridge    docker0
Wired connection 1  ethernet  --
Wired connection 2  ethernet  --
Wired connection 4  ethernet  --          
Wired connection 5  ethernet  --
```

From this, we can derive the following points.

 1. *Wired connection 3*, which is connected via the device `enP7s7`, corresponds to the 10 Gb/s RJ45 port on the Spark.
 2. The other wired connections likely correspond to auto-generated stale DHCP connections for the ConnectX-7 NIC.

To find even more solid evidence for the second point, inspect which interfaces the auto-generated connections are bound to.

```console
# nmcli connection show "Wired connection 1" | grep -E "connection\.interface-name|ipv4\.method"
# nmcli connection show "Wired connection 2" | grep -E "connection\.interface-name|ipv4\.method"
# nmcli connection show "Wired connection 4" | grep -E "connection\.interface-name|ipv4\.method"
# nmcli connection show "Wired connection 5" | grep -E "connection\.interface-name|ipv4\.method"
```

For each of these, you should see output similar to this.

```
connection.interface-name:              enP2p1s0f0np0
ipv4.method:                            auto
```

Confirm that all of these connections are set up with `ipv4.method: auto`, and correspond to ConnectX-7 interfaces.

### Delete auto-generated connections for the ConnectX-7 NIC

Once you’ve confirmed that these connections are indeed the auto-generated stale DHCP connections for the ConnectX-7 NIC, you can safely delete them.

```console
# nmcli connection delete "Wired connection 1"
# nmcli connection delete "Wired connection 2"
# nmcli connection delete "Wired connection 4"
# nmcli connection delete "Wired connection 5"
```

For each of these commands, you should see output similar to this.

```
Connection 'Wired connection 1' (8402ac9a-5283-3d5d-9123-a90365c4bb31) successfully deleted.
```

Then mark the unused ConnectX-7 interfaces as unmanaged to prevent NetworkManager from auto-generating new connections for them on future reboots.

```console
# nmcli device set enp1s0f1np1 managed no
# nmcli device set enP2p1s0f1np1 managed no
```

The second MAC on the active QSFP port (`enP2p1s0f0np0`) will show as `disconnected` after each reboot since it shares a physical port with a live cable. This is harmless and can be left as-is.

### Rename the wired connection for the 10 Gb/s RJ45 port

As we identified before, *Wired connection 3*, which is connected via the device `enP7s7`, corresponds to the 10 Gb/s RJ45 port on the Spark.

You might want to rename this connection for clarity, to something like `lan-rj45`.

```console
# nmcli connection modify "Wired connection 3" connection.id "lan-rj45"
```

### Turn off WiFi

After this thorough rationalization of network connections on the Spark, you should be able to rely on the wired connection for the 10 Gb/s RJ45 port for general network access.

So you might as well turn off WiFi to save a bit of power, and ensure all general network access takes place via the faster wired connection.

```console
# nmcli radio wifi off
```

This change persists across reboots of the Spark.

### Confirm the updated network configuration persists across reboots

Reboot the Spark.

Once the Spark is back up and running, check the network devices again.

```console
# nmcli device status
```

You should see output similar to this.

```
DEVICE         TYPE      STATE                   CONNECTION
enP7s7         ethernet  connected               lan-rj45
enp1s0f0np0    ethernet  connected               compute-fabric
lo             loopback  connected (externally)  lo
docker0        bridge    connected (externally)  docker0
enP2p1s0f0np0  ethernet  disconnected            --
enP2p1s0f1np1  ethernet  unavailable             --
enp1s0f1np1    ethernet  unavailable             --
wlP9s9         wifi      unavailable             --
```

Then check the network connections again.

```console
# nmcli -f NAME,TYPE,DEVICE connection show
```

You should see output similar to this.

```
NAME               TYPE      DEVICE      
lan-rj45           ethernet  enP7s7      
compute-fabric     ethernet  enp1s0f0np0 
lo                 loopback  lo          
docker0            bridge    docker0     
YourWiFiNetwork    wifi      --
```


## Tidy up NetworkManager connections on the server

For symmetry, we should now go through a similar exercise on the virtualization/storage server.

### Inspect network devices and connections

You can get some initial insight into which network devices are connected and which connections they map to with the following command.

```console
# nmcli device status
```

You may see output similar to this.

```
DEVICE           TYPE      STATE                   CONNECTION
bridge0          bridge    connected               bridge0
enP2s1f0np0      ethernet  connected               compute-fabric
enP2p3s0         ethernet  connected               bridge0-member-enP2p3s0
lo               loopback  connected (externally)  lo
vnet0            tun       connected (externally)  vnet0
enP2p1s0f1np1    ethernet  unavailable             --
enx56425e08dc8c  ethernet  unmanaged               --
```

Next up, you can list all the connections with the following command.

```console
# nmcli -f NAME,TYPE,DEVICE connection show
```

You may see output similar to this.

```
NAME                     TYPE      DEVICE      
bridge0                  bridge    bridge0     
compute-fabric           ethernet  enP2s1f0np0 
bridge0-member-enP2p3s0  ethernet  enP2p3s0    
lo                       loopback  lo          
vnet0                    tun       vnet0       
Wired connection 1       ethernet  --          
Wired connection 2       ethernet  --
```

From this, we can derive that *Wired connection 1* and *Wired connection 2* likely correspond to auto-generated stale DHCP connections for the BCM57414 NIC.

To find even more solid evidence for this, inspect which interfaces the auto-generated connections are bound to.

```console
# nmcli connection show "Wired connection 1" | grep -E "connection\.interface-name|ipv4\.method"
# nmcli connection show "Wired connection 2" | grep -E "connection\.interface-name|ipv4\.method"
```

For each of these, you should see output similar to this.

```
connection.interface-name:              enP2p1s0f1np1
ipv4.method:                            auto
```

Confirm that all of these connections are set up with `ipv4.method: auto`, and correspond to BCM57414 interfaces.

### Delete auto-generated connections for the BCM57414 NIC

Once you’ve confirmed that these connections are indeed the auto-generated stale DHCP connections for the BCM57414 NIC, you can safely delete them.

```console
# nmcli connection delete "Wired connection 1"
# nmcli connection delete "Wired connection 2"
```

For each of these commands, you should see output similar to this.

```
Connection 'Wired connection 1' (405400b1-13cb-3b29-a68f-8051007c8ea0) successfully deleted.
```

Then mark the unused BCM57414 interface as unmanaged to prevent NetworkManager from auto-generating new connections for them on future reboots.

```console
# nmcli device set enP2p1s0f1np1 managed no
```

### Confirm the updated network configuration persists across reboots

Reboot the virtualization/storage server.

Once the server is back up and running, check the network devices again.

```console
# nmcli device status
```

You should see output similar to this.

```
DEVICE           TYPE      STATE                   CONNECTION
bridge0          bridge    connected               bridge0
enP2s1f0np0      ethernet  connected               compute-fabric
enP2p3s0         ethernet  connected               bridge0-member-enP2p3s0
lo               loopback  connected (externally)  lo
vnet0            tun       connected (externally)  vnet0
enP2p1s0f1np1    ethernet  unavailable             --
enx56425e08dc8c  ethernet  unmanaged               --
```

Then check the network connections again.

```console
# nmcli -f NAME,TYPE,DEVICE connection show
```

You should see output similar to this.

```
NAME                     TYPE      DEVICE
bridge0                  bridge    bridge0
compute-fabric           ethernet  enP2s1f0np0
bridge0-member-enP2p3s0  ethernet  enP2p3s0
lo                       loopback  lo
vnet0                    tun       vnet0
```


## Test the connection once again

After all this rationalization of NetworkManager connections overall, on both nodes, you should go through once again [all the steps to test the connection](#test-the-connection) for our new compute fabric.


## Future enhancements

### Improve link reliability with Forward Error Correction

Forward Error Correction (FEC) improves link reliability by adding redundant data that allows the receiver to correct bit errors without requiring TCP retransmissions. At 25 Gb/s on a passive DAC cable, RS-FEC (Reed-Solomon) is the recommended mode per IEEE 802.3by and is required for a lossless fabric suitable for RoCEv2/RDMA.

Without FEC, the link functions correctly for bulk TCP transfers but produces a significant number of TCP retransmits under load. With RS-FEC active on both sides, retransmits drop substantially.

Adding support for FEC is substantially easier with a version 1.52 of NetworkManager, which introduces native support for the `ethtool.fec` property for network connections.

However, as of June 2026, the Spark’s DGX OS is still based on Ubuntu 24.04, which still uses version 1.46 of NetworkManager.

### Improve performance with RoCEv2 / RDMA

Configuring RDMA over Converged Ethernet version 2 (RoCEv2) on this dedicated compute fabric link allows the network adapters to transfer data directly between application memories without CPU involvement.

In so doing, we can eliminate TCP/IP overhead and reduce latency to microseconds, while freeing up CPU cycles for compute tasks instead of network processing.