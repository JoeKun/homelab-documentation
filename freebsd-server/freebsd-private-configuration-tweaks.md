# Private configuration tweaks on a dedicated branch

Most configuration files in the `homelab-documentation` repository are meant to be applied with a symbolic link, as described in [Useful command-line tools for FreeBSD](freebsd-command-line-tools.md#fetch-configuration-files), so that later improvements arrive with a simple `git pull`.

However, a few configuration files in the repository use placeholders wherever a value belongs to one particular machine: `my_server` for a host name, invented public IP addresses, `john@smith.com` for an email address, etc.

This guide shows how you can use a dedicated private branch of the `homelab-documentation` git repository to keep track of private edits for the real values you need on your own server.

## Create a machine-specific branch

In your clone of the `homelab-documentation` repository, create a new private branch named `my_server-only`, without tracking any remote branch.

```console
# cd /homelab-documentation
# git switch -c my_server-only
```

Then make one commit per file, with a subject that names the file and says what was substituted. Here are example commit messages.

 - `my_server only: /etc/fstab: use real serial numbers for storage drives.`
 - `my_server only: /etc/rc.conf.d/hostname: use real hostname.`
 - `my_server only: /etc/pf.conf: use real IP addresses for cloud servers.`
 - `my_server only: ~/.gitconfig: use real name and email address.`

Keeping them separate is what makes the branch durable. Each commit is replayed on its own, so a conflict in one file never blocks the others, and a tweak that stops being necessary can be dropped without disturbing the rest.


## Update the machine-specific branch

When improvements are made in the `main` branch of the `homelab-documentation` repository, fetch it and replay your commits on top of it. There’s no need to switch branches to do this.

```console
# git fetch origin main:main
# git rebase main
```

Every rebase gives your commits new hashes, and their content is specific to one machine, so this branch has no upstream: it lives only on the server it describes.


## Keep credentials and secrets separate

Credentials and other kinds of secrets (like API keys) are the exception.

A real host name or drive serial number is private, but exposing one is embarrassing rather than dangerous. Passwords and API keys are a different matter, and three properties of `git` make this branch a poor place to keep them.

 - `git` keeps every version of every file. Dropping the commit later leaves the secret in `.git` until it’s garbage collected, and `.git` is world-readable by default.
 - `git` records no ownership and no permission bits beyond the executable one. A file that has to be `-rw-r-----` is silently rewritten as `-rw-r--r--` by the next `checkout`, `rebase` or `merge`.
 - A branch is one `git push` away from wherever `origin` happens to point.

Instead, keep these kinds of secrets in discrete small files, outside of the repository.

The [`buddyns-sync-zone.conf`](dns/opt/local/etc/buddyns-sync-zone.conf) file described in [Faster DNS zone replication on FreeBSD with `nsnotifyd`](freebsd-faster-dns-replication-nsnotifyd.md#install-script-to-request-immediate-syncing-of-zone-by-buddyns) is a good example of that; it’s a small file that is meant to contain an API key, and, rather than laying down this file with a symbolic link like most other configuration files from the `homelab-documentation` repository, you should copy the file outside of your clone of the repository, and edit it there.