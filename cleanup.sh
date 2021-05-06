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

pools="linode aws google azure digitalocean testing"
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


if [[ "$FORCE" == "true" ]]; then
  echo "WARNING: potential orphaned servers!! skipping WorkflowComplete test"
else
  echo "waiting for all machines to be WorkflowComplete"
  while [[ $(drpcli machines count WorkflowComplete Eq false Workflow Ne "") -gt 0 ]]; do
    suspects=$(drpcli machines list WorkflowComplete Eq false Workflow Ne "" | jq -r .[].Name)
    echo "... waiting 5 seconds.  Working Machines are [$suspects]"
    sleep 5
  done
  echo "done waiting"
fi

sites=$(drpcli endpoints list | jq -r .[].Id)
echo ""
echo "Sites list: $sites"
echo ""
echo "setting machines to destroy"
for s in $sites; do
  mc=$(drpcli endpoints show $s | jq -r .Meta.Uuid)
  if drpcli machines exists $mc > /dev/null; then
    echo "  destroy site $s machine $mc via workflow"
    drpcli machines update $mc '{"Locked":false}' > /dev/null
    drpcli machines meta set $mc key BaseContext to "drpcli-runner" > /dev/null
    drpcli machines update $mc '{"Context":"drpcli-runner"}' > /dev/null
    drpcli machines workflow $mc cloud-site-destroy > /dev/null
    # backslash escape seems to be needed, otherwise it's being intepreted as YAML input
    drpcli machines run $mc > /dev/null
  else
    echo "  site $s machine $mc already does not exist"
  fi
done

echo "waiting for machines to destroy"
for s in $sites; do
  mc=$(drpcli endpoints show $s | jq -r .Meta.Uuid)
  if [[ -z "$mc" ]] ; then
    echo "  endpoint $s already removed, no action required"
  else
    if drpcli machines exists $mc > /dev/null; then
      echo "  waiting for removal of $s via $mc"
      if drpcli machines wait $mc WorkflowComplete true 120 ; then
        echo "  all clear, destroy $mc"
        sleep 1
        drpcli machines destroy $mc
        drpcli endpoints destroy $s >/dev/null 2>/dev/null || :
      else
        echo "  WARNING workflow for $s on $mc did not complete!"
        exit 1
      fi
    else
      echo "  MANUAL CLEANUP! site $s does not have a managed machine $mc"
      exit 1
    fi
  fi
done

if [[ "$FORCE" == "true" ]]; then
  echo "WARNING: potential orphaned servers!! skipping WorkflowComplete test"
else
  echo "waiting for all machines to be WorkflowComplete"
  while [[ $(drpcli machines count WorkflowComplete Eq false Workflow Ne "") -gt 0 ]]; do
    suspects=$(drpcli machines list WorkflowComplete Eq false Workflow Ne "" | jq -r .[].Name)
    echo "... waiting 5 seconds.  Working Machines are [$suspects]"
    sleep 5
  done
  echo "done waiting"
fi

if [ "$FORCE" == "true" ] || [ $(drpcli machines count Context Eq "") -eq 1 ]; then

  echo "removing manager"
  terraform init -no-color
  terraform destroy -no-color -auto-approve -var-file=manager.tfvars

  if [[ -e "multi-site-demo.json" ]]; then
    rm multi-site-demo.json
  fi
  rm -f multi-site/profiles/*

  rm -f terraform.tfstate terraform.tfstate.backup
else
  echo "WARNING provisioned machines still exist - did not destroy manager.  Call with -f to force!"
fi


