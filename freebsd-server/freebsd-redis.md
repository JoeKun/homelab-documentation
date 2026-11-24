# In-memory data store with Redis on FreeBSD

Many large services you might want to set up in your homelab may require an in-memory data store like [Redis](https://redis.io).

This guide shows how to install Redis on FreeBSD in such a way that each service has its own dedicated Redis instance. With this isolation between the different Redis instances, each one gets its own memory limit, data file and log, and can be restarted on its own.

## General approach for Redis with multiple instances

The startup script provided with Redis on FreeBSD already supports multiple instances, which it calls profiles.

**One configuration file per instance.** A profile named `my_service` runs `redis-server` with `/usr/local/etc/redis-my_service.conf`. That file starts by including the global `/usr/local/etc/redis.conf`, and then only overrides what must differ from one instance to the next.

**One system configuration file per instance.** Each profile is declared in its own small file in the `/usr/local/etc/rc.conf.d/redis` directory, so adding an instance is as simple as adding a file.

**A Unix socket instead of a TCP port.** For a simple homelab setup, you may have all your services that depend on Redis running on the same machine. In this scenario, it is viable for each instance to listen on its own Unix socket in `/var/run/redis`; this simplifies networking setup, including from a firewall perspective.


## Install Redis

If you’re using `poudriere` following [this guide](freebsd-poudriere.md), then add Redis to the list of packages built by `poudriere`.

```console
# cat << EOF >> /usr/local/etc/poudriere.d/pkglist
databases/redis
EOF
```

And build your packages again.

```console
# poudriere bulk \
    -j my_poudriere-arm64-15-1 \
    -p 2026Q3 \
    -f /usr/local/etc/poudriere.d/pkglist
```

Finally, on the target server machine, install the package.

```console
# pkg install redis
```

The package creates the `redis` user and group, the directories `/var/db/redis`, `/var/log/redis` and `/var/run/redis`, and installs the global configuration file `/usr/local/etc/redis.conf`.

Leave that global configuration file as it is. Once any profile is declared, the global file is never used to start a server of its own; it only serves as the common baseline included by every instance, which already binds to the loopback interface only.


## Prepare the Redis service for multiple instances

Create the directory that will hold one system configuration file per instance. [^1]

[^1]: As shown in [Modular system configuration on FreeBSD](freebsd-modular-system-configuration.md). When `/usr/local/etc/rc.conf.d/redis` is a directory rather than a file, every file inside it is loaded, as described in the `rc.conf(5)` manual page.

```console
# mkdir -p /usr/local/etc/rc.conf.d/redis
```

For now, this directory is empty, so the `redis` service remains disabled; it only becomes enabled once we add at least one instance.


## Add a dedicated instance of Redis for a service

The steps below add an instance of Redis for a service named `my_service`; make sure to replace this name with the name of your service that needs to use Redis.

### Data directory

Create the directory where this instance will save its data.

```console
# mkdir /var/db/redis/my_service
# chown redis:redis /var/db/redis/my_service
```

### Redis configuration

Copy the provided [sample instance configuration file](redis/sample-instances/usr/local/etc/redis-my_service.conf) next to the global one, with a name that matches your service.

```console
# cd /usr/local/etc
# cp /homelab-documentation/freebsd-server/redis/sample-instances/usr/local/etc/redis-my_service.conf redis-my_service.conf
```

Manually edit this file to replace every occurrence of `my_service` with the name of your service. The value of `pidfile` in particular must stay `/var/run/redis/` followed by the profile name and `.pid`, since that’s where the service startup script looks for the process it needs to stop.

Here is what the configuration file for your dedicated instance of Redis should look like.

```
include /usr/local/etc/redis.conf

port 0
unixsocket /var/run/redis/my_service.sock
unixsocketperm 770

pidfile /var/run/redis/my_service.pid
logfile /var/log/redis/my_service.log
dbfilename my_service.rdb
dir /var/db/redis/my_service/

# maxmemory 200M
```

Setting `port` to `0` turns off the TCP port that the global configuration file would otherwise open, which leaves the Unix socket as the only way in.

If the service uses its instance as a cache, consider uncommenting `maxmemory`, so that the instance cannot grow without bounds.

### Logging configuration

To avoid the log file growing indefinitely, make sure to add support for rotating it with a new `redis-my_service`-specific configuration file for `newsyslog`.

```console
# mkdir -p /usr/local/etc/newsyslog.conf.d
# cd /usr/local/etc/newsyslog.conf.d
# cp /homelab-documentation/freebsd-server/redis/sample-instances/usr/local/etc/newsyslog.conf.d/redis-my_service.conf redis-my_service.conf
```

Once again, manually edit this new file to replace every occurrence of `my_service` with the name of your service.

### Enable and start your new dedicated instance of Redis

Declare the new profile, which also enables the `redis` service.

```console
# cat << EOF > /usr/local/etc/rc.conf.d/redis/my_service
# /usr/local/etc/rc.conf.d/redis/my_service: system configuration for the redis instance dedicated to my_service

redis_enable="YES"
redis_profiles="\${redis_profiles} my_service"
EOF
```

Now you can start this instance on its own, without touching any other instance.

```console
# service redis start my_service
```

As a quick sanity check, ask the new instance to answer through its socket.

```console
# redis-cli -s /var/run/redis/my_service.sock ping
PONG
```


## Grant a service access to its Redis instance

With `unixsocketperm 770`, the socket is only accessible to the `redis` user and to members of the `redis` group. The service’s own user therefore needs to join that group.

For instance, for a PHP application served by `nginx`, whose code runs as the `www` user:

```console
# pw group mod redis -m www
```

The service can then be configured to connect to its instance through the socket path, `/var/run/redis/my_service.sock`, and port `0`, which is how most clients express the absence of a TCP port.