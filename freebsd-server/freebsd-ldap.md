# LDAP directory services with OpenLDAP on FreeBSD

Once a homelab runs more than one user-facing service, you may want to unify the user and group management layer across those services. This is commonly solved with a directory service, which can hold people and groups in a central location that multiple services can integrate with.

This guide covers how to set up a directory service on FreeBSD using [OpenLDAP](https://www.openldap.org) for a multiple domain setup as well as system accounts and policies, to support a local mail server and other services.

## Design and architecture of the directory

The most important aspect of setting up a new LDAP directory is to list out the goals and requirements for our organization, so we can try and design a shape of the directory that meets all of our expectations. Some changes to the directory structure can be pretty challenging to implement once it’s all up and running, so the upfront investment you make in this initial design phase is certainly worth it.

### Requirements

For this setup, here are the main requirements.

 1. **Essential text based metadata for users**
	 - Including first name, surname (family name), identifier, email address.
 2. **Support for multiple email aliases per user**
	 - `user@my_domain.tld` may want to be reachable via `support@my_domain.tld` and `feedback@my_domain.tld`.
 3. **Support for redirecting email externally**
	 - `user@my_domain.tld` might choose to redirect email to `john.smith@external-email-provider.com`.
 4. **Support for mail delivery to a local mailbox**
	 - `user@my_domain.tld` might prefer instead to deliver email locally on the server.
 5. **Support for sending mail for alias accounts with a password**
	 - `scanner@my_domain.tld` can be set up with a password to authenticate with a mail server for sending scans via email, while not being able to sign into other applications on the server.
 6. **Support for multiple domains as isolated tenants**
	 - `contact@my_domain.tld` and `contact@my_other_domain.xyz` can coexist as distinct users.
	 - `staff` in `my_domain.tld` and `staff` in `my_other_domain.xyz` can coexist as distinct groups.
 7. **Domain management with simple LDAP directory updates**
	 - Adding a new domain should not require changing the OpenLDAP configuration itself, and ideally it should not require changing the configuration of most of the services that integrate with this LDAP directory.
 8. **System-wide groups for gating access to applications**
	 - `user@my_domain.tld` and `worker@my_other_domain.xyz` can both use `my_application`.
 9. **Access-lists to protect sensitive data in the directory**
	 - Service accounts should only be able to read the data they actually need.

### High-level overview of the directory hierarchy

LDAP offers a few common data components and attributes, which you can learn about in this great introductory article: [Understanding the LDAP Protocol, Data Hierarchy, and Entry Components](https://www.digitalocean.com/community/tutorials/understanding-the-ldap-protocol-data-hierarchy-and-entry-components).

To meet the requirements above, our directory tree has one branch per domain you serve, and one for system-wide accounts and groups.

```
o=homelab
├── ou=my_domain.tld           a domain, with its own users and groups
├── ou=my_other_domain.xyz     another domain, with its own users and groups
└── ou=system                  service accounts, and system-wide groups
```

**The suffix is an organization, not a domain.**  
Several domains are served here and no single one of them owns the directory, so using something like `o=homelab` as the suffix allows treating all domains equally.

**A domain is an `ou` carrying an `associatedDomain`, not a `dc`.**  
The `dc` attribute holds one DNS label, so a domain name maps to `dc=my_domain,dc=tld` and never to `dc=my_domain.tld`. Here a domain is data rather than the root of the tree, and every lookup arrives with the whole name.

```
dn: ou=my_domain.tld,o=homelab
objectClass: organizationalUnit
objectClass: domainRelatedObject
ou: my_domain.tld
associatedDomain: my_domain.tld
```

`associatedDomain` comes from the built-in object class `domainRelatedObject`, and means precisely “the DNS domain associated with this object”.

**Each domain has its own users.**  
`user@my_domain.tld` and `user@my_other_domain.xyz` can be two different people, with separate passwords and separate mailboxes. That’s why the tree branches by domain rather than pooling everyone together. This point also applies to groups.

### Mail handling rules

Four attributes of an entry influence how mail addressed to it is handled.

 - `mailLocalAddress` lists every address the entry accepts, always fully qualified.
 - `mailRoutingAddress`, when present, is where that mail is forwarded; its absence means the mail is delivered to a local mailbox instead.
 - `mail` is the address the entry publishes and signs in with; it never redirects mail elsewhere, but, for an entry without a `mailRoutingAddress`, the `mail` attribute determines the canonical name of the local mailbox: a mail server delivering locally rewrites the other addresses into the value of `mail` first.
 - `userPassword`, when present, means the entry can authenticate.

So, for example, a person with a password and no routing address has a local mailbox; an entry with a routing address and no password is a plain alias.

Both `mailLocalAddress` and `mailRoutingAddress` come from the built-in object class `inetLocalMailRecipient`.

### Custom schemas

Almost everything above uses built-in object classes and attributes, which ship as part of OpenLDAP. However, to achieve all of our requirements, we need to add two custom schemas.

 - [`virtual_mail.schema`](ldap/opt/local/etc/openldap/schema/virtual_mail.schema) includes markers for domains that accept delivery to local mailboxes or only aliases, as well as a marker for an account to be allowed to submit mail without having a local mailbox.
 - [`published_group.schema`](ldap/opt/local/etc/openldap/schema/published_group.schema) includes a marker for a group to be exposed to other applications on the server, and requires it to carry a globally unique `displayName`.

Not every group needs to be published; for example, it’s usually undesirable to mark as published the system-wide groups for gating access to applications on the server.

While these schemas add new object classes that can serve as specific markers, they don’t define any custom attribute.

### Access control

Ordinary users don’t require any read or write access to any part of the LDAP directory. A service or application typically finds a user entry using its own service account and then binds as the user to check the password. All a user needs is the right to authenticate.

Services are granted read access to specific sets of attributes, based on the minimum level of access they need. This access is defined by specific access-lists in the server’s configuration which are mapped to dedicated system groups that grant specific capabilities. Those groups live in `ou=capabilities,ou=system` rather than beside the ordinary groups, since granting read access to the LDAP directory is a different matter from saying who may use an application, and keeping the two apart puts a capability out of reach of the options that add someone to a group.

Here is the list of available capabilities for service accounts.

 - `service-accounts`: the bare minimum any client needs to use the LDAP directory; granted to every service account by default;
 - `user-authenticators`: allows a service to find a user’s entry and bind using their credentials, without actually granting read access to the stored password hash;
 - `mail-routing-readers`: allows a mail server to resolve the email addresses and destinations for mail routing purposes;
 - `group-membership-readers`: allows access to groups that can be visible to services or applications that support functionality based on group membership;
 - `user-profile-readers`: allows access to users’ personal metadata attributes, such as their name.

And now that we have a good handle on the design and architecture of our directory, we can begin with the installation process.


## Install OpenLDAP

If you’re using `poudriere` following [this guide](freebsd-poudriere.md), then add an entry to the list of packages built by `poudriere`.

```console
# cat << EOF >> /usr/local/etc/poudriere.d/pkglist

# LDAP directory services
net/openldap26-server
EOF
```

And build your packages again.

```console
# poudriere bulk \
    -j my_poudriere-arm64-15-1 \
    -p 2026Q3 \
    -f /usr/local/etc/poudriere.d/pkglist
```

Finally, on the target server machine, install `openldap26-server`. The client tools come with it as a dependency.

```console
# pkg install openldap26-server
```

The package creates an `ldap` user for the server to run as. It needs to read your certificate, so add it to the `ssl` group created in [the guide on SSL/TLS certificates](freebsd-ssl-tls-lets-encrypt.md#create-ssl-user-and-group).

```console
# pw group mod ssl -m ldap
```


## Configure OpenLDAP

OpenLDAP comes with a daemon named `slapd`, which stands for “Standalone LDAP Daemon”.

`slapd` uses a main configuration file named `slapd.ldif`, which is read exactly once, when the configuration database is built initially; hence, editing it afterwards changes nothing and a later change has to go through `ldapmodify` against `cn=config`.

Assuming you [fetched this homelab documentation](freebsd-command-line-tools.md#fetch-configuration-files) in `/homelab-documentation`, you can start by creating a symbolic link to the provided [`slapd.ldif`](ldap/usr/local/etc/openldap/slapd.ldif) file.

```console
# cd /usr/local/etc/openldap
# rm -f slapd.ldif
# ln -s ../../../../homelab-documentation/freebsd-server/ldap/usr/local/etc/openldap/slapd.ldif
```

Manually edit the file to use your own domain name for the `olcTLS*` directives in the TLS support section; the paths used in this provided configuration file map closely to what you get with Let’s Encrypt following [the guide on SSL/TLS certificates](freebsd-ssl-tls-lets-encrypt.md). [^1]

[^1]: For such private edits to configuration files used from the `homelab-documentation` repository with a symbolic link, please consider following the recommended approach for [private configuration tweaks on a dedicated branch](freebsd-private-configuration-tweaks.md#create-a-machine-specific-branch).

Feel free to familiarize yourself with the rest of the `slapd.ldif` configuration file, which includes various comments with more details on how certain key aspects of the configuration are defined.

You’ll also need to install the custom schemas in `/opt/local/etc/openldap/schema`.

```console
# mkdir -p /opt/local/etc/openldap/schema
# cd /opt/local/etc/openldap/schema
# for schema_name in virtual_mail published_group; \
  do \
      ln -s ../../../../../homelab-documentation/freebsd-server/ldap/opt/local/etc/openldap/schema/${schema_name}.schema; \
      ln -s ../../../../../homelab-documentation/freebsd-server/ldap/opt/local/etc/openldap/schema/${schema_name}.ldif; \
  done
```


## Build the configuration database

Now you need to use `slapadd` to turn this `slapd.ldif` file into the configuration database `slapd` actually uses.

```console
# mkdir -p /usr/local/etc/openldap/slapd.d
# slapadd -v -n0 -F /usr/local/etc/openldap/slapd.d -l /usr/local/etc/openldap/slapd.ldif
```

You should see output similar to this.

```
added: "cn=config" (00000001)
added: "cn=module{0},cn=config" (00000001)
added: "cn=schema,cn=config" (00000001)
added: "cn={0}core,cn=schema,cn=config" (00000001)
added: "cn={1}cosine,cn=schema,cn=config" (00000001)
added: "cn={2}inetorgperson,cn=schema,cn=config" (00000001)
added: "cn={3}misc,cn=schema,cn=config" (00000001)
added: "cn={4}nis,cn=schema,cn=config" (00000001)
added: "cn={5}virtual_mail,cn=schema,cn=config" (00000001)
added: "cn={6}published_group,cn=schema,cn=config" (00000001)
added: "olcDatabase={-1}frontend,cn=config" (00000001)
added: "olcDatabase={0}config,cn=config" (00000001)
added: "olcDatabase={1}mdb,cn=config" (00000001)
added: "olcOverlay={0}memberof,olcDatabase={1}mdb,cn=config" (00000001)
added: "olcOverlay={1}refint,olcDatabase={1}mdb,cn=config" (00000001)
added: "olcOverlay={2}unique,olcDatabase={1}mdb,cn=config" (00000001)
Closing DB...
```

Since `slapadd` runs as `root`, you must now change the ownership of everything it created to the `ldap` user and group.

```console
# chown -R ldap:ldap /usr/local/etc/openldap/slapd.d
```


## Enable and start the OpenLDAP daemon

At this point, you can enable the `slapd` service. [^2]

[^2]: As shown in [Modular system configuration on FreeBSD](freebsd-modular-system-configuration.md).

```console
# cat << EOF > /usr/local/etc/rc.conf.d/slapd
# /usr/local/etc/rc.conf.d/slapd: system configuration for slapd

slapd_enable="YES"
slapd_flags="-h \"ldapi://%2fvar%2frun%2fopenldap%2fldapi/ ldap:/// ldaps:///\""
slapd_sockets="/var/run/openldap/ldapi"
slapd_cn_config="YES"
EOF
```

Alternatively, assuming you [fetched this homelab documentation](freebsd-command-line-tools.md#fetch-configuration-files) in `/homelab-documentation`, you may enable this service by creating a simple symbolic link to the provided system configuration file.

```console
# cd /usr/local/etc/rc.conf.d
# ln -s ../../../../homelab-documentation/freebsd-server/ldap/usr/local/etc/rc.conf.d/slapd
```

Now you can start the `slapd` service.

```console
# service slapd start
```

As a quick sanity check that you can successfully manage the OpenLDAP database from a shell as root on the server, run the following command.

```console
# ldapsearch -H ldapi:/// -Y EXTERNAL -Q -b cn=config -LLL "(olcOverlay=*)" dn
```

You should see the three overlays attached to the database in the output.

```
dn: olcOverlay={0}memberof,olcDatabase={1}mdb,cn=config

dn: olcOverlay={1}refint,olcDatabase={1}mdb,cn=config

dn: olcOverlay={2}unique,olcDatabase={1}mdb,cn=config

```

At this point, you should have a functional LDAP directory server, but it’s still empty, missing essential scaffolding, as well as the useful entries you need like users and groups.


## Populate the LDAP directory

Building LDAP entries by hand is unpleasant and easy to get subtly wrong, so the `homelab-documentation` repository includes some utility scripts to create the kinds of LDAP entries commonly needed.

### Install helper LDAP scripts

Assuming you [fetched this homelab documentation](freebsd-command-line-tools.md#fetch-configuration-files) in `/homelab-documentation`, here’s how you can install these scripts.

```console
# mkdir -p /opt/local/lib
# cd /opt/local/lib
# ln -s ../../../homelab-documentation/freebsd-server/ldap/opt/local/lib/ldap_standard_utilities
# mkdir -p /opt/local/bin
# cd /opt/local/bin
# for file_name in ../../../homelab-documentation/freebsd-server/ldap/opt/local/bin/ldap_*; \
  do \
      ln -s "${file_name}"; \
  done
```

These scripts all talk to the directory over the Unix socket as the calling process, so they have to be run as `root` and never ask for a password.

### Bootstrap LDAP directory with top level and system entries

For your new LDAP directory based on the [`slapd.ldif`](ldap/usr/local/etc/openldap/slapd.ldif) file to be ready for consumption, you first need an essential bootstrap step.

```console
# ldap_create_top_level_directory_and_system_entries
```

This creates the base suffix, the system branch, the administrator whose password you can use from a graphical client, and the five capability groups.

You should see output similar to this.

```
adding new entry "o=homelab"

adding new entry "ou=system,o=homelab"

adding new entry "ou=users,ou=system,o=homelab"

adding new entry "ou=groups,ou=system,o=homelab"

adding new entry "ou=capabilities,ou=system,o=homelab"

adding new entry "cn=admin,ou=users,ou=system,o=homelab"

adding new entry "cn=service-accounts,ou=capabilities,ou=system,o=homelab"

adding new entry "cn=user-authenticators,ou=capabilities,ou=system,o=homelab"

adding new entry "cn=mail-routing-readers,ou=capabilities,ou=system,o=homelab"

adding new entry "cn=group-membership-readers,ou=capabilities,ou=system,o=homelab"

adding new entry "cn=user-profile-readers,ou=capabilities,ou=system,o=homelab"

```

From this point on, your LDAP directory has all the essential scaffolding it needs.

You can find several examples of how to add various kinds of entries to your LDAP directory in [this sample script](ldap/sample-scripts/ldap_setup_multi_domain_directory_with_sample_entries), which adds a number of entries for a two-domain setup. Nevertheless, let’s review below some key use-cases.

### Service accounts

A service account is an identity a service binds as, and the capabilities it’s given determine what data it has access to. [^3]

[^3]: You can refer to the [Access control](#access-control) section above for a more detailed overview of the available capabilities.

```console
# ldap_create_user --system --cn "my_mail_service"                  \
                   --capability "user-authenticators"               \
                   --capability "mail-routing-readers"
```

For a service running on the same machine, if it can connect to the LDAP server over the Unix socket, you can pass the `--socket-account <unix-account>` option to `ldap_create_user` instead of having to provide a password.

### Domains

Here’s an example of how you can create a domain that supports email delivery to local mailboxes.

```console
# ldap_create_domain --domain "my_domain.tld" --mailbox-domain      \
                     --essential-aliases-destination "admin"
```

The `--mailbox-domain` option indicates that this domain supports email delivery to local mailboxes. As an alternative, a domain can be created with the `--alias-domain` option, which indicates that every address must redirect elsewhere. You cannot pass both of these options for the same domain; but you can create a domain with neither of these options if mail for that domain is handled externally.

The `--essential-aliases-destination` option creates an entry answering for `postmaster`, `abuse`, `hostmaster` and `webmaster`, all forwarded to the address you name.

### People and aliases

Here’s how you can create a user with a local mailbox.

```console
# ldap_create_user --domain "my_domain.tld" --uid "john"            \
                   --given-name "John" --surname "Smith"
```

If you need an entry for an alias, but you don’t intend to authenticate into any service or application with this entry, you can use `--alias-only` with `--mail-destination`.

```console
# ldap_create_user --domain "my_domain.tld" --cn "contact"          \
                   --mail-alias "outreach"                          \
                   --mail-destination "john"                        \
                   --alias-only
```

And here’s another interesting example of an entry that does need to support authentication, but doesn’t require a local mailbox; this is suitable for a scanner, which submits mail but cannot sign into other applications on the server.

```console
# ldap_create_user --domain "my_domain.tld" --uid "scanner"         \
                   --cn "Fancy Scanner" --surname "Scanner"         \
                   --mail-destination "john"                        \
                   --authenticated-sender
```

Addresses given to `--mail`, `--mail-alias` and `--mail-destination` may be provided with a local part only; in that case, they are qualified with the entry’s own domain before being stored. The `ldap_create_user` script ensures that only fully qualified addresses are added to the LDAP directory.

### Groups

The `ldap_create_group` script can be used to create groups of two different kinds.

You can either create a group attached to a specific domain.

```console
# ldap_create_group --domain "my_domain.tld" --cn "writers"         \
                    --member "john"
```

Or you can create a system-wide group.

```console
# ldap_create_group --system --cn "my_application"                  \
          --member "uid=john,ou=users,ou=my_domain.tld,o=homelab"
```

Typically, you should only use a system-wide group for applications on the server that are available to all of the domains in the LDAP directory. This kind of group can be used to declare which users have access to a specific application on the server.

A system-wide group is not published by default, which is the desirable choice for gating access to an application.

However, you may also want to create a system-wide group that is exposed to applications on the server, such as one defining the administrators for a given application. You can create such a group by adding the `--published` option.

```console
# ldap_create_group --system --cn "my_application-admins" --published \
                    --member "uid=john,ou=users,ou=my_domain.tld,o=homelab"
```

Once a group is created, you can also add newly created users to it easily using the `ldap_create_user` script, with the `--member-of` option for a group in the new user’s own domain, or with the `--system-group` option for a system-wide group. Note that `--system-group` creates the group unpublished when it doesn’t exist yet, so a published group like the one above should be declared explicitly with `ldap_create_group` before anyone joins it.


## Confirm correct behavior

Bind as the administrator and read back what you created.

```console
# ldapsearch -H ldap://my_server.my_domain.tld -ZZ -x               \
      -D "cn=admin,ou=users,ou=system,o=homelab" -W                 \
      -b "o=homelab"                                                \
      -LLL "(objectClass=organizationalUnit)" dn
```

Then check that an ordinary user can authenticate and nothing more.

```console
# ldapsearch -H ldap://my_server.my_domain.tld -ZZ -x               \
      -D "uid=john,ou=users,ou=my_domain.tld,o=homelab" -W          \
      -b "o=homelab" -LLL "(objectClass=*)" dn
```

This command is expected to return no entries at all, despite a successful authentication. Instead, you should see output similar to this.

```
No such object (32)
```

This confirms that the bind succeeded for your user, even though the search returned nothing, which proves that the access controls we defined above are working as intended.


## Firewall configuration for OpenLDAP

For a homelab environment, you may want to open the relevant ports for OpenLDAP for traffic from any other machine in your local area network. In practice, this means opening ports 389 for `ldap://` and 636 for `ldaps://`.

Assuming you already configured `pf` as a firewall with rules for services you want to expose to your local area network, as shown in [Configuring firewall with `pf` on FreeBSD](freebsd-firewall.md#firewall-configuration-for-nfs), all you need to do is to ensure `ldap` and `ldaps` are included in the `tcp_and_udp_services_for_lan_subnet`, and reload `pf` rules.

```console
# service pf reload
```