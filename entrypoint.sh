#!/bin/bash
set -e

PASSWORD="$MYSQL_ROOT_PASSWORD"

# if command starts with an option, prepend mysqld
if [ "${1:0:1}" = '-' ]; then
  CMDARG="$@"
fi

if [ -z "$CLUSTER_NAME" ]; then
  echo >&2 'Error:  You need to specify CLUSTER_NAME'
  exit 1
fi

myips=$(hostname -I)
first=${myips%% *}



cat >>/etc/mysql/conf.d/galera.cnf <<EOL
[mysqld]
binlog_format=ROW
default-storage-engine=innodb
innodb_autoinc_lock_mode=2
bind-address=0.0.0.0

# Galera Provider Configuration
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so

# Galera Cluster Configuration, Add the list of peers in wrsep_cluster_address
wsrep_cluster_name=$CLUSTER_NAME
wsrep_cluster_address="gcomm://${cur_host}"

# Galera Synchronization Configuration
wsrep_node_address=${first}
wsrep_sst_method=rsync
EOL


# if we have CLUSTER_JOIN - then we do not need to perform datadir initialize
# the data will be copied from another node

if [ -z "$CLUSTER_JOIN" ]; then
    echo "................................... Beg"
    docker-entrypoint.sh  mysqld --wsrep-new-cluster
    echo "................................... End"
fi



