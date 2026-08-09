# Modular periodic scripts configuration on FreeBSD

FreeBSD includes a simple yet powerful periodic system for running certain tasks on a regular schedule, such as system health checks, security audits, and cleanup jobs. [^1]

[^1]: To learn the basics of FreeBSD’s built-in periodic system, check out this [great introductory guide from the FreeBSD Foundation](https://freebsdfoundation.org/blog/an-introduction-to-freebsds-periodic-system/).

While this system is already modular in terms of how to add periodic scripts that can be triggered by it, it doesn’t have built-in support for modular periodic configuration files, similar to the approach shown in the [modular system configuration on FreeBSD](freebsd-modular-system-configuration.md) guide.

In this guide, we’ll set up our `/etc/periodic.conf` file in a custom way to enable this configuration to be modular.

## Scaffolding for modular periodic scripts configuration

Assuming you [fetched this homelab documentation](freebsd-command-line-tools.md#fetch-configuration-files) in `/homelab-documentation`, you just need to create a symbolic link to [the `periodic.conf` file provided in the repository](modular-periodic-scripts-configuration/etc/periodic.conf).

```console
# cd /etc
# ln -s ../homelab-documentation/freebsd-server/modular-periodic-scripts-configuration/etc/periodic.conf
```

This scaffolding ensures that when periodic scripts source `/etc/periodic.conf`, they also source all the files in `/etc/periodic.conf.d` and `/usr/local/etc/periodic.conf.d` with the `.conf` file extension.

Neither of those directories exists on a FreeBSD system out of the box, so let’s just create them both now.

```console
# mkdir -p /etc/periodic.conf.d
# mkdir -p /usr/local/etc/periodic.conf.d
```

It’s worth noting that, unlike FreeBSD’s built-in support for [modular system configuration](freebsd-modular-system-configuration.md), this scaffolding doesn’t support per-service or per-script targeting. This is largely harmless since unused variables are simply ignored by scripts that don’t check them.


## Examples of discrete periodic scripts configuration

For a freshly installed [FreeBSD server with ZFS on Root](freebsd-ampere-altra.md), there are a couple of simple things you should enable to ensure your ZFS pool remains healthy.

 - [`zfs-pool-scrub.conf`](modular-periodic-scripts-configuration/etc/periodic.conf.d/zfs-pool-scrub.conf)
	 - Weekly ZFS pool scrub.
 - [`zfs-health-monitoring.conf`](modular-periodic-scripts-configuration/etc/periodic.conf.d/zfs-health-monitoring.conf)
	 - Daily ZFS health monitoring.

```console
# cd /etc/periodic.conf.d
# ln -s ../../homelab-documentation/freebsd-server/modular-periodic-scripts-configuration/etc/periodic.conf.d/zfs-pool-scrub.conf
# ln -s ../../homelab-documentation/freebsd-server/modular-periodic-scripts-configuration/etc/periodic.conf.d/zfs-health-monitoring.conf
```


## Hourly periodic scripts

While FreeBSD has built-in support for daily, weekly and monthly periodic scripts, it’s lacking support for hourly periodic scripts, which can actually be quite handy in some cases.

As a quick bonus, let’s add that capability with some very simple `cron` setup and defaults configuration.

```console
# cd /etc/cron.d
# ln -s ../../homelab-documentation/freebsd-server/modular-periodic-scripts-configuration/etc/cron.d/periodic-hourly

# cd /etc/periodic.conf.d
# ln -s ../../homelab-documentation/freebsd-server/modular-periodic-scripts-configuration/etc/periodic.conf.d/hourly-periodic-jobs.conf

# mkdir -p /usr/local/etc/periodic/hourly
```

Let’s assume you have a custom script for checking the health of a database, which you would like to run hourly. Assuming the script has the appropriate shebang and the executable bit set in its permissions, you can simply drop that script in `/usr/local/etc/periodic/hourly` following the usual naming conventions for periodic scripts.

```console
# cd /usr/local/etc/periodic/hourly
# mv /path/to/database-health-check 500.database-health-check
```