###############################################################################
# Script Description : Galera check system made to be used in conjunction 
#                      with Haproxy. 
#                      See Readme file for config examples.
#                        
# Author:   Guillaume Seigneuret
# Date:     17/01/2017
# Version:  1.0
#
# Usage : Library made to be included inside Nginx
#
# Utilisation:
#
# Nginx config : 
# perl_modules /etc/nginx/perl/lib;
# perl_require galera.pm;
#
# server {
#     listen 80 default_server;
#     listen [::]:80 default_server;
#
#     location / {
#         access_log off;
#         set $guser "wsrep_sst_user";
#         set $gpass "wsrep_sst_password";
#         set $ghost "localhost";
#         set $gport "3306";
#         set $gmode "CA";
#         perl galera::handler;
#     }
# }
#
# Options :
#   ghost : IP address or domain name where mysql node answer
#   gport : TCP port  where mysql node answer
#   guser : User to connect the mysql node
#   gpass : Password to connect the mysql node
#   gmode : CA = Consistency and Availability
#           CP = Consistency and Partition tolerance
#
#   It refers to the CAP theorem (https://en.wikipedia.org/wiki/CAP_theorem)
#   that say in a distributed data store, it's impossible to simultaneously
#   provide more than two out of the following three guarantees:
#       - Consistency
#       - Availability
#       - Parition tolerance
#
#   CLUSTER AVAILABILITY VS. PARTITION TOLERANCE:
#
#  Within the CAP theorem, Galera Cluster emphasizes data safety 
#  and consistency. This leads to a trade-off between cluster 
#  availability and partition tolerance. That is, when using unstable 
#  networks, such as WAN, low evs.suspect_timeout and 
#  evs.inactive_timeout values may result in false node failure 
#  detections, while higher values on these parameters may result in 
#  longer availability outages in the event of actual node failures.
#  Essentially what this means is that the evs.suspect_timeout 
#  parameter defines the minimum time needed to detect a failed node. 
#  During this period, the cluster is unavailable due to the 
#  consistency constraint.
#  (http://galeracluster.com/documentation-webpages/recovery.html)
#
# ####################################################################
# GPL v3
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# ####################################################################



package galera;

use warnings;
use strict;
use nginx;
use DBI;
use Data::Dumper;

sub handler {
    my $r = shift;

    my %ds;

    my ($host,$port);

    if (defined($r->variable('ghost'))) {
        $host = $r->variable('ghost');
    } else {
        $host = "localhost";
    }

    if (defined($r->variable('gport'))) {
        $port = $r->variable('gport');
    } else {
        $port = "3306";
    }
    
    return HTTP_SERVICE_UNAVAILABLE if not defined($r->variable('guser'));
    return HTTP_SERVICE_UNAVAILABLE if not defined($r->variable('gpass'));

    my $dbh = DBI->connect("DBI:mysql:database=mysql;host=$host;port=$port",
                        $r->variable('guser'), $r->variable('gpass'))
        or return HTTP_SERVER_ERROR;


    my $sth = $dbh->prepare("SHOW GLOBAL STATUS LIKE 'wsrep%'");
    $sth->execute();

    while (my $ref = $sth->fetchrow_hashref()) {
        my $var = $ref->{'Variable_name'};
        $ds{$var} = $ref->{'Value'};
    }
    $sth->finish();

    # Disconnect from the database.
    $dbh->disconnect();

    $ds{'wsrep_ready'}               = "NA" if not defined($ds{'wsrep_ready'});
    $ds{'wsrep_connected'}           = "NA" if not defined($ds{'wsrep_connected'});
    $ds{'wsrep_evs_state'}           = "NA" if not defined($ds{'wsrep_evs_state'});
    $ds{'wsrep_cluster_size'}        = "NA" if not defined($ds{'wsrep_cluster_size'});
    $ds{'wsrep_local_state_comment'} = "NA" if not defined($ds{'wsrep_local_state_comment'});


    if ($r->header_in('Accept') eq 'application/json') {
        $r->send_http_header("application/json");
        $r->print(sprintf("{ 'cluster_size': '%s', 'ready': '%s', 'connection_status': '%s', 'evs_state': '%s', 'local_state': '%s' }\r\n",
            $ds{'wsrep_cluster_size'}, 
            $ds{'wsrep_ready'},
            $ds{'wsrep_connected'},
            $ds{'wsrep_evs_state'},
            $ds{'wsrep_local_state_comment'}));
    } else {
        $r->send_http_header("text/plain");
        $r->print(sprintf("%-15s: %s\r\n", 'Ready',        $ds{'wsrep_ready'}));
        $r->print(sprintf("%-15s: %s\r\n", 'Connected',    $ds{'wsrep_connected'}));
        $r->print(sprintf("%-15s: %s\r\n", 'EVS State',    $ds{'wsrep_evs_state'}));
        $r->print(sprintf("%-15s: %s\r\n", 'Cluster size', $ds{'wsrep_cluster_size'}));
        $r->print(sprintf("%-15s: %s\r\n", 'Local State',  $ds{'wsrep_local_state_comment'}));
    }

    if ($r->variable('gmode') eq "CP") {
        # Node are partitioned and if client can reach us,
        # we are the right candidate (still need to be synced)
        return OK if int($ds{'wsrep_cluster_size'}) == 1 
            and $ds{'wsrep_local_state_comment'} eq "Synced";
    }

    if ($r->variable('gmode') eq "CA") {
        return OK if int($ds{'wsrep_cluster_size'}) >= 1
            and $ds{'wsrep_evs_state'} eq "OPERATIONAL";
    }

    return HTTP_SERVER_ERROR if $ds{'wsrep_ready'}               ne "ON";
    return HTTP_SERVER_ERROR if $ds{'wsrep_connected'}           ne "ON";
    return HTTP_SERVER_ERROR if $ds{'wsrep_evs_state'}           ne "OPERATIONAL";
    return HTTP_SERVER_ERROR if $ds{'wsrep_local_state_comment'} ne "Synced";
    return HTTP_SERVER_ERROR if $ds{'wsrep_cluster_status'}      ne "Primary";

    return OK;
}

1;
__END__


