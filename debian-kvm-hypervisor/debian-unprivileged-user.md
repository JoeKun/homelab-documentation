# Create an unprivileged user account on Debian

After successfully setting up a minimal Debian 13 Trixie install with root on ZFS, as shown in [Debian with Root on ZFS on Ampere Altra Server](debian-root-on-zfs-ampere-altra.md), your next step should be to create an unprivileged user account for any task you need to perform that doesn’t require `root`’s administrator privileges.

First create a dedicated ZFS dataset nested within `hypervisor/home`.

```console
# zfs create hypervisor/home/john
```

Then create the unprivileged user account.

```console
# adduser --ingroup users --no-create-home john
```

Copy the skeleton of a home directory for this new user, and fix its permissions.

```console
# cp -av /etc/skel/. /home/john
# chown -R john:users /home/john
```

Add the new unprivileged user account to the `sudo` group if you want the ability to use `sudo` with this new user.

```console
# usermod -a -G sudo john
```

That’s all there is to it!