# Useful command-line tools for Debian

After successfully setting up a minimal Debian 13 Trixie system, you may want to install a few useful command-line tools.

Here are just a few noteworthy command-line tools worth considering.

## Hardware inspection

To inspect the hardware you have connected to your Debian system, you should consider installing `nvme-cli` and `usbutils`.

```console
# apt install nvme-cli usbutils
```


## Network configuration

For network configuration checking and testing, you may want to consider a few more tools.

```console
# apt install ethtool iperf3
```


## Disk partitioning

```console
# apt install gdisk
```


## File system utilities

For syncing directories between two locations on the same system or between two systems across the network, `rsync` can be very handy.

```console
# apt install rsync
```

Also, if you want to be able to use the convenient `locate` command-line tool to quickly find files by name, please run the following commands.

```console
# apt install locate
# updatedb
```


## System monitoring

You should probably install `htop`, which is a much nicer and powerful variant of `top`.

```console
# apt install htop
```

And as a nice-to-have fun bonus, you can install `fastfetch`, which can fetch system information and display it in a pretty way.

```console
# apt install fastfetch
```

While this list is still pretty minimal, it may be just enough for a machine dedicated to being a Debian KVM Hypervisor.