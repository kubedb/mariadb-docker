#!/usr/bin/env bash

#set -eo pipefail
#$set -x

# Environment variables passed from Pod env are as follows:
#
#   GROUP_NAME          = a uuid treated as the name of the replication group
#   BASE_NAME           = name of the StatefulSet (same as the name of CRD)
#   BASE_SERVER_ID      = server-id of the primary member
#   GOV_SVC             = the name of the governing service
#   POD_NAMESPACE       = the Pods' namespace
#   MYSQL_ROOT_USERNAME = root user name
#   MYSQL_ROOT_PASSWORD = root password

script_name=${0##*/}
USER="$MYSQL_ROOT_USERNAME"
PASSWORD="$MYSQL_ROOT_PASSWORD"

function timestamp() {
    date +"%Y/%m/%d %T"
}

function log() {
    local type="$1"
    local msg="$2"
    echo "$(timestamp) [$script_name] [$type] $msg"
}

if [ -z "$CLUSTER_NAME" ]; then
  echo >&2 'Error:  You need to specify CLUSTER_NAME'
  exit 1
fi

echo "<--------The cluster name is '$CLUSTER_NAME'-------------->"

# get_host_name() expects only one argument and that is the index of the Pod of StatefulSet.
# And it forms the FQDN (Fully Qualified Domain Name) of the $1'th Pod of StatefulSet.
function get_host_name() {
    #  echo -n "$BASE_NAME-$1.$GOV_SVC.$NAMESPACE.svc.cluster.local"
    echo -n "$BASE_NAME-$1.$GOV_SVC.$NAMESPACE"
}

# get the host names from stdin sent by peer-finder program
cur_hostname=$(hostname)
echo "<--------The current host name is '$cur_hostname'-------------->"

export cur_host=
log "INFO" "Reading standard input..."
while read -ra line; do
    if [[ "${line}" == *"${cur_hostname}"* ]]; then
        #    cur_host="$line"
        cur_host=$(echo -n ${line} | sed -e "s/.svc.cluster.local//g")
        log "INFO" "I am $cur_host"
    fi
    #  peers=("${peers[@]}" "$line")
    tmp=$(echo -n ${line} | sed -e "s/.svc.cluster.local//g")
    peers=("${peers[@]}" "$tmp")

done
log "INFO" "Trying to start group with peers'${peers[*]}'"

# store the value for the variables those will be written in /etc/mysql/my.cnf file

# comma separated host names
export hosts=$(echo -n ${peers[*]} | sed -e "s/ /,/g")
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
wsrep_cluster_address="gcomm://${hosts}"

# Galera Synchronization Configuration
wsrep_node_address=${first}
wsrep_sst_method=rsync
EOL

host_len=${#peers[@]}

if [[ $host_len -eq 1 ]]; then
    log "INFO" "Creating --wsrep-new-cluster"
    docker-entrypoint.sh  mysqld --wsrep-new-cluster &
    pid=$!
    # run the mysqld in background
else
    export DATABASE_ALREADY_EXISTS=true
    log "INFO" "Adding '$cur_host' to the cluster"
    docker-entrypoint.sh mysqld &
    pid=$!
    # run the mysqld in background
fi

#saving the process id running in background
log "INFO" "The process id of mysqld is '$pid'"

# wait for all mysql servers be running (alive)
for host in ${peers[*]}; do
    for i in {900..0}; do
#        out=$(mysql -N -e "select 1;" 2>/dev/null)
        out=$(mysql -u${MYSQL_ROOT_USERNAME} -p${MYSQL_ROOT_PASSWORD} --host=${host} -N -e "select 1;" 2>/dev/null)
        log "INFO" "<--trying to ping '$host', Step='$i', '$out'-->"
        if [[ "$out" == "1" ]]; then
            break
        fi

        echo -n .
        sleep 1
    done
    if [[ "$i" == "0" ]]; then
        echo ""
        log "ERROR" "Server ${host} start failed..."
        exit 1
    fi
done

log "INFO" "All servers (${peers[*]}) are ready"


# wait for mysqld process running in background
log "INFO" "Waiting for mysqld server process running '$pid'..."

wait $pid

echo "PID PASSED................................."


