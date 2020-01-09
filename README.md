Multi-Site Manager Demo
=======================
_By RackN, October 2019_


This content is used by RackN to showcase Multi-Site Management and Context
features.  It is designed to be used with Linode; however, the context
can be easily adapted for uses.

The tooling is designed to be run from a Mac or Linux environment (eg
your laptop).  However, you may choose to spin up a very small Linode
instance as a CentOS 7 linux install, and setup the prerequisites in
that VM for control of the infrastructure.

Prerequists Overview
--------------------

The following applications are required to be in your path:
   * docker
   * terraform

The following files are required in the project root directory:
   * drpcli (v4.1 or later)
   * dangerzone plugin binary (available by request from RackN for trial purposes)
   * RackN License file (you can generate via self-service)
   * export LINODE_TOKEN=[your access token]

You can bypass the dangerzone plugin requirement by installing Docker on
your host by hand.  Dangerzone (which was not public at the time of the
video) is only used for bootstrapping the manager host to run Docker.

You must also have Terraform and Docker installed.

For complete prerequisites information, please see the **Prerequisites
Details** below.

Operation
---------

To setup the base site:

  1. Define LINODE_TOKEN
  1. Copy the rackn-catalog.ref to rackn-catalog.json (unless you want to define your own catalog or use the latest)
  1. Run the `manager.sh` command
  1. Login to your Endpoint(s)
  
Once the machines are checked in as endpoints you need to update the endpoints to use the correct version sets.  Remember that changing the DRP endpoint binary will require a reset in the UX.  Also, changing the base token of the endpoint will invalidate your tokens and require a fresh login.  DO NOT TRY TO USE THE Manager's UX while those changes are being made!

  1. Set the manager version sets
     1. manager should be paused
     1. add `cluster-3`, `credential`, `license`, `manager-ignore` and `site-base-v4.1.1`
     1. apply the manager changes
  1. Set the edge site version sets
     1. sites should be paused
     1. add `credential`, `license`, and `site-base-v4.1.1`
     1. apply the site changes

As a bonus, try to add something from the catalog at an edge site.  The manager will reset the chnage!

To expand the cluster, you need to run the `site-expand` workflow on all the edges.

   1. the `cluster-3` version set is required to set the node count to 3 instead of 0
   1. set the `site-expand` workflow

There is a tricky hack to install k3s:

   1. the `k3s-demo` profile is part of the manager content pack
   1. the `site-expand` workflow adds the `k3s-demo` profile to each edge site via the API
   1. the krib demo will work locally on the local profile - it is NOT mirrored by the manager in v4.1.
   1. since the profile also exists at the manager level the object the single-pane-of-glass updates will work.
   1. this will be addressed in a more elegant way in future versions.

Building your own static-catalog.zip
------------------------------------

This demo uses a static-catalog to reduce downloads.  If you change the catalog
reference file you should build your own catalog from it.

If you don't create one, the script will download a version from: https://rackn-private.s3-us-west-2.amazonaws.com/static-catalog.zip

To build your own static-catalog.zip:

  1. install a local dr-server
  1. upload your catalog
     1. `drpcli files upload rackn-catalog.json to "rebar-catalog/rackn-catalog.json"`
     1. `drpcli contents upload rackn-catalog.json`
  1. build the catalog in your dr-server
     1. `drpcli catalog updateLocal -c rackn-catalog.json`
     1. `drpcli plugins runaction manager buildCatalog`
  1. zip the local /var/lib/dr-server/tftpboot/files/rebar-catalog


Prerequists Details
-------------------

These prerequisites are specific to Linux.  They can be adapted to setup the
requirements for MacOS X as well.  Please note that certain components are
ONLY available from RackN directly and you will not be able to complete these
steps without contacting RackN.  Please email support@rackn.com for more
details.

Create a Linode Token if you haven't already at: https://cloud.linode.com/profile/tokens

From your laptop/workstation - prep your bootstrap manager.

```
export MGR=<IP_of_your_bootstrap_VM>

# make prep directory where github code and artifacts will be copied to
ssh root@$MGR "mkdir -p multi-site-demo"

# download the rackn license and save it to your local filesystem
# see the **RackN & License** section of an existing DRP Endpoint
# that has your License installed - or ask support@rackn.com

# copy your license file to Linode Manager
scp ~/Downloads/rackn-license.json root@$MGR:./multi-site-demo/
```

Login / connect to your bootstrap manager VM.
```
ssh root@$MGR
```

FROM the bootstrap manager, setup the multi-site demo prerequisites.
```
git clone https://github.com/rackn/multi-site-demo/
cd multi-site-demo
curl -s -o drpcli https://rebar-catalog.s3-us-west-2.amazonaws.com/drpcli/v4.1.2/amd64/linux/drpcli
curl -s -o tf.zip https://releases.hashicorp.com/terraform/0.12.13/terraform_0.12.13_linux_amd64.zip
yum -y install epel-release
yum -y install unzip jq docker
unzip tf.zip
chmod 755 terraform drpcli
rm tf.zip
systemctl daemon-reload
systemctl enable docker
systemctl start docker
```
IMPORTANT: set your``LINODE_TOKEN` environment variable!!!!
```
export LINODE_TOKEN=<<<YOUR_SECRET_TOKEN>>>
```

Now you can run the `manager.sh` script.
