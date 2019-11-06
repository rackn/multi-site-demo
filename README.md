Multi-Site Manager Demo
=======================
_By RackN, October 2019_


This content is used to RackN Showcase Multi-Site Management and Context
features.  It is designed to be used with Linode; however, the context
can be easily adapted for uses.

The tooling is designed to be run from a Mac or Linux environment (eg
your laptop).  However, you may choose to spin up a very small Linode
instance as a CentOS 7 linux install, and setup the prerequisites in
that VM for control of the infrastructure.

Prerequists Overview
--------------------

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
Overview** below.

Operation
---------

To setup the base site:

  1. Define LINODE_TOKEN
  2. Run the `manager.sh` command
  3. Login to your Endpoint(s)
  
Once the machines are checked in as endpoints:

  * TBD

Prerequists Overview
--------------------

These prerequisites are specific to Linux.  They can be adapted to setup the
requirements for MacOS X as well.  Please note that certain components are
ONLY available from RackN directly and you will not be able to complete these
steps without contacting RackN.  Please email support@rackn.com for more
details.

Create a Linode Token if you haven't already from:
https://cloud.linode.com/profile/tokens

# from your laptop/workstation - prep your bootstrap manager
export MGR=<IP_of_your_bootstrap_VM>

# make prep directory where github code and artifacts will be copied to
ssh root@$MGR "mkdir -p multi-site-demo"

# download the rackn license and save it to your local filesystem
# see the **RackN & License** section of an existing DRP Endpoint
# that has your License installed - or ask support@rackn.com

# copy your license file to Linode Manager
scp ~/Downloads/rackn-license.json root@$MGR:./multi-site-demo/

# build dangerzone - MUST BE RACKN employee / git repo access
git clone https://github.com/rackn/provision-server.git
cd provision-server
export GOOS=linux
export GOARCH=amd64
tools/build-one.sh cmds/dangerzone
scp bin/$GOOS/$GOARCH/dangerzone root@$MGR:./multi-site-demo/

# connect to your bootstrap manager VM
ssh root@$MGR

# FROM the bootstrap manager
git clone https://github.com/rackn/multi-site-demo/
cd multi-site-demo
curl -s -o drpcli https://rebar-catalog.s3-us-west-2.amazonaws.com/drpcli/v4.1.2/amd64/linux/drpcli
curl -s -o tf.zip https://releases.hashicorp.com/terraform/0.12.13/terraform_0.12.13_linux_amd64.zip
yum -y install epel-release
yum -y install unzip jq docker
unzip tf.zip
chmod 755 terraform drpcli
rm tf.zip
export LINODE_TOKEN=<<<YOUR_SECRET_TOKEN>>>
