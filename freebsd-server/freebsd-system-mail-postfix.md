# System mail with Postfix on FreeBSD

A FreeBSD server sends mail regularly to its `root` administrator account: the daily, weekly and monthly reports from the periodic system, the output of `cron` jobs, and alerts from services like `smartd`.

This guide replaces the default mail handler on FreeBSD with [Postfix](https://www.postfix.org), configured as narrowly as possible: it accepts mail from the machine itself only, delivers locally for the machine’s own names, and forwards mail for `root` to an external address.

This is the first step of a multi-part mail server setup series: later guides build on this same installation of Postfix.

## General approach for system mail

**Nothing listens on the network.** Postfix only accepts mail from processes running on the machine, so there is no port to open in the firewall, and nothing for anyone else to connect to.

**Local aliases.** FreeBSD already maps most system accounts to `root`. We just need to add a few local aliases, including the one that specifies where mail for `root` goes.

**Staged configuration files.** Postfix’s main configuration file has no mechanism to include other files, so each stage of the mail server setup ships its own complete copy of it. This guide uses the copy in [`freebsd-server/postfix/system-mail`](postfix/system-mail/usr/local/etc/postfix/main.cf); later guides move the symbolic link to the copy for their own stage.

**Outbound port 25 must be open for mail to leave.** This configuration delivers mail directly to each recipient’s mail server, on port 25. Many residential internet service providers block outbound connections to that port. If yours does, you can still follow this guide entirely, and confirm that everything works up to the point where mail leaves the machine; the next guide then sends that mail through a relay instead.


## Install Postfix

If you’re using `poudriere` following [this guide](freebsd-poudriere.md), then add Postfix to the list of packages built by `poudriere`.

```console
# cat << EOF >> /usr/local/etc/poudriere.d/pkglist

# Mail server
mail/postfix
EOF
```

And build your packages again.

```console
# poudriere bulk \
    -j my_poudriere-arm64-15-1 \
    -p 2026Q3 \
    -f /usr/local/etc/poudriere.d/pkglist
```

Postfix’s default options are all this guide needs. For a machine that doesn’t use your own `poudriere` repository, such as a VPS in the public cloud, FreeBSD’s official package works just as well.

Finally, on the target server machine, install the package.

```console
# pkg install postfix
```

The package creates the `postfix` user and group, as well as the `maildrop` group, and installs sample configuration files in `/usr/local/etc/postfix`.


## Make Postfix the system’s mail transport agent

Sendmail used to be the default mail transport agent on FreeBSD for decades, until it was replaced by the DragonFly Mail Agent (also known as `dma`) in FreeBSD 14.0. As a result, many programs rely on its `sendmail` command to send mail, which led other mail transport agents, such as `dma` and Postfix, to provide a compatible command of their own.

### Point `mailwrapper` at Postfix

On FreeBSD, the `sendmail`, `mailq` and `newaliases` commands are all handled by [`mailwrapper(8)`](https://man.freebsd.org/cgi/man.cgi?query=mailwrapper&sektion=8&manpath=freebsd-release-ports), which runs the mail transport agent named in `/usr/local/etc/mail/mailer.conf`. In the absence of a custom `mailer.conf` in that location, `mailwrapper` checks the corresponding configuration in the base system in `/etc/mail/mailer.conf`, which points to `dma`.

Hence, to replace `dma` with Postfix, you just need to install the version of `mailer.conf` provided by the Postfix package.

```console
# mkdir -p /usr/local/etc/mail
# install -m 0644 /usr/local/share/postfix/mailer.conf.postfix /usr/local/etc/mail/mailer.conf
```

### Disable Sendmail’s periodic routines

Sendmail is still part of the base system. Its daemons don’t start by default, but a few daily maintenance routines of the periodic system that are specific to it are still enabled. Assuming you [configured your `/etc/periodic.conf` to enable a modular periodic scripts configuration](freebsd-modular-periodic-scripts-configuration.md#scaffolding-for-modular-periodic-scripts-configuration), you can disable them with a new [`postfix.conf` file](postfix/usr/local/etc/periodic.conf.d/postfix.conf) in `/usr/local/etc/periodic.conf.d`.

```console
# cd /usr/local/etc/periodic.conf.d
# ln -s ../../../../homelab-documentation/freebsd-server/postfix/usr/local/etc/periodic.conf.d/postfix.conf
```

These are the same four settings recommended by the package’s installation message.


## Configure Postfix

### Main configuration file

Replace the sample main configuration file with a symbolic link to the one for this stage, [provided in the repository](postfix/system-mail/usr/local/etc/postfix/main.cf).

```console
# cd /usr/local/etc/postfix
# rm -f main.cf
# ln -s ../../../../homelab-documentation/freebsd-server/postfix/system-mail/usr/local/etc/postfix/main.cf
```

Here are some of the important parts of this `main.cf` file.

Postfix only listens on the loopback interface, and only trusts the machine itself to send mail.

```
inet_interfaces = loopback-only
mynetworks_style = host
```

FreeBSD’s own aliases come first, followed by a local aliases file, described [below](#where-mail-for-root-goes).

```
alias_maps = $default_database_type:/etc/mail/aliases
             $default_database_type:/usr/local/etc/mail/aliases
```

Outbound mail is encrypted whenever the recipient’s mail server supports it.

```
smtp_tls_security_level = may
```

Just as important is what the file leaves out. `myhostname`, `myorigin` and `mydestination` keep their default values, derived from the machine’s fully qualified host name. You can check what Postfix makes of them.

```console
# postconf myhostname myorigin mydestination
myhostname = my_server.my_domain.tld
myorigin = $myhostname
mydestination = $myhostname, localhost.$mydomain, localhost
```

System mail therefore leaves as `root@my_server.my_domain.tld`, and only mail for the machine’s own name or for `localhost` is delivered locally. Mail for any other address, including addresses in `my_domain.tld` itself, leaves the machine.

### Where mail for root goes

FreeBSD’s `/etc/mail/aliases` already maps most system accounts, such as `postmaster`, `daemon` or `operator`, to `root`. Leave it untouched, so that system upgrades can keep merging it cleanly, and complete it with a symbolic link to [our own `aliases` file](postfix/usr/local/etc/mail/aliases).

```console
# cd /usr/local/etc/mail
# ln -s ../../../../homelab-documentation/freebsd-server/postfix/usr/local/etc/mail/aliases
```

Make sure to customize the first alias for `root`.

```
root:                   john@external-domain.tld
```

Replace this address with your own; if you would like to keep track of this kind of private edit to configuration files, you may want to consider [creating a dedicated branch containing your private tweaks](freebsd-private-configuration-tweaks.md).

Then build the aliases databases.

```console
# newaliases
```


## Enable and start Postfix

Check the configuration first; `postfix check` prints nothing when all is well.

```console
# postfix check
```

Enable the `postfix` service. [^1]

[^1]: As shown in [Modular system configuration on FreeBSD](freebsd-modular-system-configuration.md).

```console
# cat << EOF > /usr/local/etc/rc.conf.d/postfix
# /usr/local/etc/rc.conf.d/postfix: system configuration for postfix

postfix_enable="YES"
EOF
```

Then start the `postfix` service.

```console
# service postfix start
```


## Essential DNS records

Mail delivery is a complex and multi-layered problem. Over the years, mail providers have employed various methods for reducing spam. This problem domain is large enough that we need to cover it in greater depth in a future guide.

Nevertheless, there are some essential DNS records that need to be created for your server’s system mail to have a reasonable chance of not being flagged as spam by external mail servers.

**Address records.** Your server’s fully qualified host name, such as `my_server.my_domain.tld`, must resolve to the host’s public addresses, in the zone file for `my_domain.tld`, as shown in [Authoritative DNS server with BIND on FreeBSD](freebsd-dns-bind.md#address-and-canonical-name-records).

**Reverse DNS records.** Each of those addresses resolves back to a host name that itself resolves to the same address. Ideally, that’s the server’s fully qualified host name, `my_server.my_domain.tld`, which is also the name Postfix introduces itself with when connecting to other mail servers. These live in the provider’s reverse zone; you will have to contact your internet service provider or cloud provider as appropriate to have them update the reverse DNS `PTR` record as needed.

**An SPF record for the host name.** System mail leaves as `root@my_server.my_domain.tld`, so receiving servers look for an SPF policy at `my_server.my_domain.tld` itself, not at `my_domain.tld`.

```
my_server               IN      A       89.67.45.123
my_server               IN      AAAA    1234:5678:9abc:edcb::a
my_server               IN      TXT     "v=spf1 a -all"
```

For context, SPF stands for Sender Policy Framework, and it offers a standard method for administrators to list the addresses allowed to send mail for a domain name. The `a` mechanism authorizes exactly the addresses of the host’s own `A` and `AAAA` records.

Postfix may connect over IPv6 whenever the recipient’s mail server has an IPv6 address. If the host has an IPv6 address without a reverse DNS record, either ask the provider for one, or restrict Postfix on that host to IPv4 with `inet_protocols = ipv4`, as a private tweak.


## Confirm correct behavior

All but the last of these checks work whether or not outbound port 25 is open.

### Local delivery

Send a message to an account that isn’t aliased to anything, such as your [unprivileged user](freebsd-unprivileged-user.md).

```console
# echo "Local delivery test" | mail -s "Local delivery test" my_username
```

The message should be delivered right away. You should see logs like this in `/var/log/maillog` (date and time omitted).

```
postfix/pickup[39425]: 17407D25: uid=0 from=<root>
postfix/cleanup[57878]: 17407D25: message-id=<[date_time].17407D25@my_server.my_domain.tld>
postfix/qmgr[39815]: 17407D25: from=<root@my_server.my_domain.tld>, size=338, nrcpt=1 (queue active)
postfix/local[58858]: 17407D25: to=<my_username@my_server.my_domain.tld>, orig_to=<my_username>, relay=local, delay=0.05, delays=0.03/0.01/0/0, dsn=2.0.0, status=sent (delivered to mailbox)
postfix/qmgr[39815]: 17407D25: removed
```

This alone proves that `mailwrapper` now hands mail to Postfix, and that Postfix queues and delivers it. `my_username` can read the message with `mail`.

### Alias resolution

Ask Postfix where mail for `root` goes, without sending anything.

```console
# postalias -q root /usr/local/etc/mail/aliases
john@external-domain.tld
```

`sendmail -bv` goes further, and reports how Postfix would deliver mail for `root`, through every alias and down to the transport it would use. The report is itself a message, sent to the account given with `-f`; use `my_username`, whose mail stays on the machine.

```console
# sendmail -f my_username -bv root
Mail Delivery Status Report will be mailed to <my_username>.
```

### Outbound mail

Finally, send a message to `root`.

```console
# echo "Outbound delivery test" | mail -s "Outbound delivery test" root
```

If your server’s outbound port 25 is open, the message should reach the address from the `aliases` file within moments, and the log file `/var/log/maillog` should show a line with `status=sent`, preceded by one describing the TLS connection.

```
postfix/pickup[843]: EB36C339: uid=0 from=<root>
postfix/cleanup[23733]: EB36C339: message-id=<[date_time].EB36C339@my_server.my_domain.tld>
postfix/qmgr[1669]: EB36C339: from=<root@my_server.my_domain.tld>, size=344, nrcpt=1 (queue active)
postfix/cleanup[23733]: EBADA274: message-id=<[date_time].EB36C339@my_server.my_domain.tld>
postfix/local[25155]: EB36C339: to=<root@my_server.my_domain.tld>, orig_to=<root>, relay=local, delay=0.01, delays=0/0/0/0, dsn=2.0.0, status=sent (forwarded as EBADA274)
postfix/qmgr[1669]: EBADA274: from=<root@my_server.my_domain.tld>, size=477, nrcpt=1 (queue active)
postfix/qmgr[1669]: EB36C339: removed
postfix/smtp[39096]: Trusted TLS connection established to mx1.external-domain.tld[203.0.113.25]:25: TLSv1.3 with cipher TLS_AES_256_GCM_SHA384 (256/256 bits) key-exchange X25519MLKEM768 server-signature ECDSA (prime256v1) server-digest SHA256
postfix/smtp[39096]: EBADA274: to=<john@external-domain.tld>, orig_to=<root>, relay=mx1.external-domain.tld[203.0.113.25]:25, delay=1.3, delays=0/0.02/0.58/0.65, tls=may, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued as 4dK7xQ2mHvz3Rn)
postfix/qmgr[1669]: EBADA274: removed
```

You can also find more information in the message’s headers, such as whether it passed SPF checks.

```
Received-SPF: pass (external-domain.tld: domain of root@my_server.my_domain.tld designates 89.67.45.123 as permitted sender) client-ip=89.67.45.123;
Authentication-Results: mx1.external-domain.tld;
       spf=pass (external-domain.tld: domain of root@my_server.my_domain.tld designates 89.67.45.123 as permitted sender) smtp.mailfrom=root@my_server.my_domain.tld
```

Conversely, if your server’s outbound port 25 is blocked, the message stays in the mail queue, and after a minute or so, you may see output like this.

```console
# mailq
-Queue ID-  --Size-- ----Arrival Time---- -Sender/Recipient-------
873D9C90        477 [Date / Time]        root@my_server.my_domain.tld
     (connect to mx2.external-domain.tld[203.0.113.26]:25: Operation timed out)
                                         john@external-domain.tld

-- 0 Kbytes in 1 Request.
```

And you should see logs like this in `/var/log/maillog` (date and time omitted).

```
postfix/pickup[3142]: 800623BC: uid=0 from=<root>
postfix/cleanup[5374]: 800623BC: message-id=<[date_time].800623BC@my_server.my_domain.tld>
postfix/qmgr[3452]: 800623BC: from=<root@my_server.my_domain.tld>, size=344, nrcpt=1 (queue active)
postfix/cleanup[5374]: 873D9C90: message-id=<[date_time].800623BC@my_server.my_domain.tld>
postfix/local[6170]: 800623BC: to=<root@my_server.my_domain.tld>, orig_to=<root>, relay=local, delay=0.05, delays=0.03/0.01/0/0, dsn=2.0.0, status=sent (forwarded as 873D9C90)
postfix/qmgr[3452]: 873D9C90: from=<root@my_server.my_domain.tld>, size=477, nrcpt=1 (queue active)
postfix/qmgr[3452]: 800623BC: removed

[30 seconds later]
postfix/smtp[6909]: connect to mx1.external-domain.tld[203.0.113.25]:25: Operation timed out

[30 seconds later]
postfix/smtp[6909]: connect to mx2.external-domain.tld[203.0.113.26]:25: Operation timed out
postfix/smtp[6909]: 873D9C90: to=<john@external-domain.tld>, orig_to=<root>, relay=none, delay=61, delays=0/0.04/61/0, tls=may?, dsn=4.4.1, status=deferred (connect to mx2.external-domain.tld[203.0.113.26]:25: Operation timed out)
```

The only reason given should be a connection to the recipient’s mail server on port 25 timing out. To be sure that the port is blocked rather than misconfigured, check a connection on port 25, which will most likely time out after five seconds.

```console
# nc -z -v -w 5 smtp.gmail.com 25
nc: connect to smtp.gmail.com port 25 (tcp) failed: Operation timed out
```

And contrast that with a connection on port 587, which internet service providers usually leave open.

```console
# nc -z -v -w 5 smtp.gmail.com 587
Connection to smtp.gmail.com 587 port [tcp/submission] succeeded!
```

Even if you find yourself in this annoying situation with your provider blocking your outbound port 25, you can easily work around this limitation by relaying your mail through another server, which we’ll cover in the next guide.
