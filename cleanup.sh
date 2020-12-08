#!/usr/bin/env bash
# RackN Copyright 2019
# Build Manager Demo

set -e

PATH=$PATH:.

rm -f profiles/linode.yaml
rm -f profiles/aws.yaml
rm -f profiles/google.yaml

FORCE="false"
PASSWORD="r0cketsk8ts"
while getopts ":P:f" CmdLineOpts
do
  case $CmdLineOpts in
    P) PASSWORD=${OPTARG}     ;;
    f) FORCE="true"          ;;
    u) usage; exit 0          ;;
    \?)
      echo "Incorrect usage.  Invalid flag '${OPTARG}'."
      exit 1
      ;;
  esac
done

export RS_ENDPOINT=$(terraform output drp_manager)
export RS_KEY="rocketskates:${PASSWORD}"
echo "Using RS_ENDPOINT=$RS_ENDPOINT and RS_KEY=$RS_KEY"

pools="linode aws google testing"
if [[ -r manager.tfvars ]]
then
  for P in $pools
  do
    if [[ $(drpcli pools status $P | jq -r '.InUse | length') -gt 0 ]]; then
      echo "Releasing machines in $P"
      drpcli pools manage release $P --all-machines > /dev/null
    else
      echo "No allocated machines in $P"
    fi
  done
fi

echo "waiting for all machines to be WorkflowComplete"
while [[ $(drpcli machines count WorkflowComplete Eq false) -gt 0 ]]; do
  suspects=$(drpcli machines list WorkflowComplete Eq false | jq -r .[].Name)
  echo "... waiting 5 seconds.  Working Machines are [$suspects]"
  sleep 5
done
echo "done waiting"


sites=$(drpcli endpoints list | jq -r .[].Id)
echo ""
echo "sites set to:"
echo $sites

echo "setting machines to destroy"
for mc in $sites;
do
  if drpcli machines exists Name:$mc > /dev/null
  then
    drpcli machines update Name:$mc '{"Locked":false}' > /dev/null
    drpcli machines meta set Name:$mc key BaseContext to "runner"
    drpcli machines update Name:$mc '{"Context":"runner"}' > /dev/null
    drpcli machines workflow Name:$mc site-destroy > /dev/null
    # backslash escape seems to be needed, otherwise it's being intepreted as YAML input
    drpcli machines set Name:$mc param Runnable to true
  else
    echo "machine $mc already does not exist"
  fi
done

echo "waiting for machines to destroy"
for mc in $sites;
do
  if drpcli machines exists Name:$mc > /dev/null
  then
    drpcli machines wait Name:$mc WorkflowComplete true 120
    drpcli machines destroy Name:$mc
  fi
done

if [ "$FORCE" == "true" ] || [ $(drpcli machines count Context Eq "") -eq 1 ]; then

  echo "removing manager"
  terraform init -no-color
  terraform destroy -no-color -auto-approve -var-file=manager.tfvars

  if [[ -e "multi-site-demo.json" ]]; then
    rm multi-site-demo.json
  fi

  rm -f terraform.tfstate terraform.tfstate.backup

else
  echo "WARNING provisioned machines still exist - did not destroy manager.  Call with -f to force!"
fi


