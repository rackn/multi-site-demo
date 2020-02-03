#!/bin/bash
# RackN Copyright 2019
# Build Manager Demo

set -e

export RS_ENDPOINT=$(terraform output drp_manager)

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
    drpcli machines meta set Name:$mc key BaseContext to "runner"
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
    drpcli machines wait Name:$mc Stage "complete-nobootenv" 120
    drpcli machines destroy Name:$mc
  fi
done

echo "Downloading Contexts for next run"
raw=$(drpcli contexts list Engine=docker-context)
contexts=$(jq -r ".[].Name" <<< "${raw}")
i=0
for context in $contexts; do
  image=$(jq -r ".[$i].Image" <<< "${raw}")
  if [[ -f $context.tar ]] ; then
    echo "has $context.tar file, skipping download"
  else
    echo "downloading $image for $context context"
    drpcli files download "contexts/docker-context/$image" > $context.tar
  fi
  i=$(($i + 1))
done


if [[ "$(drpcli machines list | jq length)" == "1" ]]; then

  echo "removing manager"
  terraform init -no-color
  terraform destroy -no-color -auto-approve -var-file=manager.tfvars

  if [[ -e "linode.json" ]]; then
    rm linode.json
  fi

  if [[ -e "multi-site-demo.json" ]]; then
    rm multi-site-demo.json
  fi

  rm -f terraform.tfstate terraform.tfstate.backup

else
  echo "WARNING machines still exist - did not destroy manager"
fi


