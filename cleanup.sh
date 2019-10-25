#!/bin/bash
# RackN Copyright 2019
# Build Manager Demo

set -e

RS_ENDPOINT=$(terraform output drp_manager)

sites="us-central us-west us-east us-southeast"

echo "setting machines to destroy"
for mc in $sites;
do
  drpcli machines meta set Name:$mc key BaseContext to ""
  drpcli machines workflow Name:$mc site-destroy
  drpcli machines meta set Name:$mc key BaseContext to "terraform"
done

echo "waiting for machines to destroy"
for mc in $sites;
do
  drpcli machines wait Name:$mc Stage "complete-nobootenv" 120
done

terraform init -no-color
terraform destroy -no-color -auto-approve --var="linode_token=$LINODE_TOKEN"

rm linode.json
rm multi-site-demo.json
rm digitalrebar-runner
rm digitalrebar-terraform