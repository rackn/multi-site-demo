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

source /etc/os-release
case $ID in
  centos|rhel|fedora) $PKG="yum -y" ;;
  ubuntu|debian)      $PKG="apt -y" ;;
  *) xiterr 1 "Unsupported platform '$ID', don't know how to install pkg dependencies."
    ;;
esac

# install packages
echo "Installing required packages..."
$PKG install epel-release
$PKG install git jq docker wget curl vim unzip

# just assuming we're all one big happy systemd family
if $(which systemctl > /dev/null 2>&1 )
then
  systemctl daemon-reload
  systemctl enable docker
  systemctl start docker
else
  echo "!!! WARNING - didn't start Docker, no 'systemctl' daemon - make sure Docker is started correctly."
fi
echo ""

# fixup PATHs
printf "Writing updated PATH to .bashrc... "
echo "PATH=$HOME/multi-site-demo:$PATH" >> $HOME/.bashrc
echo "done"

# collect LINODE infoz:

if [[ -z "$LINODE_TOKEN" ]]
then
  read -p "Enter LINODE_TOKEN:  " LINODE_TOKEN
  export LINODE_TOKEN
fi

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
