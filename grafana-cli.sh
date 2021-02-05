#!/bin/bash
# ------------------------------------------------------------------
# Author: Omar Rojina (omar.rojina@wizeline.com)
# Description:  This script can execute actions using the Grafana
#               API such as:
#                 - List alerts
# ------------------------------------------------------------------

usage () {
    echo "Usage: 
        $0 [-h] [config [command] | resource [action] [args]]

          Examples:
                |-------------------------------------------------------------|--------------------------------------------------------|
                |           COMMAND                                           |                   DESCRIPTION                          |
                |-------------------------------------------------------------|--------------------------------------------------------|
                |  $0 -h                                        | Prints this message                                    |
                |  $0 alerts                                    | Prints the list of alerts in the current environment   |
                |----------------------------------------------------------------------------------------------------------------------|

                NOTE: This script requires jq to be installed (https://stedolan.github.io/jq/download/)
                "
}

getStatusCode () {
    local statusCode=$(curl --write-out %{http_code} --output /dev/null -ksH "$GF_AUTH_HEADER" $GF_API_URL/org)
    echo $statusCode
}

getAlerts () {
    statusCode=$(getStatusCode)
    

    if [ $statusCode -eq 200 ]; then
        curl -ksH "$GF_AUTH_HEADER" $GF_API_URL/alerts/ | jq -r '.[] | select(.state | test("no_data|paused|alerting|pending|ok|unknown")) | [.id,.state,.dashboardSlug,.name] | @csv ' | awk -v FS="," -v red="$(tput setaf 1)" -v green="$(tput setaf 2)" -v yellow="$(tput setaf 3)" -v blue="$(tput setaf 4)" -v reset='\033[0m' 'BEGIN{printf "%-12s%-15s%-60s%-60s%s","ALERT_ID","ALERT_STATE","DASHBOARD","ALERT_NAME",ORS;for(c=0;c<155;c++) printf "="; printf "\n"}{printf "%-12d%s%-15s%s%-60s%-60.60s%s",$1,($2 ~ /ok/)?green:($2 ~ /paused/?yellow:($2 ~ /alerting/?red:blue)),$2,reset,$3,$4,ORS; } ' | sed 's/"//g' 2>&1
    else
        echo "ERROR: Grafana returned status code: $statusCode"
        exit 1
    fi
}

# --- Options processing -------------------------------------------
if [ $# -eq 0 ] ; then
    usage
    exit 1
fi

while getopts ":h" opt; do
    case ${opt} in 
        h )
            usage
            exit 0
            ;;
        \? )
            echo "Invalid option: -$OPTARG" 1>&2
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

if [ -z "$1" ]; then
    echo "Expected command or resource not provided"
    exit 1
else
    if [ -z "$GF_API_URL" ] || [ -z "$GF_AUTH_HEADER" ]; then
        echo "ERROR: Environment variables not found."
        usage
        exit 1
    fi
    resource=$1; shift
    case "$resource" in
        alerts)
            getAlerts
            exit 0     
            ;;
        * )
            echo "Invalid resource: $resource.
                Valid resources are:
                    - alerts" 1>&2
            exit 1
            ;;
    esac
fi

