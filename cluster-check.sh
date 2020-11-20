#!/bin/bash

# This script is used as the readiness probe for percona-xtradb pod
# that checks the cluster statuses, if any of the checks fails then
# this script exits with status code 1.

function check_property() {
    IFS='|' read -ra expected <<< "$2"
    local match=0
    for e in ${expected[*]}; do
        if [[ "$3" == "$e" ]]; then
            match=1
            break
        fi
    done
    if [[ "$match" -eq 0 ]]; then
        echo "[Error] Not match $1. Expected $2, got $3"
        exit 1
    fi
}

READ_ONLY=$(mysql -uroot -p${MYSQL_ROOT_PASSWORD} -Ne "select 1;" | awk '{print $1}')
EXPECTED_READ_ONLY="1"
check_property "select 1" $EXPECTED_READ_ONLY $READ_ONLY

# TODO: Check why 2 or 4 in wsrep_local_state
WSREP_LOCAL_STATE=$(mysql -uroot -p${MYSQL_ROOT_PASSWORD}  -Ne "show status like 'wsrep_local_state';" | awk '{print $2}')
EXPECTED_WSREP_LOCAL_STATE="2|4"
check_property "wsrep_local_state" $EXPECTED_WSREP_LOCAL_STATE $WSREP_LOCAL_STATE

WSREP_EVS_STATE=$(mysql -uroot -p${MYSQL_ROOT_PASSWORD}  -Ne "show status like 'wsrep_evs_state';" | awk '{print $2}')
EXPECTED_WSREP_EVS_STATE="OPERATIONAL"
check_property "wsrep_evs_state" $EXPECTED_WSREP_EVS_STATE $WSREP_EVS_STATE

WSREP_CLUSTER_STATUS=$(mysql -uroot -p${MYSQL_ROOT_PASSWORD}  -Ne "show status like 'wsrep_cluster_status';" | awk '{print $2}')
EXPECTED_WSREP_CLUSTER_STATUS="Primary"
check_property "wsrep_cluster_status" $EXPECTED_WSREP_CLUSTER_STATUS $WSREP_CLUSTER_STATUS


WSREP_CONNECTED=$(mysql -uroot -p${MYSQL_ROOT_PASSWORD}  -Ne "show status like 'wsrep_connected';" | awk '{print $2}')
EXPECTED_WSREP_CONNECTED="ON"
check_property "wsrep_connected" $EXPECTED_WSREP_CONNECTED $WSREP_CONNECTED

WSREP_READY=$(mysql -uroot -p${MYSQL_ROOT_PASSWORD}  -Ne "show status like 'wsrep_ready';" | awk '{print $2}')
EXPECTED_WSREP_READY="ON"
check_property "wsrep_ready" $EXPECTED_WSREP_READY $WSREP_READY
