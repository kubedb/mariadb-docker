#!/usr/bin/env bash

# Environment variables passed from Pod env are as follows:
#   CLUSTER_NAME = name of the mariadb cr
#   MYSQL_ROOT_USERNAME = root user name of the mariadb database server
#   MYSQL_ROOT_PASSWORD = root password of the mariadb database server

script_name=${0##*/}

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

# get the host names from stdin sent by peer-finder program
cur_hostname=$(hostname)

export cur_host=
log "INFO" "Reading standard input..."
while read -ra line; do
    if [[ "${line}" == *"${cur_hostname}"* ]]; then
        cur_host=$(echo -n ${line%.svc*})
    fi
    tmp=$(echo -n ${line%.svc*})
    peers=("${peers[@]}" "$tmp")

done

log "INFO" "Trying to start group with peers'${peers[*]}'"

# comma separated host names
export hosts=$(echo -n ${peers[*]} | sed -e "s/ /,/g")
myips=$(hostname -I)
first=${myips%% *}

# write on galera configuration file
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
    # Starting with provider version 3.19, Galera has an additional protection against attempting to boostrap the cluster using a node
    # that may not have been the last node remaining in the cluster prior to cluster shutdown.
    # ref: https://galeracluster.com/library/training/tutorials/restarting-cluster.html#restarting-the-cluster
    sed -i -e 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/g' /var/lib/mysql/grastate.dat
    log "INFO" "Creating new cluster using --wsrep-new-cluster"
    docker-entrypoint.sh mysqld --wsrep-new-cluster $@ &
    # saving the process id running in background for further process...
    pid=$!
else
    # DATABASE_ALREADY_EXISTS=true skips database initialization for newly added nodes in cluster.
    export DATABASE_ALREADY_EXISTS=true

    log "INFO" "Adding new node ***'$cur_host'*** to the cluster"
    docker-entrypoint.sh mysqld $@ &
    # saving the process id running in background for further process...
    pid=$!
fi

args=$@
# wait for all mysql servers be running (alive)
for host in ${peers[*]}; do
    for i in {900..0}; do
        tlsCred=""
        if [[ "$args" == *"--require-secure-transport"* ]]; then
            tlsCred="--ssl-ca=/etc/mysql/certs/client/ca.crt  --ssl-cert=/etc/mysql/certs/client/tls.crt --ssl-key=/etc/mysql/certs/client/tls.key"
        fi
        out=$(mysql -u${MYSQL_ROOT_USERNAME} -p${MYSQL_ROOT_PASSWORD} --host=${host} ${tlsCred} -N -e "select 1;" 2>/dev/null)
        log "INFO" "Trying to ping ***'$host'***, Step='$i', Got='$out'"
        if [[ "$out" == "1" ]]; then
            break
        fi
        echo -n .
        sleep 1
    done
    if [[ "$i" == "0" ]]; then
        echo ""
        log "ERROR" "Failed to start the Server = ${host} ..."
        exit 1
    fi
done

log "INFO" "All servers are ready -> (${peers[*]})"

# wait for mysqld process running in background
log "INFO" "SUCCESS: mysqld process [pid = '$pid'] running in background ..."

wait $pid
