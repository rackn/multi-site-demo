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

The following files are required in the project root directory:
   * RackN License file (you can generate via self-service)
   * export LINODE_TOKEN=[your access token]

For complete prerequisites information, please see the **Prerequisites
Details** below.

Operation
---------

To setup the base site:

  1. Define LINODE_TOKEN
  1. Put rackn-license.json file in place
  1. Run the `manager.sh` command
  1. Login to your Endpoint(s)

Once the machines are checked in as endpoints you need to update the endpoints to use the correct version sets.  Remember that changing the DRP endpoint binary will require a reset in the UX.  Also, changing the base token of the endpoint will invalidate your tokens and require a fresh login.  DO NOT TRY TO USE THE Manager's UX while those changes are being made!

  1. Set the manager version sets
     1. manager should be paused
     1. add `cluster-3`, `license`, `manager-ignore`, and `site-base-v4.2.1`
     1. apply the manager changes
  1. Set the edge site version sets
     1. sites should be paused
     1. add `license` and `site-base-v4.2.1`
     1. apply the site changes

As a bonus, try to add something from the catalog at an edge site.  The manager will reset the change!

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
  1. build the catalog in your dr-server
     1. `drpcli plugins runaction manager buildCatalog`
     1. `drpcli catalog updateLocal -c rackn-catalog.json`
     1. `drpcli plugins runaction manager buildCatalog`
  1. zip the local /var/lib/dr-server/tftpboot/files/rebar-catalog

To use, make sure the file is in the directory with manager.sh when run.

Prerequists Details
-------------------

These prerequisites are specific to Linux.  They can be adapted to setup the
requirements for MacOS X as well.

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
scp ~/Downloads/rackn-license.json root@$MGR:
```

Login / connect to your bootstrap manager VM.
```
ssh root@$MGR
```

FROM the bootstrap manager, setup the multi-site demo prerequisites.
```
git clone https://github.com/rackn/multi-site-demo/
cd multi-site-demo
cp ../rackn-license.json .
```
IMPORTANT: set your``LINODE_TOKEN` environment variable!!!!
```
export LINODE_TOKEN=<<<YOUR_SECRET_TOKEN>>>
```

Now you can run the `manager.sh` script.

manager.sh
----------

Builds the cluster on Linode using Terraform and then does a bunch of setup and prep.  Uses bootstrap processes, so minimal upload is required.  Will create a 4 site manager.

Recommended to use `-c [clustername]` so that your cluster is easy to identify in Linode.

There are a lot of other flags, look at the code to review them.

scaleup.sh
----------

Used to create runner agents with workload for testing.

Options:

  * -s ## = number of instances per site (default = 10)
  * -r = remove test instances

cleanup.sh
----------

Destroys all the VMs.  Will use cloud-decommission to remove sites and wait for that to complete.  Then uses Terraform locally to remove the manager.

Will NOT work (without -f) if there are machine entries beyond the Sites and Manager.

Options:

  * -f = force cleanup even if there are other VMs
