#!/bin/bash

set -euo pipefail

## Requirement: wget/curl

## ======================== Settings =========================

declare -g LOG LOG_LTH LOG_TZ REQ_INTERVAL REQ_RETRY

## Directories of log file
LOG="${0%/*}/namesilo_ddns.log"

## Max lines of log
LOG_LTH=100

## Time zone for logging time (tip: use `tzselect`)
LOG_TZ='America/Los_Angeles'

## Interval seconds between API requests
REQ_INTERVAL=5

## Retry limit for updating-failed host before disabled
REQ_RETRY=2

## ===========================================================

declare -g IP_ADDR_V4 IP_ADDR_V6 INV_HOSTS RECORDS FUNC_RETURN
declare -g APIKEY HOSTS IGNORE_CACHE
declare -g PROJECT COPYRIGHT LICENSE HELP
PROJECT="Namesilo DDNS CLI v2.7 (2021.02.02)"
COPYRIGHT="Copyright (c) 2021 Mr.Jos"
LICENSE="MIT License: <https://opensource.org/licenses/MIT>"
HELP="Usage: namesilo_ddns.sh <command> ... [parameters ...]
Commands:
  --help                   Show this help message
  --version                Show version info
  --key, -k <apikey>       Specify Namesilo API key
  --host, -h <host>        Add a hostname
  --refetch, -r            Refetch records from Namesilo

Example:
  namesilo_ddns.sh -k c40031261ee449037a4b44b1 \\
      -h yourdomain1.tld \\
      -h subdomain1.yourdomain1.tld \\
      -h subdomain2.yourdomain2.tld

Exit codes:
    0    Successfully updating for all host(s)
    2    Exist updating failed host(s)
    9    Arguments error

Tips:
  Strongly recommand to refetch records or clear caches in log,
  if your DNS records have been updated by other ways.
"

parse_args()
{
    local RE_KEY="^[0-9a-fA-F]{16,32}$"
    local RE_HOST="^([a-zA-Z0-9\-]{1,63}\.)+[a-zA-Z0-9\-]{1,63}$"
    local RE_IPV4="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    local RE_IPV6="^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{1,4}$"
    while [[ $# -gt 0 ]]; do case "$1" in
        --help)
            echo "${PROJECT:-}"
            echo "${HELP:-}"
            exit 0
            ;;
        --version)
            echo "${PROJECT:-}"
            echo "${COPYRIGHT:-}"
            echo "${LICENSE:-}"
            exit 0
            ;;
        --key | -k)
            shift
            if [[ $1 =~ $RE_KEY ]]; then
                APIKEY="$1"
            else
                echo "Invalid API key: $1"
                exit 9
            fi
            ;;
        --host | -h)
            shift
            if [[ $1 =~ $RE_HOST ]]; then
                HOSTS+=("$1")
            else
                echo "Invalid host format: $1"
                exit 9
            fi
            ;;
        --refetch | -r )
            IGNORE_CACHE=true
            ;;
    esac; shift; done

    if [[ ! ${APIKEY:-} =~ $RE_KEY ]]; then
        echo "No valid API key"
        exit 9
    elif [[ -z ${HOSTS[@]} ]]; then
        echo "No valid host"
        exit 9
    elif [[ -z $( command -v wget ) && -z $( command -v curl ) ]]; then
        echo "Necessary requirement (wget/curl) does not exist."
        exit 9
    fi
}

load_log()
{
    ## read old log
    local LINES=() IDX=0
    local LINE CACHE HEAD_IDX HELPFUL
    [[ ! -e $LOG ]] && echo -n "" > $LOG
    while read -r LINE; do
        if [[ -z $LINE ]]; then
            continue
        elif [[ ${LINE:0:1} == "@" ]]; then
            ## parse cache
            [[ ${IGNORE_CACHE:-false} == true ]] && continue
            CACHE=$( echo -e ${LINE##*"="} )
            case $LINE in
                "@Cache[IPv4-Address]"*)
                    IP_ADDR_V4="$CACHE" ;;
                "@Cache[IPv6-Address]"*)
                    IP_ADDR_V6="$CACHE" ;;
                "@Cache[Invalid-Hosts]"*)
                    INV_HOSTS="${INV_HOSTS:-};$CACHE" ;;
                "@Cache[Record]"*)
                    RECORDS+=("$CACHE") ;;
            esac
            continue
        else
            ## omit helpless line
            IDX=$(( IDX + 1 ))
            case $LINE in
                *"address has no change"*)          ;;
                *"address is unknown"*)             ;;
                *"network communication failed"*)   ;;
                "====="*)
                    [[ ${HELPFUL:-false} != true ]] && IDX="${HEAD_IDX:-1}"
                    HEAD_IDX="$IDX"
                    HELPFUL=false
                    ;;
                *)
                    HELPFUL=true ;;
            esac
            LINES[$IDX]=$LINE
            continue
        fi
    done < $LOG

    ## rewrite old log with length control
    local START END HEAD
    END=$(( IDX ))
    START=$(( END - LOG_LTH + 1 ))
    [[ $START -le 0 ]] && START=1
    echo -n "" > $LOG
    for (( IDX = START ; IDX <= END ; IDX++ )); do
        [[ ${LINES[IDX]:-} == "====="* ]] && HEAD=true
        if [[ ${HEAD:-false} == true && -n ${LINES[IDX]:-} ]]; then
            echo ${LINES[IDX]:-} >> $LOG
        fi
    done
    HEAD=$( TZ=$LOG_TZ printf '%(%Y-%m-%d %H:%M:%S)T\n' "-1" )
    echo "========================= $HEAD ========================" >> $LOG
}

get_ip()
{
    local ARG POOL RE
    if [[ $1 == "-4" ]]; then
        POOL=(
            "http://v4.ident.me"
            "https://ip4.nnev.de"
            "https://v4.ifconfig.co"
            "https://ipv4.yunohost.org"
            "https://ipv4.icanhazip.com"
            "https://ipv4.wtfismyip.com/text"
            "https://ipv4.ipecho.roebert.eu"
        )
        RE="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    elif [[ $1 == "-6" ]]; then
        POOL=(
            "http://v6.ident.me"
            "https://ip6.nnev.de"
            "https://v6.ifconfig.co"
            "https://ipv6.yunohost.org"
            "https://ipv6.icanhazip.com"
            "https://ipv6.wtfismyip.com/text"
            "https://ipv6.ipecho.roebert.eu"
        )
        RE="^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{1,4}$"
    else
        return
    fi
    ARG="$1"

    ## get public ip from pool in random order
    local RES IDX IDX_RAN VAR
    for (( IDX = ${#POOL[@]} - 1; IDX >= 0; IDX--  )); do
        IDX_RAN=$(( $RANDOM % (IDX + 1) ))
        VAR="${POOL[IDX]}"
        POOL[$IDX]="${POOL[IDX_RAN]}"
        POOL[$IDX_RAN]="$VAR"
        set +e
        if [[ -n $( command -v wget ) ]]; then
            RES=$( wget -qO-  -t 1   -T 5 $ARG ${POOL[IDX]} )
        elif [[ -n $( command -v curl ) ]]; then
            RES=$( curl -s --retry 0 -m 5 $ARG ${POOL[IDX]} )
        fi
        set -e
        if [[ $RES =~ $RE ]]; then
            break
        else
            RES="NULL"
        fi
    done

    if [[ ${RES:-NULL} == "NULL" ]]; then
        ## if ip-getting failed, cached ip will be applicated
        return
    elif [[ $ARG == "-4" && $RES != ${IP_ADDR_V4:-NULL} ]]; then
        echo "IPv4 address changed to [$RES]" >> $LOG
        IP_ADDR_V4="$RES"
    elif [[ $ARG == "-6" && $RES != ${IP_ADDR_V6:-NULL} ]]; then
        echo "IPv6 address changed to [$RES]" >> $LOG
        IP_ADDR_V6="$RES"
    fi
}

fetch_records()
{
    FUNC_RETURN=""
    local DOMAIN="$1"

    ## fetch records list request
    ## https://www.namesilo.com/api-reference#dns/dns-list-records
    local REQ RES
    REQ="https://www.namesilo.com/api/dnsListRecords"
    REQ="$REQ?version=1&type=xml&key=$APIKEY&domain=$DOMAIN"
    set +e
    read -rt ${REQ_INTERVAL:=0} <> <(:) || :
    if [[ -n $( command -v wget ) ]]; then
        RES=$( wget -qO-  -t 2   -T 20 $REQ )
    elif [[ -n $( command -v curl ) ]]; then
        RES=$( curl -s --retry 1 -m 20 $REQ )
    fi
    set -e

    ## parse list response
    local ID TYPE HOST VALUE TTL FAIL
    local CODE DETAIL FETCHED=()
    local TAG TEXT XPATH="" IFS=\>
    while read -d \< TAG TEXT; do
        if [[ ${TAG:0:1} == "?" ]]; then     ## xml declare
            continue
        elif [[ ${TAG:0:1} == "/" ]]; then   ## node end
            if [[ $XPATH == "//namesilo/reply/resource_record" ]]; then
                FETCHED+=("${ID:-}|${TYPE:-}|${HOST:-}|${VALUE:-}|${TTL:-}|${FAIL:-0}")
                unset ID TYPE HOST VALUE TTL FAIL
            fi
            XPATH=${XPATH%$TAG}
        else                                 ## node start
            XPATH="$XPATH/$TAG"
            case $XPATH in
                "//namesilo/reply/code")
                    CODE=$TEXT ;;
                "//namesilo/reply/detail")
                    DETAIL=$TEXT ;;
                "//namesilo/reply/resource_record/record_id")
                    ID=$TEXT ;;
                "//namesilo/reply/resource_record/type")
                    TYPE=$TEXT ;;
                "//namesilo/reply/resource_record/host")
                    HOST=$TEXT ;;
                "//namesilo/reply/resource_record/value")
                    VALUE=$TEXT ;;
                "//namesilo/reply/resource_record/ttl")
                    TTL=$TEXT ;;
            esac
        fi
    done <<< "$RES"
    RECORDS+=(${FETCHED[@]:-})
    [[ ${CODE:=000} -eq 000 ]] && DETAIL="network communication failed"

    ## result
    echo "Fetch ${#FETCHED[@]} record(s) of [$DOMAIN]: ($CODE) ${DETAIL:-}" >> $LOG
    if [[ $CODE -eq 000 ]]; then
        FUNC_RETURN="UNFETCHED#ERROR#"
    else
        FUNC_RETURN="FETCHED"
    fi
}

update_record()
{
    FUNC_RETURN=""
    ## parse record info
    local ID TYPE HOST VALUE TTL FAIL
    local DOMAIN SUBDOMAIN VAR
    VAR=(${1//|/ })
    ID=${VAR[0]:-}
    TYPE=${VAR[1]:-}
    HOST=${VAR[2]:-}
    VALUE=${VAR[3]:-NULL}
    TTL=${VAR[4]:-}
    FAIL=${VAR[5]:-0}
    VAR=(${HOST//./ })
    if [[ ${#VAR[@]} -le 2 ]]; then
        DOMAIN="$HOST"
        SUBDOMAIN=""
    else
        DOMAIN="${VAR[-2]}.${VAR[-1]}"
        SUBDOMAIN="${HOST%.$DOMAIN}"
    fi

    ## update check
    local IP_ADDR CHECK
    if [[ ! $ID =~ ^[0-9a-fA-F]{32}$ ]]; then
        CHECK="Format of record ID [$ID] is invalid"
        FAIL=$(( FAIL + 1 ))
    elif [[ $TYPE == "A" ]]; then
        IP_ADDR=${IP_ADDR_V4:-NULL}
        [[ $IP_ADDR == $VALUE ]] && CHECK="IPv4 address has no change"
        [[ $IP_ADDR == "NULL" ]] && CHECK="IPv4 address is unknown"
    elif [[ $TYPE == "AAAA" ]]; then
        IP_ADDR=${IP_ADDR_V6:-NULL}
        [[ $IP_ADDR == $VALUE ]] && CHECK="IPv6 address has no change"
        [[ $IP_ADDR == "NULL" ]] && CHECK="IPv6 address is unknown"
    else
        CHECK="Record type [$TYPE] is not supported"
        FAIL=$(( FAIL + 1 ))
    fi
    if [[ -n ${CHECK:-} ]]; then
        echo "Update record [$TYPE//$HOST//${ID:0:4}]: $CHECK" >> $LOG
        FUNC_RETURN="$ID|$TYPE|$HOST|$VALUE|$TTL|$FAIL"
        if [[ -z ${IP_ADDR:-} ]]; then
            FUNC_RETURN="$FUNC_RETURN#ERROR#"
        fi
        return
    fi

    ## update record request
    ## https://www.namesilo.com/api-reference#dns/dns-update-record
    local REQ RES
    REQ="https://www.namesilo.com/api/dnsUpdateRecord"
    REQ="$REQ?version=1&type=xml&key=$APIKEY&domain=$DOMAIN"
    REQ="$REQ&rrid=$ID&rrhost=$SUBDOMAIN&rrvalue=$IP_ADDR&rrttl=${TTL:=3600}"
    set +e
    read -rt ${REQ_INTERVAL:=0} <> <(:) || :
    if [[ -n $( command -v wget ) ]]; then
        RES=$( wget -qO-  -t 2   -T 10 $REQ )
    elif [[ -n $( command -v curl ) ]]; then
        RES=$( curl -s --retry 1 -m 10 $REQ )
    fi
    set -e
    
    ## parse result response
    local CODE DETAIL NEW_ID=""
    local TAG TEXT XPATH="" IFS=\>
    while read -d \< TAG TEXT; do
        if [[ ${TAG:0:1} == "?" ]]; then     ## xml declare
            continue
        elif [[ ${TAG:0:1} == "/" ]]; then   ## node end
            XPATH=${XPATH%$TAG}
        else                                 ## node start
            XPATH="${XPATH}/${TAG}"
            case ${XPATH} in
                "//namesilo/reply/code")
                    CODE=$TEXT ;;
                "//namesilo/reply/detail")
                    DETAIL=$TEXT ;;
                "//namesilo/reply/record_id")
                    NEW_ID=$TEXT ;;
            esac
        fi
    done <<< "$RES"
    [[ ${CODE:=000} -eq 000 ]] && DETAIL="network communication failed"

    ## result
    [[ ${CODE:=000} -eq 300 ]] && DETAIL="$DETAIL [${ID:0:4}=>${NEW_ID:0:4}]"
    echo "Update record [$TYPE//$HOST//${ID:0:4}]: ($CODE) ${DETAIL:-}" >> $LOG
    if [[ $CODE -eq 300 ]]; then
        ID="$NEW_ID"
        VALUE="$IP_ADDR"
        FAIL=0
    else
        FAIL=$(( FAIL + 1 ))
    fi
    FUNC_RETURN="$ID|$TYPE|$HOST|$VALUE|$TTL|$FAIL"
    if [[ $CODE -ne 300 ]]; then
        FUNC_RETURN="$FUNC_RETURN#ERROR#"
    fi
}

main()
{
    ## preparations
    load_log
    get_ip -4
    get_ip -6
    
    ## initialize host status dictionary
    declare -A STATUS
    local HOST DOMAIN RECORD VAR FAIL ID CHECKED
    local SUCCESS=true
    for HOST in "${HOSTS[@]:-}"; do
        [[ -z $HOST ]] && continue
        VAR=(${HOST//./ })
        [[ ${#VAR[@]} -lt 2 ]] && continue
        if [[ ";${INV_HOSTS:-};" == *";$HOST;"* ]]; then
            STATUS[$HOST]="<disabled>"
        else
            STATUS[$HOST]="<init>"
        fi
    done

    ## check records from log and discard invalid ones
    CHECKED=()
    for RECORD in "${RECORDS[@]:-}"; do
        [[ -z $RECORD ]] && continue
        VAR=(${RECORD//|/ })
        HOST=${VAR[2]:-}
        FAIL=${VAR[5]:-0}
        if [[ -z $HOST || -z ${STATUS[$HOST]:-} ]]; then
            continue    ## no fitting host
        elif [[ ${STATUS[$HOST]} == "<disabled>" ]]; then
            continue    ## the host has been disabled
        elif [[ $FAIL -gt $REQ_RETRY ]]; then
            ## the record has too many failed requests
            STATUS[$HOST]="<suspended>"
            continue
        elif [[ ${STATUS[$HOST]} == "<init>" ]]; then
            STATUS[$HOST]="<matched>"
        fi
        CHECKED+=("$RECORD")
    done
    RECORDS=(${CHECKED[@]:-})

    ## fetch record info for hosts with issues
    local FETCHED_DOMAIN=""
    for HOST in "${!STATUS[@]}"; do
        [[ ${STATUS[$HOST]} == "<disabled>" ]] && continue
        [[ ${STATUS[$HOST]} == "<matched>" ]] && continue
        VAR=(${HOST//./ })
        DOMAIN="${VAR[-2]}.${VAR[-1]}"
        if [[ "|$FETCHED_DOMAIN|" != *"|$DOMAIN|"* ]]; then
            fetch_records $DOMAIN
            if [[ -z $FUNC_RETURN ]]; then
                SUCCESS=false
            elif [[ $FUNC_RETURN == *"#ERROR#"* ]]; then
                SUCCESS=false
            else
                FETCHED_DOMAIN="$FETCHED_DOMAIN|$DOMAIN"
            fi
        fi
        STATUS[$HOST]="<init>"
    done

    ## update ip for valid records
    CHECKED=()
    for RECORD in "${RECORDS[@]:-}"; do
        [[ -z $RECORD ]] && continue
        VAR=(${RECORD//|/ })
        ID=${VAR[0]:-}
        HOST=${VAR[2]:-}
        if [[ -z $ID || " ${CHECKED[@]:-}" == *" $ID|"* ]]; then
            continue    ## duplicated record
        elif [[ -z $HOST || -z ${STATUS[$HOST]:-} ]]; then
            continue    ## no fitting host
        elif [[ ${STATUS[$HOST]} == "<disabled>" ]]; then
            continue    ## the host has been disabled
        fi
        update_record $RECORD
        if [[ -z $FUNC_RETURN ]]; then
            SUCCESS=false
            continue
        elif [[ $FUNC_RETURN == *"#ERROR#"* ]]; then
            SUCCESS=false
            FUNC_RETURN=${FUNC_RETURN//"#ERROR#"/}
        fi
        CHECKED+=("$FUNC_RETURN")
        STATUS[$HOST]="<matched>"
    done
    RECORDS=(${CHECKED[@]:-})

    ## collect invalid hosts
    INV_HOSTS=""
    for HOST in "${!STATUS[@]}"; do
        [[ ${STATUS[$HOST]} == "<matched>" ]] && continue
        VAR=(${HOST//./ })
        DOMAIN="${VAR[-2]}.${VAR[-1]}"
        if [[ ${STATUS[$HOST]} == "<disabled>" ]]; then
            INV_HOSTS="$INV_HOSTS;$HOST"
        elif [[ "|$FETCHED_DOMAIN|" == *"|$DOMAIN|"* ]]; then
            STATUS[$HOST]="<disabled>"
            INV_HOSTS="$INV_HOSTS;$HOST"
        fi
    done
    [[ -n $INV_HOSTS ]] && SUCCESS=false

    ## write cache for next running
    echo "@Cache[IPv4-Address]=${IP_ADDR_V4:-NULL}" >> $LOG
    echo "@Cache[IPv6-Address]=${IP_ADDR_V6:-NULL}" >> $LOG
    if [[ -n ${INV_HOSTS:-} ]]; then
        echo "@Cache[Invalid-Hosts]=${INV_HOSTS#;}" >> $LOG
    fi
    for RECORD in "${RECORDS[@]:-}"; do
        [[ -n $RECORD ]] && echo "@Cache[Record]=$RECORD" >> $LOG
    done

    ## exit with running status
    if [[ $SUCCESS == true ]]; then
        exit 0
    else
        exit 2
    fi
}

parse_args $*
main
