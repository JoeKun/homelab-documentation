# Storage health monitoring with `smartd` on FreeBSD

Most drives can warn you that they’re degrading well before they fail, through [SMART](https://en.wikipedia.org/wiki/Self-Monitoring,_Analysis_and_Reporting_Technology). The `smartmontools` package provides `smartctl` to query that information on demand, and `smartd` to watch it continuously and alert you when something changes.

Writing the configuration file is the easy part. The real work is determining which device nodes to monitor and what each drive actually supports, since both vary considerably on a machine with mixed storage.

## Hardware configuration

 - **Add-in card:** Icy Dock ExpressSlot Slide 4 Bay M.2 NVMe SSD Adapter Card
 - **System storage:** Three Samsung 990 PRO 2 TB - NVMe PCIe 4.0 M.2 2280 SSD
 - **Mass tiered storage**
	 - **Host bus adapter**: Broadcom 9500-16i Tri-Mode Storage Adapter
	 - **Storage backplane**: Single SAS-3 expander with 8 NVMe (Supermicro BPN-SAS3-846EL1-N8)
	 - **Hard drives**: 6 × WD Red Plus 14 TB NAS Internal Hard Drive
	 - **Fast NVMe SSDs**
		 - 4 × Samsung PM9A3 1.92 TB NVMe Enterprise SSD
		 - 2 × Intel Optane 905P Series 960 GB


## Install `smartmontools`

If you’re using `poudriere` following [this guide](freebsd-poudriere.md), then add an entry to the list of packages built by `poudriere`.

```console
# cat << EOF >> /usr/local/etc/poudriere.d/pkglist

# System administration utilities
sysutils/smartmontools
EOF
```

And build your packages again.

```console
# poudriere bulk \
    -j my_poudriere-arm64-15-1 \
    -p 2026Q3 \
    -f /usr/local/etc/poudriere.d/pkglist
```

Finally, on the target server machine, install `smartmontools`.

```console
# pkg install smartmontools
```


## Choose which device nodes to monitor

`smartctl --scan` is the obvious starting point, but treat its output as a first draft rather than something to paste into a configuration file.

```console
# smartctl --scan
/dev/da0 -d scsi # /dev/da0, SCSI device
[…]
/dev/nda0 -d scsi # /dev/nda0, SCSI device
[…]
/dev/nvme0 -d nvme # /dev/nvme0, NVMe device
[…]
```

Two things in there are misleading.

**Each NVMe drive appears twice.** `/dev/nvmeN` is the controller device node created by `nvme(4)`, while `/dev/ndaN` is the disk peripheral created by `nda(4)`, the CAM-based NVMe driver. They are the same physical drive reached through two different subsystems, so monitoring both means polling every drive twice and receiving every alert twice.

Prefer the `/dev/nvmeN` nodes with `-d nvme`. That path reads the NVMe SMART/Health Information log natively, whereas reaching the drive through CAM only gets you a lossy SCSI translation of it.

The numbering usually corresponds, but `camcontrol devlist -v` lets you confirm it rather than assume it, since it prints the controller each CAM peripheral belongs to.

```console
# camcontrol devlist -v
[…]
scbus2 on nvme0 bus 0:
<Samsung SSD 990 PRO 2TB 8B2QJXD7>  at scbus2 target 0 lun 1 (pass7,nda0)
[…]
```

**SATA drives behind a SAS host bus adapter are labelled `-d scsi`.** The scan walks the CAM device list and labels everything it finds there as SCSI, without inspecting what is really behind the peripheral. Those drives are reached through the adapter’s SCSI-ATA translation layer, and `-d scsi` would give you a translated view with no ATA attribute table, no error log and no self-test log.

Leaving the device type out entirely is better, since both `smartctl` and `smartd` probe for the translation layer and select `sat` on their own.


## Check what each drive supports

Three properties vary from drive to drive, and each one changes what you write in the configuration file.

### Temperature thresholds

NVMe drives report the temperatures at which they consider themselves to be in trouble.

```console
# smartctl -a /dev/nvme0 | grep -i 'Comp. Temp. Threshold'
Warning  Comp. Temp. Threshold:     82 Celsius
Critical Comp. Temp. Threshold:     85 Celsius
```

These sit far above anything reasonable for a spinning disk, which is the main reason one set of thresholds cannot cover both kinds of drive. Choose a warning level comfortably below the lowest value any drive in the machine reports, so that you hear about a cooling problem before the hardware starts throttling.

Some drives report nothing here at all. On those, the drive’s own critical warning flag will never fire for temperature, and the threshold you configure is their only coverage. They still report a current temperature, which is what actually matters.

```console
# smartctl -A /dev/nvme0 | grep -i '^Temperature:'
Temperature:                        46 Celsius
```

### Self-test support

Not every NVMe drive implements the device self-test command.

```console
# smartctl -c /dev/nvme0 | grep -i 'Optional Admin'
Optional Admin Commands (0x0017):   Security Format Frmw_DL Self_Test
```

`Self_Test` in that list means the drive can be given a self-test schedule. A drive without it should simply be monitored without one.

### Extended self-test duration

The duration determines how far apart to space the schedule, and it differs by orders of magnitude between device types.

```console
# smartctl -c /dev/da0 | grep -A 1 'Extended self-test'
Extended self-test routine
recommended polling time: 	 (1562) minutes.
```

Twenty-six hours per drive, which is why the hard drives below are staggered across separate days of the month.

NVMe capabilities don’t include an equivalent figure, so the practical approach is to run one test on an idle drive and watch its progress.

```console
# smartctl -t long /dev/nvme4
# smartctl -l selftest /dev/nvme4
Self-test status: Extended self-test in progress (14% completed)
```

Don’t try to extrapolate from that percentage, which advances very unevenly; just check back until the log reports a completed test. These drives take well under an hour, so their tests need far less spacing than the hard drives.


## Configure `smartd`

Assuming you [fetched this homelab documentation](freebsd-command-line-tools.md#fetch-configuration-files) in `/homelab-documentation`, you can create a symbolic link to [the `smartd.conf` file provided in the repository](storage-health-monitoring-smart/usr/local/etc/smartd.conf).

```console
# cd /usr/local/etc
# ln -s ../../../homelab-documentation/freebsd-server/storage-health-monitoring-smart/usr/local/etc/smartd.conf
```

That file is specific to the hardware described above, so adapt the device list to your own machine. It’s organized into two blocks, because directives do not carry across device types: a later `DEFAULT` line replaces the earlier one for every device below it.

The first block covers the hard drives, with the following `DEFAULT` line.

```
DEFAULT -a -I 194 -W 4,40,45 -R 5 -m root
```

 - `-a` enables the standard set of checks;
 - `-I 194` suppresses the normalized temperature attribute since it changes constantly;
 - `-W 4,40,45` monitors temperature properly instead;
 - `-R 5` reports changes in the raw reallocated sector count, which moves long before the normalized value does.

The second block replaces those defaults for the NVMe drives.

```
DEFAULT -H -l error -l selftest -W 0,70,78 -m root
```

ATA attribute identifiers like 194 and 5 mean nothing to an NVMe controller, so they are omitted; it keeps `-H` for the drive’s own critical warning flag, `-l error` for the error log, and much higher temperature thresholds.

It also names `-l selftest` explicitly, which `-a` had already covered for the hard drives. This is easy to overlook, and overlooking it means scheduling self-tests whose results nobody ever reads.

Self-tests themselves are scheduled per device with an `-s` expression, whose leading letter is the type of test to run.

```
/dev/da0 -s L/../01/./03
```

`L` is the long test, the same one `smartctl -t long` runs above, while `S` would be the short one. The remaining fields are month, day of month, day of week and hour, matched as patterns in which a dot stands for any digit. This one therefore runs a long test on the first day of every month, at 03:00. Devices are spread out so that only one drive is ever testing at a time.

Avoid just relying on `DEVICESCAN` in your `smartd.conf`, as it applies the same flawed scan logic described above.


## Verify the configuration before enabling it

`smartd` can parse its configuration, register every device and exit, without running as a service.

```console
# smartd -q onecheck
```

The summary line near the end should match what you configured.

```
Monitoring 6 ATA/SATA, 0 SCSI/SAS and 9 NVMe devices
```

Here `0 SCSI/SAS` confirms that nothing fell through to the translated path. This run also names any directive it cannot honor, rather than failing silently.

```
Device: /dev/nvme3, does not support NVMe Self-tests, ignoring -l selftest
```

A second mode prints the self-test schedule it derived, which is the only way to confirm that your `-s` expressions mean what you intended.

```console
# smartd -q showtests
[…]
Device: /dev/da4 [SAT], will do test 1 of type L at Sun Aug  9 03:04:18 2026 PDT
[…]
```

Tests fire at the first check following the scheduled hour rather than exactly on it, so the minutes will look arbitrary.


## Enable `smartd`

Enable the `smartd` service. [^1]

[^1]: As shown in [Modular system configuration on FreeBSD](freebsd-modular-system-configuration.md).

```console
# cat << EOF > /usr/local/etc/rc.conf.d/smartd
# /usr/local/etc/rc.conf.d/smartd: system configuration for smartd

smartd_enable="YES"
EOF
```

Then start the `smartd` service.

```console
# service smartd start
```


## Confirm that alerts reach you

`smartd` writes to `syslog` and, thanks to the `-m` directive, sends email. An alerting path that has never been exercised is a poor thing to depend on: `smartd` can run correctly and silently for years before anyone discovers that the mail never arrived.

Add `-M test` to a single device line, restart the service, and confirm that the message arrives.

```console
# service smartd restart
```

Then remove the directive, otherwise every subsequent restart will mail you.


## Include drive health in daily status reports

In addition to `smartd` alerting us when something is wrong, FreeBSD’s periodic system can include SMART health for a list of devices in its daily run.

Assuming you [configured your `/etc/periodic.conf` to enable a modular periodic scripts configuration](freebsd-modular-periodic-scripts-configuration.md#scaffolding-for-modular-periodic-scripts-configuration), you can set this up with a new [`smart-status.conf` file](storage-health-monitoring-smart/usr/local/etc/periodic.conf.d/smart-status.conf) in `/usr/local/etc/periodic.conf.d`.

```console
# cd /usr/local/etc/periodic.conf.d
# ln -s ../../../../homelab-documentation/freebsd-server/storage-health-monitoring-smart/usr/local/etc/periodic.conf.d/smart-status.conf
```

This configuration file automatically derives the list of devices to report status about from the list of devices already included in `/usr/local/etc/smartd.conf`.


## Additional resources

Interpreting what `smartd` eventually reports is a large subject in its own right, and the meaning of a given attribute often depends on the drive vendor.

Klara Systems has a broader article on [FreeBSD NAS maintenance best practices](https://klarasystems.com/articles/open-source-freebsd-nas-maintenance-best-practices/) which goes further in that direction, covering what the common SMART attributes mean and what healthy values look like.