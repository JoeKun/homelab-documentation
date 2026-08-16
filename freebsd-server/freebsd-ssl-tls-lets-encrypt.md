# SSL/TLS certificates with Let’s Encrypt on FreeBSD

Having a valid and trusted SSL/TLS certificate is a must for external facing services in a homelab. Nowadays, setting up a great SSL/TLS certificate is a no-brainer, especially with the advent of [Let’s Encrypt](https://letsencrypt.org), which is a free and automated certificate authority, capable of signing certificates trusted by all major web browsers.

In this guide, we’ll cover how to get started with SSL/TLS certificates on FreeBSD, using a generally applicable approach to obtaining SSL/TLS certificates with Let’s Encrypt, which isn’t tied to one specific service that needs to use the certificate. This way, you’ll be able to use your new SSL/TLS certificate not only for your web server of choice, such as `nginx`, but also down the road for other services you might be interested in hosting, such as a mail server, or a GitLab container registry.

To be more specific, we’ll focus on an approach that leverages the DNS challenge method, building upon an existing [authoritative DNS server with BIND](freebsd-dns-bind.md), which has two great advantages:
 - it allows for zero downtime SSL/TLS certificate renewals;
 - it is suitable for obtaining wildcard SSL/TLS certificates for multiple domains with all of their subdomains. [^1]

[^1]: A wildcard SSL/TLS certificate can be used to secure not only a core domain such as `my_domain.tld`, but also all of its subdomains, which is achieved by adding `*.my_domain.tld` to the certificate signing request.

## Create SSL user and group

It’s important to keep the private key for your SSL certificate secure, which implies making sure it’s not readable by all unprivileged users on the server.

Creating a dedicated SSL user, and especially a corresponding group, can help with this; it allows you make sure the private key is only readable by users who are members of this SSL group, and thus, control tightly which services will be able to use it.

Here’s how you can create this new dedicated user and group.

```console
# pw group add ssl -g 551
# pw user add ssl -u 551 -g 551 -c "SSL Unprivileged User" -d /var/empty -s /usr/sbin/nologin
```

You should also create the directories where you’ll be storing your certificates and private keys, with the right permissions.

```console
# mkdir -p /usr/local/etc/ssl/certs
# mkdir -p /usr/local/etc/ssl/private
# chown root:ssl /usr/local/etc/ssl/private
# chmod 710 /usr/local/etc/ssl/private
```


## Choosing an ACME client implementation

Obtaining an SSL/TLS certificate from Let’s Encrypt can be done by using a client tool that supports the [Automatic Certificate Management Environment (ACME)](https://en.wikipedia.org/wiki/Automatic_Certificate_Management_Environment) protocol.

While there is a rich ecosystem of [ACME client implementations](https://letsencrypt.org/docs/client-options/), a popular choice of ACME client tool is [`certbot`](https://certbot.eff.org/pages/about), which was originally developed by Let’s Encrypt as a reference implementation written in Python.

In this guide, we’ll be using `certbot`, mainly because it’s well supported and widely used, and also because it isn’t tied to one specific service that needs to use the certificate.


## Drawbacks of the standalone challenge method

One of the easiest ways to use `certbot` to create a new SSL/TLS certificate signed by Let’s Encrypt is to use the `standalone` option, which essentially spawns up a builtin web server to handle a cryptographic challenge meant to prove that we do control our domain name. However, the downside of this `standalone` option is that you have to temporarily shut down any web server you might have running on your server.

For example, assuming you have `nginx` running as a web server, you’ll need to invoke `certbot` as follows.

```console
# service nginx stop
# certbot certonly --standalone
# service nginx start
```

The `certbot` command will prompt you with various questions, such as which domain names to include in your certificate.

With such a certificate, when the time to renew the certificate comes, here is how you need to invoke `certbot` again.

```console
# service nginx stop
# certbot renew --standalone
# service nginx start
```

While this approach is very straightforward, it does introduce some unfortunate amount of downtime for our web server.


## Advantages of the DNS challenge method

As an alternative, `certbot` supports the DNS-01 challenge method, which requires a DNS server configured to allow `TXT` records to be updated in the zone file using RFC 2136 dynamic updates.

Unlike the standalone challenge method, the DNS-01 challenge method doesn’t require temporarily shutting down your main web server.

Furthermore, using the DNS-01 challenge method, Let’s Encrypt allows you to obtain wildcard SSL/TLS certificates for multiple domains with all of their subdomains, which is a very nice feature that can save you time when you want to spin-up a new subdomain with proper SSL/TLS certificate support for a new website or service down the road.


## Update `named` configuration for the DNS challenge method

The main thing we need to do to support the DNS challenge method is to allow certain `TXT` records to be updated in the relevant zone file using RFC 2136 dynamic updates. [^2]

[^2]: This part of the guide is inspired by [Patrick Terlisten’s great article on how to set up DNS-01 challenge validation with a local BIND instance](https://vcloudnine.de/using-lets-encrypt-dns-01-challenge-validation-with-local-bind-instance/).

### Create a TSIG key to secure dynamic updates

To allow a remote server to initiate a such a dynamic update securely, the first thing you need to do is to create a TSIG (Transaction Signature) key for `named`, on your primary authoritative name server.

```console
# cd /var/named/usr/local/etc/namedb
# tsig-keygen -a hmac-sha512 letsencrypt > letsencrypt.key
# chown bind letsencrypt.key
# chmod 600 letsencrypt.key
```

The key inside the `letsencrypt.key` file should look something like this.

```
key "letsencrypt" {
	algorithm hmac-sha512;
	secret "Qf[…]XdW/CIHfA==";
};
```

Obviously, the real TSIG key secret is considerably longer, as it will contain a lot of characters in place of `[…]`.

### Update local `named` configuration to allow dynamic updates

Assuming your [`named` configuration was modularized according to this guide](freebsd-dns-bind.md#modularize-configuration-file-for-named), you should review the [`named.conf.local`](dns/var/named/usr/local/etc/namedb/named.conf.local) file from the `homelab-documentation` repository, and uncomment the relevant portions of the file that relate to `letsencrypt`.

More specifically, you need to include this TSIG key file in your `named.conf.local` configuration file.

```
//-----------------------------------------------------------
// Let’s Encrypt Key
//-----------------------------------------------------------

include "/usr/local/etc/namedb/letsencrypt.key";
```

Then, you need to update the relevant [DNS zones configuration for which your DNS server is the primary authoritative name server](freebsd-dns-bind.md#dns-zones-configuration-as-primary).

```
zone "my_domain.tld" {
	type primary;
	file "primary-dynamic/my_domain.tld.zone";
	allow-query {
		any;
	};
	allow-transfer {
		buddyns-transfer;
	};
	notify yes;
	check-names warn;
	update-policy {
		grant letsencrypt name _acme-challenge.my_domain.tld. txt;
	};
};
```

The key additions here are:
 - the `update-policy` block, which allows updating TXT records for `_acme-challenge.my_domain.tld` using the `letsencrypt` TSIG key created [above](#create-a-tsig-key-to-secure-dynamic-updates);
 - the `check-names warn` directive, to avoid error logs related to the underscore in `_acme-challenge`. [^3]

[^3]: [Alexis Wilke’s guide on setting up BIND to obtain Let’s Encrypt wildcard certificates](https://linux.m2osw.com/setting-bind-get-letsencrypt-wildcards-work-your-system-using-rfc-2136) goes into a bit more detail about the importance of the `check-names warn` directive in your `named` configuration.

When you’re done with these configuration updates, restart `named`.

```console
# service named restart
```


## Install `certbot` with its DNS challenge plugin

If you’re using `poudriere` following [this guide](freebsd-poudriere.md), then add a few entries to the list of packages built by `poudriere`.

```console
# cat << EOF >> /usr/local/etc/poudriere.d/pkglist

# Let’s Encrypt SSL certificate utilities
security/py-certbot
security/py-certbot-dns-rfc2136
EOF
```

And build your packages again.

```console
# poudriere bulk \
    -j my_poudriere-arm64-15-1 \
    -p 2026Q3 \
    -f /usr/local/etc/poudriere.d/pkglist
```

Finally, on the target server machine, install `py312-certbot` and `py312-certbot-dns-rfc2136`.

```console
# pkg install py312-certbot py312-certbot-dns-rfc2136
```


## Create credentials file for the DNS challenge plugin

The DNS RFC 2136 challenge plugin for `certbot` requires a small credentials file with the essential information about our primary authoritative name server.

On the target server, create a file named `letsencrypt-dns-rfc2136-credentials.ini` in a new restricted folder at `/usr/local/etc/ssl/credentials`. Assuming you [fetched this homelab documentation](freebsd-command-line-tools.md#fetch-configuration-files) in `/homelab-documentation`, you can just copy the [`letsencrypt-dns-rfc2136-credentials.ini`](letsencrypt/usr/local/etc/ssl/credentials/letsencrypt-dns-rfc2136-credentials.ini) file into this new directory.

```console
# cd /usr/local/etc/ssl
# mkdir credentials
# chmod 700 credentials
# cd credentials
# cp -av /homelab-documentation/freebsd-server/letsencrypt/usr/local/etc/ssl/credentials/letsencrypt-dns-rfc2136-credentials.ini .
# chmod 600 letsencrypt-dns-rfc2136-credentials.ini
```

The `letsencrypt-dns-rfc2136-credentials.ini` file must contain the following entries.

 - `dns_rfc2136_server`: the IP address of your primary authoritative name server; if this is the same machine as the one you want to use `certbot` on, you can just use `127.0.0.1`; otherwise, you’ll have to use the public IP address of your primary authoritative name server.
 - `dns_rfc2136_name`: the name of your TSIG key; this should match the last argument of your `tsig-keygen` call [above](#create-a-tsig-key-to-secure-dynamic-updates).
 - `dns_rfc2136_secret`: the `secret` present in your TSIG key.
 - `dns_rfc2136_algorithm`: the algorithm used for generating your TSIG key; this should match the algorithm option `-a` of your `tsig-keygen` call [above](#create-a-tsig-key-to-secure-dynamic-updates).

Hence, the `letsencrypt-dns-rfc2136-credentials.ini` file should look something like this.

```
dns_rfc2136_server = 127.0.0.1
dns_rfc2136_name = letsencrypt
dns_rfc2136_secret = Qf[…]XdW/CIHfA==
dns_rfc2136_algorithm = HMAC-SHA512
```


## Obtain your initial wildcard SSL/TLS certificate with `certbot`

Now you’re finally ready to invoke `certbot` with the DNS RFC 2136 plugin to get your initial wildcard SSL/TLS certificate for `my_domain.tld` and all of its first-level subdomains.

```console
# certbot certonly \
    --dns-rfc2136 \
    --dns-rfc2136-credentials /usr/local/etc/ssl/credentials/letsencrypt-dns-rfc2136-credentials.ini \
    --dns-rfc2136-propagation-seconds 180 \
    -d my_domain.tld -d '*.my_domain.tld'
```

If you have multiple domains you’d like to include in this SSL/TLS certificate, you can pass more `-d` arguments at the end. For example, to also include `my_other_domain.tld` and all of its first-level subdomains, you can invoke `certbot` like this.

```console
# certbot certonly \
    --dns-rfc2136 \
    --dns-rfc2136-credentials /usr/local/etc/ssl/credentials/letsencrypt-dns-rfc2136-credentials.ini \
    --dns-rfc2136-propagation-seconds 180 \
    -d my_domain.tld -d '*.my_domain.tld' \
    -d my_other_domain.tld -d '*.my_other_domain.tld'
```

When you run this command for the first time, `certbot` will automatically create an account for you, which requires you to provide your email address, and agree to the terms of service for Let’s Encrypt.

Once you finish answering these initial questions, `certbot` requests the creation of a certificate for your domains, and you should see output like this.

```
Account registered.
Requesting a certificate for my_domain.tld and 3 more domains
Waiting 180 seconds for DNS changes to propagate
```

If you encounter timeouts related to DNS propagation, you can increase the related delay with the `--dns-rfc2136-propagation-seconds` option. However, this kind of error is usually better handled by [accelerating DNS zone replication using `nsnotifyd`](freebsd-faster-dns-replication-nsnotifyd.md).

After that delay to allow DNS changes to propagate, if the certificate was successfully created, you should see some more output like this.

```
Successfully received certificate.
Certificate is saved at: /usr/local/etc/letsencrypt/live/my_domain.tld/fullchain.pem
Key is saved at:         /usr/local/etc/letsencrypt/live/my_domain.tld/privkey.pem
This certificate expires on 2026-11-13.
These files will be updated when the certificate renews.
```

### Expected `named` server logs

You can confirm the dynamic updates were performed as expected by monitoring the `named` log file for the term `‌_acme-challenge`.

```console
# tail -f /var/named/var/log/named.log | grep -i _acme-challenge
```

You should see logs like this (date and time omitted) at the beginning of the certificate request.

```
update: client @0x4f8f54672000 127.0.0.1#15665/key letsencrypt: updating zone 'my_domain.tld/IN': adding an RR at '_acme-challenge.my_domain.tld' TXT "TyDIhEnzKhjtEo0uSZ1uNKJMRt7zKvQZwRSq16GNWo4"
update: client @0x4f8f55b7d800 127.0.0.1#24819/key letsencrypt: updating zone 'my_domain.tld/IN': adding an RR at '_acme-challenge.my_domain.tld' TXT "SbhFhyxzHVkXvzCvl45TzVFjerPLsuT1dONjgLCwtkk"
```

And you should see logs like this after the delay to allow DNS changes to propagate.

```
update: client @0x4f8f55652800 127.0.0.1#20994/key letsencrypt: updating zone 'my_domain.tld/IN': deleting an RR at _acme-challenge.my_domain.tld TXT
update: client @0x4f8f5355a800 127.0.0.1#12404/key letsencrypt: updating zone 'my_domain.tld/IN': deleting an RR at _acme-challenge.my_domain.tld TXT
```

### Inspect new SSL/TLS certificate

If you want to inspect this certificate via command-line, you can do so with the following command.

```console
# openssl x509 -in /usr/local/etc/letsencrypt/live/my_domain.tld/cert.pem \
    -noout \
    -subject -issuer -dates \
    -ext subjectAltName,keyUsage,extendedKeyUsage
```

Here’s what the output of that command should look like.

```
subject=CN=my_domain.tld
issuer=C=US, O=Let's Encrypt, CN=YE2
notBefore=Aug 15 22:10:41 2026 GMT
notAfter=Nov 13 22:10:40 2026 GMT
X509v3 Key Usage: critical
    Digital Signature
X509v3 Extended Key Usage: 
    TLS Web Server Authentication
X509v3 Subject Alternative Name: 
    DNS:*.my_domain.tld, DNS:*.my_other_domain.tld, DNS:my_domain.tld, DNS:my_other_domain.tld
```


## Create symbolic links to certificate in `/usr/local/etc/ssl`

After you create a new Let’s Encrypt signed certificate, you may want to create symbolic links to the commonly used components of this certificate, in `/usr/local/etc/ssl`. For example, assuming you just created a wildcard certificate for `my_domain.tld` as described above, run the following commands:

```console
# cd /usr/local/etc/ssl/certs
# ln -s ../../letsencrypt/live/my_domain.tld/fullchain.pem my_domain.tld_wildcard.pem
# cd /usr/local/etc/ssl/private
# ln -s ../../letsencrypt/live/my_domain.tld/privkey.pem my_domain.tld_wildcard.key
```


## Adjust file permissions

Every time you create or renew a Let’s Encrypt signed certificate with `certbot`, make sure to adjust permissions so the private key can be read by any user that belongs to the newly created `ssl` group.

```console
# cd /usr/local/etc/letsencrypt
# chown -R -h root:ssl live archive
# chmod g+x live archive
# chmod g+r archive/*/privkey*.pem
```


## Automate certificate renewal

Assuming you [configured your `/etc/periodic.conf` to enable a modular periodic scripts configuration](freebsd-modular-periodic-scripts-configuration.md#scaffolding-for-modular-periodic-scripts-configuration), you can set this up with a new [`letsencrypt-certificate-automatic-renewal.conf`](letsencrypt/usr/local/etc/periodic.conf.d/letsencrypt-certificate-automatic-renewal.conf) file in `/usr/local/etc/periodic.conf.d`.

```console
# cd /usr/local/etc/periodic.conf.d
# ln -s ../../../../homelab-documentation/freebsd-server/letsencrypt/usr/local/etc/periodic.conf.d/letsencrypt-certificate-automatic-renewal.conf
```

Then you’ll need to automate adjusting the permissions of new SSL/TLS certificates, as well as restarting any services that use those certificates. You can do so by adding symbolic links to a couple of executable scripts in the `post` `renewal-hooks` directory for Let’s Encrypt.

```console
# cd /usr/local/etc/letsencrypt/renewal-hooks/post
# ln -s ../../../../../../homelab-documentation/freebsd-server/letsencrypt/usr/local/etc/letsencrypt/renewal-hooks/post/fix-ssl-certificate-permissions
# ln -s ../../../../../../homelab-documentation/freebsd-server/letsencrypt/usr/local/etc/letsencrypt/renewal-hooks/post/restart-services-requiring-ssl-certificate
```

Manually edit `/usr/local/etc/letsencrypt/renewal-hooks/post/restart-services-requiring-ssl-certificate` to include instructions for restarting any services you run on your server that use your SSL/TLS certificate.

And finally, if you normally use `named-reset-dynamic-zone-files` to help you [reconcile handcrafting your zone files with DNS dynamic updates](freebsd-dns-bind.md#considerations-for-dynamic-updates), you can also add that script as an additional hook.

```console
# cd /usr/local/etc/letsencrypt/renewal-hooks/post
# ln -s ../../../../../../homelab-documentation/freebsd-server/letsencrypt/usr/local/etc/letsencrypt/renewal-hooks/post/named-reset-dynamic-zone-files
```