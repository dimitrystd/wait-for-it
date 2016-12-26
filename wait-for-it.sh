#!/usr/bin/env bash
#   Use this script to test if a given TCP host/port are available

cmdname=$(basename $0)

echoerr() { if [[ $QUIET -ne 1 ]]; then echo "$@" 1>&2; fi }

usage()
{
    cat << USAGE >&2
Usage:
    $cmdname (host:port|--url) [-s] [-t timeout] [-r timeout] [-- command args]
    -h HOST | --host=HOST       Host or IP under test
    -p PORT | --port=PORT       TCP port under test
                                Alternatively, you specify the host and port as host:port
    --url=http://domain.com/path/to/check
                                URL that should return 200
    -s | --strict               Only execute subcommand if the test succeeds
    -q | --quiet                Don't output any status messages
    -t TIMEOUT | --timeout=TIMEOUT
                                Timeout in seconds, zero for no timeout
    -r TIMEOUT | --retry=TIMEOUT
                                Wait TIMEOUT between retries (10 sec by default)
    -- COMMAND ARGS             Execute command with args after the test finishes
USAGE
    exit 1
}

wait_for()
{
    if [[ $TIMEOUT -gt 0 ]]; then
        echoerr "$cmdname: waiting $TIMEOUT seconds for $HOST:$PORT"
    else
        echoerr "$cmdname: waiting for $HOST:$PORT without a timeout"
    fi
    start_ts=$(date +%s)
    while :
    do
        (echo > /dev/tcp/$HOST/$PORT) >/dev/null 2>&1
        result=$?
        if [[ $result -eq 0 ]]; then
            end_ts=$(date +%s)
            echoerr "$cmdname: $HOST:$PORT is available after $((end_ts - start_ts)) seconds"
            break
        fi
        echoerr "$cmdname: no response after $(($(date +%s) - start_ts)) seconds"
        sleep $RETRY_TIMEOUT
    done
    return $result
}

wait_for_url()
{
    if [[ $TIMEOUT -gt 0 ]]; then
        echoerr "$cmdname: waiting $TIMEOUT seconds for $URL"
    else
        echoerr "$cmdname: waiting for $URL without a timeout"
    fi
    start_ts=$(date +%s)
    while :
    do
        curl --output /dev/null --silent --head --fail --max-time 5 $URL
        result=$?
        if [[ $result -eq 0 ]]; then
            end_ts=$(date +%s)
            echoerr "$cmdname: $URL is available after $((end_ts - start_ts)) seconds"
            break
        fi
        echoerr "$cmdname: no response after $(($(date +%s) - start_ts)) seconds"
        sleep $RETRY_TIMEOUT
    done
    return $result
}

wait_for_wrapper()
{
    # In order to support SIGINT during timeout: http://unix.stackexchange.com/a/57692
    if [[ $QUIET -eq 1 ]]; then
        timeout $TIMEOUT $0 --quiet --child --url=$URL --host=$HOST --port=$PORT --timeout=$TIMEOUT --retry=$RETRY_TIMEOUT &
    else
        timeout $TIMEOUT $0 --child --url=$URL --host=$HOST --port=$PORT --timeout=$TIMEOUT --retry=$RETRY_TIMEOUT &
    fi
    PID=$!
    trap "kill -INT -$PID" INT
    wait $PID
    RESULT=$?
    if [[ $RESULT -ne 0 ]]; then
        if [[ $URL ]]; then
            echoerr "$cmdname: timeout occurred after waiting $TIMEOUT seconds for $URL"
        else
            echoerr "$cmdname: timeout occurred after waiting $TIMEOUT seconds for $HOST:$PORT"
        fi
    fi
    return $RESULT
}

# process arguments
while [[ $# -gt 0 ]]
do
    # Read below why URL is done as standalone IF instead of one more case
    if [[ "$1" == --url=* ]] ; then
        URL="${1#*=}"
        shift 1
    fi

    case "$1" in
        *:* )
        hostport=(${1//:/ })
        HOST=${hostport[0]}
        PORT=${hostport[1]}
        shift 1
        ;;
        --child)
        CHILD=1
        shift 1
        ;;
        -q | --quiet)
        QUIET=1
        shift 1
        ;;
        -s | --strict)
        STRICT=1
        shift 1
        ;;
        -h)
        HOST="$2"
        if [[ $HOST == "" ]]; then break; fi
        shift 2
        ;;
        --host=*)
        HOST="${1#*=}"
        shift 1
        ;;
        # Fo some reason pattern doesn't work if value contains colon (:)
        # --url=*)
        # URL="${1#*=}"
        # shift 1
        # ;;
        -p)
        PORT="$2"
        if [[ $PORT == "" ]]; then break; fi
        shift 2
        ;;
        --port=*)
        PORT="${1#*=}"
        shift 1
        ;;
        -t)
        TIMEOUT="$2"
        if [[ $TIMEOUT == "" ]]; then break; fi
        shift 2
        ;;
        --timeout=*)
        TIMEOUT="${1#*=}"
        shift 1
        ;;
        -r)
        RETRY_TIMEOUT="$2"
        shift 2
        ;;
        --retry=*)
        RETRY_TIMEOUT="${1#*=}"
        shift 1
        ;;
        --)
        shift
        CLI="$@"
        break
        ;;
        --help)
        usage
        ;;
        *)
        echoerr "Unknown argument: $1"
        usage
        ;;
    esac
done

if [[ ! $URL && ! $HOST ]]; then
    echoerr "Error: you need to provide URL or host and port to test."
    usage
else
    if [[ ! $URL && (! $HOST || ! $PORT) ]]; then
        echoerr "Error: you need to provide a host and port to test."
        usage
    fi
fi

TIMEOUT=${TIMEOUT:-15}
RETRY_TIMEOUT=${RETRY_TIMEOUT:-10}
STRICT=${STRICT:-0}
CHILD=${CHILD:-0}
QUIET=${QUIET:-0}

if [[ $TIMEOUT && (! $RETRY_TIMEOUT || $RETRY_TIMEOUT -ge $TIMEOUT) ]]; then
    echoerr "Error: Retry timeout must be less than $TIMEOUT"
    usage
fi

if [[ $CHILD -gt 0 ]]; then
    if [[ $URL ]]; then
        wait_for_url
        RESULT=$?
        exit $RESULT
    else
        wait_for
        RESULT=$?
        exit $RESULT
    fi
else
    wait_for_wrapper
    RESULT=$?
fi

if [[ $CLI != "" ]]; then
    if [[ $RESULT -ne 0 && $STRICT -eq 1 ]]; then
        echoerr "$cmdname: strict mode, refusing to execute subprocess"
        exit $RESULT
    fi
    exec $CLI
else
    exit $RESULT
fi
