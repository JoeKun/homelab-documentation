# Fix environment variables for administrator account on Debian

When you use `su` from your [new unprivileged user account](debian-unprivileged-user.md), you may notice that important command-line tools like `nvme` or `update-initramfs` can’t be found in your new shell as `root`.

This happens because when you use `su`, `bash` starts an interactive, non-login shell, and as a result, important directories  like `/usr/sbin` are missing from the inherited value of the `PATH` environment variable from your unprivileged user.

By default on a Debian system, the `PATH` environment variable for `bash` is defined to a sane value in `/etc/profile`, but that file is not re-evaluated for an interactive, non-login shell such as the one started by `su`.

One possible solution to this problem is to override the `PATH` in the `/root/.bashrc` file as follows.

```console
# cat << EOF >> /root/.bashrc

# Ensure the PATH environment variable is set to a reasonable value
# for root.
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH
EOF
```

You should now have easy access to all common administrative tools you may need from your `root` account, no matter how you start a shell!