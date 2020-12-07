#!/usr/bin/env bash
# RackN Copyright 2020
# Build Manager Demo

set -e

PATH=$PATH:.

export RS_ENDPOINT=$(terraform output drp_manager)

REMOVE="false"
SCALE=10
while getopts ":s:r" CmdLineOpts
do
  case $CmdLineOpts in
    r) REMOVE="true"          ;;
    s) SCALE=${OPTARG}        ;;
    u) usage; exit 0          ;;
    \?)
      echo "Incorrect usage.  Invalid flag '${OPTARG}'."
      exit 1
      ;;
  esac
done

icons=$(drpcli version_sets show site-base-tip | jq '.Global["dev/wait-icons"]')
if drpcli profiles set global param "dev/wait-icons" to - <<< $icons > /dev/null ; then
  echo "setting icons"
else
  echo "icons already set"
fi

sites=$(drpcli endpoints list | jq -r .[].Id)
echo "sites set to:"
echo $sites

echo "create $SCALE load test machines"
i=1
while (( i < SCALE )); do
  mc=$(printf "scale-%05d-manager" $i)
  if drpcli machines exists Name:$mc &> /dev/null ; then
    if [ "$REMOVE" == "true" ] ; then
      echo "removing machine $mc."
      drpcli machines destroy Name:${mc} >/dev/null
    else
      echo "machine $mc already exists.  restarting load-generator"
      drpcli machines workflow Name:${mc} "load-generator" >/dev/null
    fi
  else
    if [ "$REMOVE" != "true" ] ; then
      echo "creating $mc in manager"
      sleep 1
      drpcli machines create "{\"Name\":\"${mc}\", \
        \"Workflow\":\"load-generator\", \
        \"Description\":\"Load Test $i\", \
        \"Meta\":{\"BaseContext\":\"runner\", \"icon\":\"cloud\"}}" >/dev/null
    else
      echo "skipping, $mc does not exist"
    fi
  fi
  for s in $sites;
  do
  (
    mc=$(printf "scale-%05d-$s" $i)
    if drpcli -u $s machines exists Name:$mc &> /dev/null ; then
      if [ "$REMOVE" == "true" ] ; then
        echo "removing machine $mc."
        drpcli -u $s machines destroy Name:${mc} >/dev/null
      else
        echo "machine $mc already exists.  restarting load-generator"
        drpcli -u $s machines workflow Name:${mc} "load-generator" >/dev/null
      fi
    else
      if [ "$REMOVE" != "true" ] ; then
        echo "creating $mc in $s"
        sleep 1
        drpcli -u $s machines create "{\"Name\":\"${mc}\", \
          \"Workflow\":\"load-generator\", \
          \"Description\":\"Load Test $i\", \
          \"Meta\":{\"BaseContext\":\"runner\", \"icon\":\"cloud\"}}" >/dev/null
      else
        echo "skipping, $mc does not exist"
      fi
    fi
  ) &
  done
  (( i++ ))
done

wait
