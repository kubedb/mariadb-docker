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
        cur_host=$(echo -n ${line} | sed -e "s/.svc.cluster.local//g")
    fi
    tmp=$(echo -n ${line} | sed -e "s/.svc.cluster.local//g")
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
    log "INFO" "Creating new cluster using --wsrep-new-cluster"
    docker-entrypoint.sh  mysqld --wsrep-new-cluster &
    # saving the process id running in background for further process...
    pid=$!
else
    # DATABASE_ALREADY_EXISTS=true skips database initialization for newly added nodes in cluster.
    export DATABASE_ALREADY_EXISTS=true

    log "INFO" "Adding new node ***'$cur_host'*** to the cluster"
    docker-entrypoint.sh mysqld &
    # saving the process id running in background for further process...
    pid=$!
fi



# wait for all mysql servers be running (alive)
for host in ${peers[*]}; do
    for i in {900..0}; do
        out=$(mysql -u${MYSQL_ROOT_USERNAME} -p${MYSQL_ROOT_PASSWORD} --host=${host} -N -e "select 1;" 2>/dev/null)
        log "INFO" "=======trying to ping ***'$host'***, Step='$i', Got='$out'"
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
