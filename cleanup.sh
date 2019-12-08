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
    s+="$PRE-$s "
  done
  sites=$s
fi

echo "setting machines to destroy"
for mc in $sites;
do
  if drpcli machines exists Name:$mc > /dev/null; then
    drpcli machines meta set Name:$mc key BaseContext to ""
    drpcli machines workflow Name:$mc site-destroy
    drpcli machines meta set Name:$mc key BaseContext to "terraform"
    drpcli machines set Name:$mc param Runnable to true
  else
    echo "machine $mc already does not exist"
  fi
done

echo "waiting for machines to destroy"
for mc in $sites;
do
  if drpcli machines exists Name:$mc > /dev/null; then
    drpcli machines wait Name:$mc Stage "complete-nobootenv" 120
  fi
done

terraform init -no-color
terraform destroy -no-color -auto-approve --var="linode_token=$LINODE_TOKEN"


if [[ -e "linode.json" ]]; then
  rm linode.json
fi

if [[ -e "multi-site-demo.json" ]]; then
  rm multi-site-demo.json
fi

if [[ -e "runner.tar" ]]; then
  rm runner.tar
fi

if [[ -e "terraform.tar" ]]; then
  rm terraform.tar
fi

docker rmi digitalrebar-runner
docker rmi digitalrebar-terraform
