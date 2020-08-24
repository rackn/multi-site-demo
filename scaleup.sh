#!/usr/bin/env bash
# RackN Copyright 2020
# Build Manager Demo

set -e

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

sites="us-central us-west us-east us-southeast"
if [[ -r manager.tfvars ]]
then
  PRE=$(cat manager.tfvars | grep cluster_prefix | cut -d '"' -f2)
  for S in $sites
  do
    s+="$PRE-$S "
  done
  sites=$s
fi

echo "sites set to:"
echo $sites

echo "create $SCALE load test machines"
i=1
while (( i < SCALE )); do
  for s in $sites;
  do
    mc=$(printf "$s-%05d" $i)
    if drpcli -u $s machines exists Name:$mc > /dev/null ; then
      if [ "$REMOVE" == "true" ] ; then
        echo "removing machine $mc."
        drpcli -u $s machines destroy Name:${mc} >/dev/null &
      else
        echo "machine $mc already exists.  restarting load-generator"
        drpcli -u $s machines workflow Name:${mc} "load-generator" >/dev/null &
      fi
    else
      if [ "$REMOVE" != "true" ] ; then
        echo "creating $mc in $s"
        drpcli -u $s machines create "{\"Name\":\"${mc}\", \
          \"Workflow\":\"load-generator\", \
          \"Description\":\"Load Test $i\", \
          \"Meta\":{\"BaseContext\":\"runner\", \"icon\":\"cloud\"}}" >/dev/null &
      fi
    fi
  done
  (( i++ ))
done

wait
