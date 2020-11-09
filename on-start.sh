#!/usr/bin/env bash

#set -eoux pipefail

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
NAMESPACE="$POD_NAMESPACE"
USER="$MYSQL_ROOT_USERNAME"
PASSWORD="$MYSQL_ROOT_PASSWORD"

function timestamp() {
  date +"%Y/%m/%d %T"
}

function log() {
  local log_type="$1"
  local msg="$2"
  echo "$(timestamp) [$script_name] [$log_type] $msg"
}


# get the host names from stdin sent by peer-finder program
cur_hostname=$(hostname)
export cur_host=
log "INFO" "Reading standard input..."
while read -ra line; do
  if [[ "${line}" == *"${cur_hostname}"* ]]; then
    cur_host="$line"
    log "INFO" "I am $cur_host"
    continue
  fi
  peers=("${peers[@]}" "$line")
done


log "INFO" "Trying to start cluster with peers'${peers[*]}'"




# CLUSTER_JOIN contains the host name to which the $cur_host will join to form a cluster
# If CLUSTER_JOIN is empty then a new cluster will be bootstrapped
export CLUSTER_JOIN=${peers[0]}
if [[ -n "${CLUSTER_JOIN}" ]]; then
  # wait for the server ${CLUSTER_JOIN} be running (alive)
  log "INFO" "Waiting for the server ${CLUSTER_JOIN} be running..."
  for i in {900..0}; do
    out=$(mysqladmin -u ${USER} --password=${PASSWORD} --host=${CLUSTER_JOIN} ping 2>/dev/null)
    if [[ "$out" == "mysqld is alive" ]]; then
      break
    fi

    echo -n .
    sleep 1
  done

  echo ""
  if [[ "$i" == "0" ]]; then
    log "ERROR" "Server ${CLUSTER_JOIN} start failed..."
    exit 1
  fi

  log "INFO" "Server ${CLUSTER_JOIN} has been started"
fi

log "INFO" "Starting myself(${cur_host}) with '/entrypoint.sh $@'..."
/entrypoint.sh "$@"