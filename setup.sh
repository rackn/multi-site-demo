#!/usr/bin/env bash

# some quick pre-setup for the multi-site demo 

function xiterr() { [[ $1 =~ ^[0-9]+$ ]] && { XIT=$1; shift; } || XIT=1; printf "FATAL: $*\n"; exit $XIT; }

export PATH=$HOME/multi-site-demo:$PATH

set -e

# unpack *.gz files - not *.zip files
ZIPS=$(ls -1 *.gz)
ZIPS+=" .terraform/plugins/linux_amd64/terraform-provider-linode_v1.9.0_x4.gz"
( which gunzip > /dev/null ) || xiterr 1 "Unable to fine 'gunzip' in path"

for ZIP in $ZIPS
do
	[[ ! -r "$ZIP" ]] && continue || true
	echo "Starting gunzip for:  $ZIP"
	gunzip $ZIP &
done

echo "Waiting for unzip processes to complete..."
wait

# install packages
echo "Installing required packages..."
yum -y install epel-release
yum -y install git jq docker wget curl vim unzip
systemctl daemon-reload
systemctl enable docker
systemctl start docker
echo ""

# fixup PATHs
printf "Writing updated PATH to .bashrc... "
echo "PATH=$HOME/multi-site-demo:$PATH" >> $HOME/.bashrc
echo "done"

# collect LINOD infoz:

read -p "Enter LINODE_TOKEN:  " LINODE_TOKEN
export LINODE_TOKEN

echo ""
printf "Writing LINODE_TOKEN to .bashrc... "
echo "export LINODE_TOKEN=$LINODE_TOKEN" >> $HOME/.bashrc
echo "done"

echo ""
echo "Updating multi-site-demo content in place"
cd $HOME/multi-site-demo
git pull
echo ""

echo ""
echo "Either log out and back in, or source .bashrc:"
echo ""
echo "source $HOME/.bashrc"
echo ""
echo "Maybe you need to update the 'rackn-license.json' ??"
echo "Maybe upload your own customer Catalog ??  Otherwise the S3 one will be downloaded."
echo ""
