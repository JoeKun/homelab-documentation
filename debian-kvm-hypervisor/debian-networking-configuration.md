# Networking configuration for Debian KVM Hypervisor

With a minimal Debian 13 Trixie install like the one shown in [this earlier guide](debian-root-on-zfs-ampere-altra.md), your system uses a traditional networking configuration, based on `ifupdown` and its associated configuration files like `/etc/network/interfaces`.

While this configuration is perfectly fine, a number of other distributions, such as the ones in the Red Hat Enterprise Linux family, are embracing NetworkManager for both desktop and server systems alike.

Furthermore, for a [KVM Hypervisor](debian-kvm-libvirt-cockpit.md), some virtual machine management tasks can be easier to accomplish with the Cockpit web-based graphical user interface, and Cockpit appears to depend on and integrate well with NetworkManager.

So, in this guide, we’ll transition from the traditional networking configuration we previously set up as part of the installation process to using NetworkManager.

Since the following commands will disrupt network access, you should not run them remotely. Instead, you’ll need physical access to the server, to run the commands using the physical keyboard and monitor connected to the motherboard. Alternatively, you can use remote control access with your BMC’s KVM or serial console over LAN.

## Install NetworkManager

NetworkManager may not be installed yet, especially if you only installed the standard system utilities as part of the installation process.

```console
# apt install network-manager
```


## Disable traditional networking

Disable the network interface `enP2p3s0` with traditional networking configuration.

```console
# ifdown enP2p3s0
# rm -f /etc/network/interfaces.d/enP2p3s0
```

You may want to wait at least five seconds for good measure before moving on to the next step.


## Disable auto-connecting to USB ethernet device for motherboard’s BMC

With the ASRock Rack ALTRAD8UD2-1L2Q motherboard, the integrated Baseboard Management Controller (BMC) presents itself as a USB ethernet device. This usually leads to the `NetworkManager-wait-online` service failing to start, as it automatically tries and fails to establish a connection with this device.

You may see signs of this problem in the output of the following command.

```console
# systemctl status NetworkManager
```

Specifically, the following log line shown in the output of the previous command is a good indication that you’re faced with this specific problem.

```console
Jan 02 16:31:00 my_server.my_domain.tld NetworkManager[7850]: <warn>  [1767400260.5909] device (enxae1d1bd15110): Activation: failed for connection 'Wired connection 3'
```

If you want to confirm which NetworkManager connection is associated to this `enxae1d1bd15110` device, you can run the following command.

```console
# for connection in $(nmcli -g uuid connection show)
  do
      nmcli -f connection.id,connection.interface-name,connection.autoconnect connection show "${connection}"
  done | grep -B 1 -A 1 enxae1d1bd15110
```

Here’s the expected output at this point.

```console
connection.id:                          Wired connection 3
connection.interface-name:              enxae1d1bd15110
connection.autoconnect:                 yes
```

To fix this problem, simply delete this specific connection.

```console
# nmcli connection delete "Wired connection 3"
```

And to prevent it from happening again, instruct NetworkManager that any device whose name begins with `enxae` should not be managed.

```console
# cat << EOF > /root/99-unmanage-bmc.conf
[keyfile]
unmanaged-devices=interface-name:enxae*
EOF

# systemctl restart NetworkManager
```


## Add a network bridge for guest virtual machines

In order for virtual machines to be accessible in your network, you may want them to be on the same subnet as the host. This can be achieved with a network bridge.

First, you need to tell `NetworkManager` that it may manage the network interface device that was previously configured with traditional networking, i.e. `enP2p3s0`.

```console
# nmcli device set enP2p3s0 managed yes
# systemctl restart NetworkManager
```

Then, create a new network bridge named `bridge0`.

```console
# nmcli connection add type bridge \
      con-name bridge0 \
      ifname bridge0 \
      ipv4.method auto
```

Attach your network interface device `enP2p3s0` to this bridge as a member.

```console
# nmcli connection add type ethernet \
      con-name bridge0-member-enP2p3s0 \
      ifname enP2p3s0 \
      master bridge0
```

Bring up both of these connections.

```console
# nmcli connection up bridge0
# nmcli connection up bridge0-member-enP2p3s0
```

Make sure to wait about 5 seconds to allow these connections to be established.

Check for network connectivity with the following commands.

```console
# ip addr show bridge0
# ping -c 3 1.1.1.1
# ping -c 3 google.com
```

Confirm that your NetworkManager device status looks reasonable.

```console
# nmcli device status
```

The output should look similar to this.

```console
DEVICE           TYPE      STATE                   CONNECTION              
bridge0          bridge    connected               bridge0
enP2p3s0         ethernet  connected               bridge0-member-enP2p3s0
lo               loopback  connected (externally)  lo
enxae1d1bd15110  ethernet  disconnected            --
enP2p1s0f1np1    ethernet  unavailable             --
enP2s1f0np0      ethernet  unavailable             --
```

And confirm that your NetworkManager connections also look reasonable.

```console
# nmcli -f NAME,TYPE,DEVICE connection show
```

The output should look as follows.

```console
NAME                     TYPE      DEVICE
bridge0                  bridge    bridge0
bridge0-member-enP2p3s0  ethernet  enP2p3s0
lo                       loopback  lo
Wired connection 1       ethernet  --
Wired connection 2       ethernet  --
```

If you experienced the problem above with the `NetworkManager-wait-online` service failing to start, restart it now and check its status.

```console
# systemctl restart NetworkManager-wait-online.service
# sleep 5
# systemctl status NetworkManager-wait-online.service
```

Assuming this looks good, you should make sure this configuration works well upon the server rebooting.

```console
# reboot
```

After reboot, run the handful of commands listed above again to check for network connectivity.