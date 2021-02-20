#!/bin/bash
# ------------------------------------------------------------------
# Author: Omar Rojina (omar.rojina@wizeline.com)
# Description:  This script can execute actions using the Grafana
#               API such as:
#                 - List alerts
#                 - Pause/Resume alerts
# ------------------------------------------------------------------

usage () {
    echo "Usage: 
        $0 [-h] [config [command] | resource [action] [args]]

          Examples:
                |-------------------------------------------------------------|--------------------------------------------------------|
                |           COMMAND                                           |                   DESCRIPTION                          |
                |-------------------------------------------------------------|--------------------------------------------------------|
                |  $0 -h                                        | Prints this message                                    |
                |  $0 config                                    | Prints the current configuration settings              |
                |  source $0 config set-env qa <organization>   | Set the current environment to qa (env: dev|qa|prod)   |
                |  $0 alerts                                    | Prints the list of alerts in the current environment   |
                |  $0 alerts pause                              | Pauses all the alerts in the current environment       |
                |  $0 alerts pause -i 13,96,55                  | Pauses alerts by their ID in the current environment   |
                |  $0 alerts pause -a 'Pause alerts'            | Pauses all the alerts and adds an annotation           |
                |  $0 alerts pause -a 'Pause alerts' -i 13,96   | Pauses alerts by their ID and adds an annotation       |
                |  $0 alerts resume                             | Resume all the alerts in the current environment       |
                |  $0 alerts resume -i 13,96,55                 | Resume alerts by their ID in the current environment   |
                |  $0 alerts resume -a 'Pause alerts'           | Resume all the alerts and adds an annotation           |
                |  $0 alerts resume -a 'Pause alerts' -i 13,96  | Resume alerts by their ID and adds an annotation       |
                |----------------------------------------------------------------------------------------------------------------------|

                NOTE: This script requires jq to be installed (https://stedolan.github.io/jq/download/)
                "
}

printConfig () {
    env | grep GF_
}

# $1=environment $2=organization
setEnv () {  
    unset GF_ENV
    unset GF_API_URL
    unset GF_TOKEN
    unset GF_AUTH_HEADER
    unset GF_EXCLUDE_ALERTS
    unset GF_CURR_ORG    

    local environment=$1

    case "$environment" in
        dev | qa | prod)
            local org=$2           
            export GF_CURR_ORG=$org
            source <(grep '=' <(grep -A2 "\[$GF_CURR_ORG\]" ~/.grafana/"$environment"))
            source <(grep '=' <(grep -A3 "\[ENVIRONMENT\]" ~/.grafana/"$environment"))
            printConfig        
            ;;
        *)
            echo "Invalid environment.
            Valid environments are: dev,qa,prod"
            ;;
    esac
    
}

getStatusCode () {
    local statusCode
    statusCode=$(curl --write-out '%{http_code}' --output /dev/null -ksH "$GF_AUTH_HEADER" "$GF_API_URL"/org)
    echo "$statusCode"
}

getAlerts () {
    statusCode=$(getStatusCode)

    if [ "$statusCode" -eq 200 ]; then
        curl -ksH "$GF_AUTH_HEADER" "$GF_API_URL"/alerts/ | \
        jq -r '.[] | select(.state | test("no_data|paused|alerting|pending|ok|unknown")) | [.id,.state,.dashboardSlug,.name] | @csv ' | \
        awk -v FS="," \
        -v red="$(tput setaf 1)" \
        -v green="$(tput setaf 2)" \
        -v yellow="$(tput setaf 3)" \
        -v blue="$(tput setaf 4)" \
        -v reset='\033[0m' \
        'BEGIN{
            printf "%-12s%-15s%-60s%-60s%s","ALERT_ID","ALERT_STATE","DASHBOARD","ALERT_NAME",ORS;
            for(c=0;c<155;c++) 
                printf "="; 
                printf "\n"
            }
            {
            printf "%-12d%s%-15s%s%-60s%-60.60s%s",$1,($2 ~ /ok/)?green:($2 ~ /paused/?yellow:($2 ~ /alerting/?red:blue)),$2,reset,$3,$4,ORS; 
            } ' | sed 's/"//g' 2>&1
    else
        echo "ERROR: Grafana returned status code: $statusCode"
        exit 1
    fi
}

# $1=alertID
checkExcluded () {
    alert=$1

    for excluded in $(echo ${GF_EXCLUDE_ALERTS[*]} | sed "s/,/ /g")
    do
        if [[ "$excluded" -eq "$alert" ]]; then
            return 1
        fi
    done
}

# $1=alertID
pauseAlert () {
    alert=$1
    checkExcluded $alert
    isExcluded=$?

    if [[ 0 -eq $isExcluded ]]; then
        curl -X POST -ksH "$GF_AUTH_HEADER" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d '{"paused":true}' \
        "$GF_API_URL/alerts/$alert/pause" 2>&1 && printf "\n"; 
    else
        printf "Excluding alert with ID: %d\n" $alert;
    fi
}

# $1=alertID
resumeAlert () {
    alert=$1
    checkExcluded $alert
    isExcluded=$?

    if [[ 0 -eq $isExcluded ]]; then
        curl -X POST -ksH "$GF_AUTH_HEADER" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d '{"paused":false}' \
        "$GF_API_URL/alerts/$alert/pause" 2>&1 && printf "\n"; 
    else
        printf "Excluding alert with ID: %d\n" $alert;
    fi
}

addAnnotation () {
    DATA="{\"what\": "\"$1\"", \"tags\": [\"grafana-cli\",\""$2"\"]}"

    curl -X POST -ksH "$GF_AUTH_HEADER" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d "$DATA" \
    "$GF_API_URL/annotations/graphite" 2>&1 && printf "\n";  
}

# $1=alertIDs separated by comma, $2=Annotation text
pauseAlerts () {
    if [ ! -z "$2" ]; then
        addAnnotation "$2" "alerting-pause"
    fi

    if [ -z "$1" ]; then
        curl -ksH "$GF_AUTH_HEADER" "$GF_API_URL/alerts/" | jq -r '.[] | [.id] | @csv ' | while read -r line; do pauseAlert "$line"; done 2>&1; printf "\n"
    else
        if [[ ! $1 =~ (^[0-9]+)((\,[0-9]+)+$|$) ]]; then
            echo "Invalid argument: Alert IDs. Expected ids in comma separated format "
            exit 1
        fi
        echo "$1" | sed -e $'s/,/\\\n/g' | while read -r line; do pauseAlert "$line";done 2>&1; printf "\n"
    fi
}

# $1=alertIDs separated by comma, $2=Annotation text
resumeAlerts () {
    if [ ! -z "$2" ]; then
        addAnnotation "$2" "alerting-resume"
    fi

    if [ -z "$1" ]; then
        curl -ksH "$GF_AUTH_HEADER" "$GF_API_URL/alerts/" | jq -r '.[] | [.id] | @csv ' | while read -r line; do resumeAlert "$line";  done 2>&1; printf "\n"
    else
        if [[ ! $1 =~ (^[0-9]+)((\,[0-9]+)+$|$) ]]; then
            echo "Invalid argument: Alert IDs. Expected ids in comma separated format "
            exit 1
        fi
        echo "$1" | sed -e $'s/,/\\\n/g' | while read -r line; do resumeAlert "$line"; done 2>&1; printf "\n"
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
elif [ "$1" = "config" ]; then
    shift
    command=$1
    if [ -z "$command" ]; then
        printConfig
    else
        case "$command" in
            set-env)
                shift
                if [ -z "$1" ]; then
                    echo "Environment parameter was not provided but it was expected"
                    usage
                else                
                    env=$1
                    shift
                    if [ -z "$1" ]; then
                        echo "Error: Organization value was expected but it was not provided"
                        usage
                    else
                        org=$1
                        echo "Switching environment: $env selected ..."
                        setEnv "$env" "$org"
                    fi                    
                fi
                ;;
            * )
                echo "Invalid command: $command "
                exit 1
                ;;
        esac
    fi
else
    if [ -z "$GF_API_URL" ] || [ -z "$GF_AUTH_HEADER" ]; then
        echo "ERROR: Environment variables not found. Use the ""config"" command."
        usage
        exit 1
    fi
    resource=$1; shift
    case "$resource" in
        alerts)
            action=$1; shift
            if [ -z "$action" ]; then
                getAlerts
                exit 0
            fi

            case "$action" in
                pause)
                    while getopts ":a:i:" opt; do
                        case ${opt} in
                            a )
                                annotation=$OPTARG
                                ;;
                            i )
                                alertIds=$OPTARG
                                ;;
                            \? )
                                echo "Invalid option: -$OPTARG" 1>&2
                                exit 1
                                ;;
                            : )
                                echo "Invalid Option: -$OPTARG requires an argument" 1>&2
                                exit 1
                                ;;
                        esac
                    done
                    shift $((OPTIND-1))

                    pauseAlerts "$alertIds" "$annotation"
                    ;;
                resume)
                    while getopts ":a:i:" opt; do
                        case ${opt} in
                            a )
                                annotation=$OPTARG
                                ;;
                            i )
                                alertIds=$OPTARG
                                ;;
                            \? )
                                echo "Invalid option: -$OPTARG" 1>&2
                                exit 1
                                ;;
                            : )
                                echo "Invalid Option: -$OPTARG requires an argument" 1>&2
                                exit 1
                                ;;
                        esac
                    done
                    shift $((OPTIND-1))

                    resumeAlerts "$alertIds" "$annotation"

                    ;;
                * )
                    echo "Invalid action: $action
                        Valid actions are:
                            - pause
                            - resume" 1>&2
                    exit 1
                    ;;
            esac       
            ;;
        * )
            echo "Invalid resource: $resource.
                Valid resources are:
                    - alerts" 1>&2
            exit 1
            ;;
    esac
fi

