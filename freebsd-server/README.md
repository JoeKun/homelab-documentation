# FreeBSD Server Documentation

These documents are produced in the course of my journey to set up my own server infrastructure for personal use, largely to increase my level of digital sovereignty.

While each document attempts to cover its own topic thoroughly, it’s possible that some document will rely on prerequisites covered in another document. Sometimes, that may be explicitly called out, whereas in other instances it may not be obvious.

If you suspect there may be an unspecified prerequisite in any of these documents, it may be helpful to know the order of documents which corresponds to how I configured my own server.

## General setup

 1. [FreeBSD on Ampere Altra Server](freebsd-ampere-altra.md)
 2. [Remote access with SSH on FreeBSD](freebsd-remote-access-ssh.md)
 3. [Synchronizing time with NTP on FreeBSD](freebsd-network-time-synchronization-ntp.md)
 4. [Network file sharing with NFS on FreeBSD](freebsd-network-file-sharing-nfs.md)
 5. [FreeBSD guest virtual machine on Debian KVM hypervisor host](freebsd-guest-on-debian-kvm-hypervisor.md)
 6. [Custom package management for FreeBSD with `poudriere`](freebsd-poudriere.md)
 7. [Useful command-line tools for FreeBSD](freebsd-command-line-tools.md)
 8. [Private configuration tweaks on a dedicated branch](freebsd-private-configuration-tweaks.md)
 9. [Using a Unicode locale on FreeBSD](freebsd-unicode-locale.md)
 10. [Creating an unprivileged user on FreeBSD](freebsd-unprivileged-user.md)
 11. [Mount special file systems on FreeBSD](freebsd-special-file-systems.md)
 12. [Modular system configuration on FreeBSD](freebsd-modular-system-configuration.md)
 13. [Modular periodic scripts configuration on FreeBSD](freebsd-modular-periodic-scripts-configuration.md)
 14. [Storage health monitoring with `smartd` on FreeBSD](freebsd-storage-health-monitoring-smart.md)
 15. [Configuring firewall with `pf` on FreeBSD](freebsd-firewall.md)


## Domain name service

 16. [Authoritative DNS server with BIND on FreeBSD](freebsd-dns-bind.md)
 17. [Faster DNS zone replication with `nsnotifyd` on FreeBSD](freebsd-faster-dns-replication-nsnotifyd.md)


## SSL/TLS certificates

 18. [SSL/TLS certificates with Let’s Encrypt on FreeBSD](freebsd-ssl-tls-lets-encrypt.md)


## Web server

 19. [Web server with `nginx` and PHP on FreeBSD](freebsd-web-server-nginx-php.md)


## Directory services

 20. [LDAP directory services with OpenLDAP on FreeBSD](freebsd-ldap.md)


## Databases

 21. [In-memory data store with Redis on FreeBSD](freebsd-redis.md)
