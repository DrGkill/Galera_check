Galera check utility for ensuring Consistency and Availability OR Consistency and Partition tolerence
=====================================================================================================

Table of contents
=================

  * [Introduction] (#intro)
  * [Installation] (#installation)
  * [Config options] (#config-options)


Introduction
============

This project gives the ability to ensure failover on a Galera cluster. It helps to chose which node
will answer queries regarding your policy (availability or partitionning tolerence).
As you may know, in distributed system, you cannot ensure consistency, availability and partition
tolerence at the same time. (http://galeracluster.com/documentation-webpages/recovery.html)
Galera concentrate on consistency and can add availability OR partitioning tolerence. This script will
 allow you to chose either availability or partition tolerence.

This system aims to be lightweight, robust and lightning fast. It takes only 1ms for the script to take a decision.


Haproxy get the check result within a millisecond:
```
L7OK/200 in 1ms
```


Installation
============

First install nginx with embedded perl support on your Galera nodes:

```
apt-get update && apt-get install nginx-extras libnginx-mod-http-perl
```

Copy configs and library inside the nginx config dir:

```
cp nginx.config /etc/nginx/sites-available/galeracheck
cd /etc/nginx/sites-enabled && ln -s ../sites-available/galeracheck
```

reload nginx:
```
service nginx restart
```

Config Options
==============

All options has to be set inside nginx config file.
Options are :

```
    ghost : IP address or domain name where mysql node answer
    gport : TCP port  where mysql node answer
    guser : User to connect the mysql node
    gpass : Password to connect the mysql node
    gmode : CA = Consistency and Availability
            CP = Consistency and Partition tolerance
```

Nginx config example :

```
perl_modules /etc/nginx/perl/lib;
perl_require galera.pm;
variables_hash_max_size 2048;
variables_hash_bucket_size 128;

server {
    listen 80 default_server;
    listen [::]:80 default_server;

    location / {
        access_log off;
        set $ghost "localhost";
        set $gport "3306";
        set $guser "wsrep_sst_user";
        set $gpass "wsrep_sst_password";
        set $gmode "CA";
        perl galera::handler;
    }
}
```

Haproxy can then be configured like so:

```
frontend bdd1-front
    bind 127.0.0.1:3306
    mode tcp
    option tcplog
    option tcpka
    default_backend bdd1-back


backend bdd1-back
    mode tcp
    balance leastconn
    option httpchk /
    http-check expect status 200
    server bdd1  172.18.10.1:3306 check port 80 inter 500 rise 3 fall 3
    server bdd2  172.18.10.2:3306 check port 80 inter 500 rise 3 fall 3 backup
    server bdd3  172.18.10.3:3306 check port 80 inter 500 rise 3 fall 3 backup
```
