# Web server with `nginx` and PHP on FreeBSD

One of the most essential services for your homelab is a web server, which can be useful to host simple websites with static pages, a dynamic website with PHP, or to act as a reverse proxy for an application reachable via HTTP on a local port.

A very popular option for these use-cases is [`nginx`](https://nginx.org), which is a high-performance and versatile web server. In this guide, we’ll cover how to set up `nginx` on FreeBSD, along with support for PHP with `php-fpm`.

## Keeping your `nginx` configuration organized

A single instance of `nginx` is able to handle requests for various websites, which are commonly referred to as virtual hosts.

Although `nginx` reads a single configuration file, `/usr/local/etc/nginx/nginx.conf`, it supports `include` directives, which allow for a more modular configuration.

**One file per virtual host.** Adding a virtual host is as simple as adding a new configuration file in the `/usr/local/etc/nginx/sites-enabled` directory, with the `.conf` extension, and reloading.

**Reusable snippets for identical options across virtual hosts.** A handful of small files sit directly in `/usr/local/etc/nginx`, each holding one reusable block of directives.

 - [`ssl_parameters`](nginx/usr/local/etc/nginx/ssl_parameters)
	 - Protocol versions and session resumption settings, included once at the `http` level so every virtual host inherits them.
 - [`ssl_wildcard_certificate`](nginx/usr/local/etc/nginx/ssl_wildcard_certificate)
	 - The certificate and key to serve, included in each virtual host that requires a secure connection.
 - [`redirect_to_ssl`](nginx/usr/local/etc/nginx/redirect_to_ssl)
	 - A permanent redirect to the `https` version of the same URL, which is the entire body of a plain HTTP virtual host.
 - [`error_pages`](nginx/usr/local/etc/nginx/error_pages)
	 - Common directives related to error pages used when a file cannot be served or another error occurs.
 - [`php`](nginx/usr/local/etc/nginx/php)
	 - Hands `.php` files to `php-fpm`, in whichever virtual host serves them.

PHP is not served directly by `nginx`. Instead, `php-fpm` runs as a separate daemon and `nginx` forwards `.php` requests to it over FastCGI. Since both run on the same machine, they talk over a Unix socket at `/var/run/php-fpm.sock` rather than a TCP port, which keeps the FastCGI endpoint out of reach of the network entirely.


## Install `nginx` and PHP

If you’re using `poudriere` following [this guide](freebsd-poudriere.md), then add a few entries to the list of packages built by `poudriere`.

```console
# cat << EOF >> /usr/local/etc/poudriere.d/pkglist

# Web server and PHP
www/nginx
lang/php84
EOF
```

And build your packages again.

```console
# poudriere bulk \
    -j my_poudriere-arm64-15-1 \
    -p 2026Q3 \
    -f /usr/local/etc/poudriere.d/pkglist
```

Finally, on the target server machine, install the packages.

```console
# pkg install nginx
# pkg install php84
```

The `nginx` server runs as the `www` user, which comes with the FreeBSD base system. It needs to read your certificate, so add it to the `ssl` group created in [the guide on SSL/TLS certificates](freebsd-ssl-tls-lets-encrypt.md#create-ssl-user-and-group).

```console
# pw group mod ssl -m www
```


## Configure PHP

For PHP, you should start by copying the sample configuration file `php.ini-production` into `/usr/local/etc/php.ini`. The most important change you should make is to disable `php-fpm` listening on a TCP port, and instead to make it listen on a Unix socket.

Assuming you [fetched this homelab documentation](freebsd-command-line-tools.md#fetch-configuration-files) in `/homelab-documentation`, you can apply this recommended configuration with a single script.

```console
# cd /homelab-documentation/freebsd-server/php/patches
# ./configure_php
```

You should then manually edit `/usr/local/etc/php.ini` to set your own timezone, which is needed for PHP’s date functions.

```
[Date]
; Defines the default timezone used by the date functions
; https://php.net/date.timezone
date.timezone = America/Los_Angeles
```


## Enable and start `php-fpm`

At this point, you can enable the `php-fpm` service. [^1]

[^1]: As shown in [Modular system configuration on FreeBSD](freebsd-modular-system-configuration.md). Note that the discrete system configuration file is named `php_fpm`, with an underscore, even though the service startup script is `php-fpm`; this is one of the cases described in [Naming rules for discrete system configuration files](freebsd-modular-system-configuration.md#naming-rules-for-discrete-system-configuration-files).

```console
# cat << EOF > /usr/local/etc/rc.conf.d/php_fpm
# /usr/local/etc/rc.conf.d/php_fpm: system configuration for php-fpm

php_fpm_enable="YES"
EOF
```

Alternatively, you may enable this service by creating a simple symbolic link to the provided system configuration file.

```console
# cd /usr/local/etc/rc.conf.d
# ln -s ../../../../homelab-documentation/freebsd-server/php/usr/local/etc/rc.conf.d/php_fpm
```

Now you can start the `php-fpm` service.

```console
# service php_fpm start
```

As a quick sanity check, confirm that the socket was created with the correct permissions.

```console
# ls -l /var/run/php-fpm.sock
srw-rw----  1 www www 0 Sep  6 21:33 /var/run/php-fpm.sock
```


## Configure `nginx`

Replace the default `nginx.conf`, and add the reusable snippets alongside it, as symbolic links to the files provided in this repository.

```console
# cd /usr/local/etc/nginx
# rm -f nginx.conf
# for file_name in nginx.conf error_pages php redirect_to_ssl ssl_parameters ssl_wildcard_certificate; \
  do \
      ln -s ../../../../homelab-documentation/freebsd-server/nginx/usr/local/etc/nginx/${file_name}; \
  done
```

Manually edit the two paths in [`ssl_wildcard_certificate`](nginx/usr/local/etc/nginx/ssl_wildcard_certificate) to point at your own certificate; they map closely to what you get with Let’s Encrypt following [the guide on SSL/TLS certificates](freebsd-ssl-tls-lets-encrypt.md#create-symbolic-links-to-certificate-in-usrlocaletcssl). [^2]

[^2]: For such private edits to configuration files used from the `homelab-documentation` repository with a symbolic link, please consider following the recommended approach for [private configuration tweaks on a dedicated branch](freebsd-private-configuration-tweaks.md#create-a-machine-specific-branch).

`nginx` writes its logs to `/var/log/nginx`, so create that directory before starting it.

```console
# mkdir -p /var/log/nginx
```

To avoid those log files growing indefinitely, make sure to add support for rotating them with a new `nginx`-specific configuration file for `newsyslog`.

```console
# mkdir -p /usr/local/etc/newsyslog.conf.d
# cd /usr/local/etc/newsyslog.conf.d
# ln -s ../../../../homelab-documentation/freebsd-server/nginx/usr/local/etc/newsyslog.conf.d/nginx.conf
```

Finally, add the catch-all virtual host, which answers for any name that no other virtual host claims. Without it, such a request would be served by whichever virtual host happens to be loaded first, which might not be a reasonable default fallback.

```console
# mkdir -p /usr/local/etc/nginx/sites-enabled
# cd /usr/local/etc/nginx/sites-enabled
# ln -s ../../../../../homelab-documentation/freebsd-server/nginx/usr/local/etc/nginx/sites-enabled/default.conf
```


## Enable and start `nginx`

At this point, you can enable the `nginx` service. [^3]

[^3]: As shown in [Modular system configuration on FreeBSD](freebsd-modular-system-configuration.md).

```console
# cat << EOF > /usr/local/etc/rc.conf.d/nginx
# /usr/local/etc/rc.conf.d/nginx: system configuration for nginx

nginx_enable="YES"
nginx_reload_quiet="YES"
EOF
```

Alternatively, you may enable this service by creating a simple symbolic link to the provided system configuration file.

```console
# cd /usr/local/etc/rc.conf.d
# ln -s ../../../../homelab-documentation/freebsd-server/nginx/usr/local/etc/rc.conf.d/nginx
```

Before starting anything, ask `nginx` to check that it can read and understand its whole configuration.

```console
# nginx -t
nginx: the configuration file /usr/local/etc/nginx/nginx.conf syntax is ok
nginx: configuration file /usr/local/etc/nginx/nginx.conf test is successful
```

Now you can start the `nginx` service.

```console
# service nginx start
```


## Firewall configuration for `nginx`

A web server is only useful if it can be reached, which requires opening ports 80 and 443.

Assuming you already configured `pf` as a firewall as shown in [Configuring firewall with `pf` on FreeBSD](freebsd-firewall.md), all you need to do is to ensure `http` and `https` are included in the `tcp_services` variable, and reload `pf` rules.

```console
# service pf reload
```


## Anatomy of a simple virtual host configuration file

Each specific website hosted with `nginx` needs to be set up with its own virtual host configuration file, which is a simple file with the `.conf` extension in the `/usr/local/etc/nginx/sites-enabled` directory.

For a very simple website, you can use the provided [sample virtual host](nginx/sample-sites/my_domain.tld.conf) as a baseline, and modify it with your own domain and settings.

```console
# cd /usr/local/etc/nginx/sites-enabled
# cp /homelab-documentation/freebsd-server/nginx/sample-sites/my_domain.tld.conf .
```

Typically, you should manually edit this file to use your own domain name in the `server_name` directives, as well as in the name of the file itself, and customize the `root` directory as needed.

### Automatic redirect to SSL

The first part of the virtual host configuration file is just a few lines to declare the server names that should activate this virtual host, and a directive to automatically redirect to the `https` version of the address being loaded.

```
server {
    listen       80;
    listen       [::]:80;
    server_name  my_domain.tld www.my_domain.tld;
    include redirect_to_ssl;
}
```

### Server block for `https` with an SSL certificate

The virtual host configuration file includes a second `server` block for connections via `https` with an SSL certificate. It also includes other configuration options that make this virtual host distinct from others, such as the `root` directive, which points to the directory on the server where the website’s content is located.

```
server {
    listen       443 ssl;
    listen       [::]:443 ssl;
    http2        on;
    server_name  my_domain.tld www.my_domain.tld;

    include ssl_wildcard_certificate;

    root /usr/local/www/my_domain.tld;
    include error_pages;
    include php;

    client_max_body_size 50m;
}
```

A quick note on `client_max_body_size`: its default value of 1 MB is low enough that an ordinary photo upload fails with a confusing `413` error; to avoid this issue with a virtual host that accepts uploads, just raise this limit to a more reasonable value.

Since PHP is enabled in this `server` block with the directive `include php`, we can run a quick test to confirm that PHP is working as expected.

```console
# mkdir -p /usr/local/www/my_domain.tld
# echo "<?php phpinfo(); ?>" > /usr/local/www/my_domain.tld/index.php
```

Then check the configuration and reload.

```console
# nginx -t
# service nginx reload
```

You can then visit your website in your favorite web browser, at `http://my_domain.tld/`; you should see it automatically redirect to the `https` version of the website, with a valid SSL certificate, and the standard PHP info screen, which includes a lot of detailed information on your local PHP installation.

Now, remove this `index.php` file:

```console
# rm -f /usr/local/www/my_domain.tld/index.php
```

And feel free to add in its place something more useful, like your own website.