Multi-Site Manager Demo
=======================
_By RackN, October 2019_


This content is used to RackN Showcase Multi-Site Management and Context features.  It is designed to be used with Linode; however, the context
can be easily adapted for uses.

Prerequists
-----------

The following files are required in the project root directory:
   * drpcli (v4.1 or later)
   * dangerzone plugin binary (available by request from RackN for trial purposes)
   * RackN License file (you can generate via self-service)
   * export LINODE_TOKEN=[your access token]

You can bypass the dangerzone plugin requirement by installing Docker on your host by hand.  Dangerzone (which was not public at the time of the video) is only used for bootstrapping the manager host to run Docker.

You must also have Terraform and Docker installed.

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
   1. in v4.1 there is a known issue with contexts being lost after the DRP token is reset (this is not surprising since all tokens are invalidated)
      1. for all the edit site machines, clear the `Context` and `Meta.BaseContext` values.  UX will show Context is "" (or an empty circle)
      1. for all the edit site machines, set `Meta.BaseContext` to `runner`
   1. set the `site-expand` workflow

There is a tricky hack to install k3s:

   1. the `k3s-demo` profile is part of the manager content pack
   1. the `site-expand` workflow adds the `k3s-demo` profile to each edge site via the API
   1. the krib demo will work locally on the local profile - it is NOT mirrored by the manager in v4.1.
   1. since the profile also exists at the manager level the object the single-pane-of-glass updates will work.
   1. this will be addressed in a more elegant way in future versions.