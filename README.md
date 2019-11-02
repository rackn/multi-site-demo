Multi-Site Manager Demo
=======================
_By RackN, October 2019_


This content is used to RackN Showcase Multi-Site Management and Context features.  It is designed to be used with Linode; however, the context
can be easily adapted for uses.

Prerequists
-----------

The following files are required in the project root directory:
   * drpcli (v4.1 or later)
   * dangerzone plugin binary
   * RackN License file
   * export LINODE_TOKEN=[your access token]

You can bypass the dangerzone plugin requirement by installing Docker on your host by hand.  Dangerzone (which was not public at the time of the video) is only used for bootstrapping the manager host to run Docker.

You must also have Terraform and Docker installed.

Operation
---------

To setup the base site:

  # Define LINODE_TOKEN
  # Run the `manager.sh` command
  # Login to your Endpoint(s)
  
Once the machines are checked in as endpoints:

TBD
