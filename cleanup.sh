#!/usr/bin/env bash
# RackN Copyright 2019
# Build Manager Demo

set -e

PATH=$PATH:.

export RS_ENDPOINT=$(terraform output drp_manager)

rm -f profiles/linode.yaml
rm -f profiles/aws.yaml
rm -f profiles/google.yaml

FORCE="false"
while getopts ":f" CmdLineOpts
do
  case $CmdLineOpts in
    f) FORCE="true"          ;;
    u) usage; exit 0          ;;
    \?)
      echo "Incorrect usage.  Invalid flag '${OPTARG}'."
      exit 1
      ;;
  esac
done

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
while [[ $(drpcli machines count WorkflowComplete=false) -gt 0 ]]; do
  echo "... waiting 5 seconds"
  sleep 5
done
echo "done waiting"

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
    drpcli machines workflow Name:$mc cloud-decommission > /dev/null
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
    drpcli endpoints destroy $mc
  fi
done

if [ "$FORCE" == "true" ] || [ "$(drpcli machines list | jq length)" == "1" ]; then

  echo "removing manager"
  terraform init -no-color
  terraform destroy -no-color -auto-approve -var-file=manager.tfvars

  if [[ -e "multi-site-demo.json" ]]; then
    rm multi-site-demo.json
  fi

  rm -f terraform.tfstate terraform.tfstate.backup

else
  echo "WARNING machines still exist - did not destroy manager.  Call with -f to force!"
fi


