#!/usr/bin/env bash
# RackN Copyright 2019
# Build Manager Demo

export PATH=$PATH:$PWD

xiterr() { [[ $1 =~ ^[0-9]+$ ]] && { XIT=$1; shift; } || XIT=1; printf "FATAL: $*\n"; exit $XIT; }

usage() {
  local _l=$(echo $0 |wc -c | awk ' { print $NF } ')
  (( _l-- ))
  PAD=$(printf "%${_l}s" " ")

  cat <<EO_USAGE

  $0 [ -d ] [ -p ] [ -b site-base-VER ] [ -c cluster_prefix ] [ -S sites ] \\
  $PAD [ -L label ] [ -P password ] [ -R region ] [ -I image ] [ -T type ] \\
  $PAD [ -v version_content ]

  WHERE:
          -p                 prep manager (lowercase 'p')
                             set the global manager to apply VersionSets
                             automatically - by default specifying the
                             $BASE VersionSet, if there is an
                             additional option to 'prep-manager', that
                             will be used in place of '$BASE'
          -b site-base-VER   Sets the VER (eg 'v4.2.2') for site-base
                             implies/sets '-p' if not specified
          -c cluster_prefix  sets cluster members with a prefix name for
                             uniqueness
          -L label           set Manager Label (endpoint name)
                             defaults to 'global-manager'
                             NOTE: '-c cluster_prefix', added to MGR too
          -P password        set Manager Password for root user
                             defaults to 'r0cketsk8ts'
          -R region          set Manager Region to be installed in
                             defaults to 'us-west'
          -I image           set Manager Image name as supported by Linode
                             defaults to 'linode/centos8'
          -T type            set Manager Type of virtual machine
                             defaults to 'g6-standard-2'
          -S sites           list of Sites to build regional controllers in
                             (comma, semi-colon, colon, dash, underscore, or
                             space separated list - normal shell rules apply
          -v version         specify what DRP content version to install, by
                             default install "stable" version
          -d                 enable debugging mode
          -x                 do NOT validate license

  NOTES:  * if '-b site-base-VER' specified, '-p' (prep-manager) is implied
          * Regions: $SITES
          * if cluster_prefix (must be 3+ chars) is set, then Regional Controllers, and LINDOE
            machine names will be prefixed with '<cluster-prefix>-REGION
            eg. '-c foo' produces a region controller named 'foo-us-west'
          * cluster_prefix is prepended to Manager Label and regional managers

          * SHANE's preferred start up:
            ./manager.sh -p -c syg -L global

EO_USAGE
}

install_tools() {
  local os=$(uname -s | tr '[:upper:]' '[:lower:]')
  if ! which drpcli >/dev/null 2>/dev/null ; then
    curl -s -o drpcli https://rebar-catalog.s3-us-west-2.amazonaws.com/drpcli/v4.3.3/amd64/$os/drpcli
    chmod +x drpcli
  fi
  if ! which jq >/dev/null 2>/dev/null ; then
    ln -s $(which drpcli) jq
  fi
  if ! which terraform >/dev/null 2>/dev/null ; then
    curl -s -o tf.zip https://releases.hashicorp.com/terraform/0.13.0/terraform_0.13.0_${os}_amd64.zip
    unzip tf.zip
    rm -f tf.zip
    chmod +x terraform
  fi
}

check_tools() {
  local tools=$*
  local tool=""
  local xit=""
  for tool in $tools; do
    if which $tool > /dev/null; then
      echo "Found required tool:  $tool"
    else
      echo ">>> MISSING <<< required dependency tool:  $tool"
      xit=fail
    fi
  done


  [[ -n $xit ]] && exit 1 || echo "All necessary tools found."
}

_drpcli() {
  (( $DBG )) && >&2 echo ">>> DBG: drpcli $*"
  drpcli $*
}

set -e

###
#  some defaults - note that Manager defaults are written to a tfvars
#  file which is used to set the manager.tf variables values
#
#  WARNING:  no input checking is performed on the values at this time
#            you must insure your input is sane and matches real values
#            that can be set for the terraform provider (linode)
###
PREP="true"
BASE="site-base-tip"           # "stable" is not fully available in the catalog
OPTS=""
MGR_LBL="global-manager"
MGR_PWD="digitalrebar"
MGR_RGN="us-west"
MGR_IMG="linode/centos8"
MGR_TYP="g6-standard-8"
SSH_KEY="$(cat ~/.ssh/id_rsa.pub)"
LINODE_TOKEN=${LINODE_TOKEN:-""}
ALLSITES="us-west us-east us-central us-southeast"
SITES="$ALLSITES"

DBG=0
LOOP_WAIT=15
VER_CONTENT="tip"
VALIDATE_LIC="true"

while getopts ":dxpb:c:t:L:P:R:I:T:S:v:u" CmdLineOpts
do
  case $CmdLineOpts in
    x) VALIDATE_LIC="false"   ;;
    p) PREP="true"            ;;
    b) BASE=${OPTARG}
       PREP="true"            ;;
    c) PREFIX=${OPTARG}       ;;
    t) LINODE_TOKEN=${OPTARG} ;;
    L) MGR_LBL=${OPTARG}      ;;
    P) MGR_PWD=${OPTARG}      ;;
    R) MGR_RGN=${OPTARG}      ;;
    I) MGR_IMG=${OPTARG}      ;;
    T) MGR_TYP=${OPTARG}      ;;
    S) STS=${OPTARG}          ;;
    v) VER_CONTENT=${OPTARG}  ;;
    d) DBG=1; set -x          ;;
    u) usage; exit 0          ;;
    \?)
      echo "Incorrect usage.  Invalid flag '${OPTARG}'."
      usage
      exit 1
      ;;
  esac
done

# if -S sites called, transform patterns to space separated list
[[ -n "$STS" ]] && SITES=$(echo $STS | tr '[ ,;:-:]' ' ' | sed 's/  //g')

check_tools unzip curl gzip
install_tools
check_tools jq drpcli terraform

if [[ "$LINODE_TOKEN" == "" ]]; then
    echo "you must export LINODE_TOKEN=[your token]"
    exit 1
else
    echo "Ready, LINODE_TOKEN set!"
fi

# create a random cluster prefix if one was not specified
[[ -z "$PREFIX" ]] && PREFIX=$(mktemp -u XXXXXX)

echo ">>>"
echo ">>> Cluster Prefix has been set to:  $PREFIX"
echo ">>>"

# add prefix to manager_label and SITES
MGR_LBL="$PREFIX-$MGR_LBL"

for site in $SITES
do
  s+="$PREFIX-$site "
done
SITES="$s"
(( $DBG )) && echo "Manager name set to:  $MGR_LBL"
(( $DBG )) && echo "Sites set to:  $SITES"

# write terraform manager.tfvars file - setting our Manager characteristics
# manager.sh relies on 'manaer.tfvars' - to parse for our MGR details
cat <<EO_MANAGER_VARS > manager.tfvars
# values added by manager.sh script and will be auto-regenerated
manager_label    = "$MGR_LBL"
manager_password = "$MGR_PWD"
manager_region   = "$MGR_RGN"
manager_image    = "$MGR_IMG"
manager_type     = "$MGR_TYP"
ssh_key          = "$SSH_KEY"
linode_token     = "$LINODE_TOKEN"
cluster_prefix   = "$PREFIX"
EO_MANAGER_VARS

echo "remove cached DRP token"
rm -f ~/.cache/drpcli/tokens/.rocketskates.token || true
unset RS_TOKEN
unset RS_LOCAL_PROXY

(( $DBG )) && { echo "manager.tfvars set to:"; cat manager.tfvars; }

# verify our command line flags and validate site-base requested
AVAIL=$(ls multi-site/version_sets/site-base*.yaml | sed 's|^.*sets/\(.*\)\.yaml$|\1|g')
( echo "$AVAIL" | grep -q "$BASE" ) || xiterr 1 "Unsupported 'site-base', available values are: \n$AVAIL"

terraform init -no-color
terraform apply -no-color -auto-approve -var-file=manager.tfvars

export RS_ENDPOINT=$(terraform output drp_manager)
export RS_IP=$(terraform output drp_ip)
export RS_KEY="rocketskates:${MGR_PWD}"
echo "Terraform Finished, expecting: export RS_ENDPOINT=${RS_ENDPOINT} && export RS_KEY=${RS_KEY}"
echo "Script is idempotent - restart if needed!"

echo "Waiting for API to be available"
timeout 360 bash -c 'while [[ "$(curl -fsSL -o /dev/null -w %{http_code} http://$RS_IP:8091)" != "200" ]]; do sleep 3; done' || false

attempt=1
while (( $attempt < 50 )); do
  sleep 2
  if _drpcli -P ${MGR_PWD} info get > /dev/null ; then
    echo "no change: password already set to $MGR_PWD"
    break
  fi
  attempt=$(( attempt + 1 ))
done
if [[ $attempt -gt 49 ]]; then
  echo "ERROR: could not login"
  exit 1
fi

export RS_TOKEN="$(_drpcli users token "rocketskates" | jq -r .Token)"

if [[ -f rackn-license.json ]]; then
  if [[ "$VALIDATE_LIC" == "true" ]] ; then
    echo "Checking Online License for rackn-license updates"
    LICENSE=$(cat rackn-license.json)
    LICENSEBASE=$(jq -r '.sections.profiles["rackn-license"].Params["rackn/license-object"]' <<< ${LICENSE})
    CONTACTID="$(jq -r .ContactId <<< ${LICENSEBASE})"
    OWNERID="$(jq -r .OwnerId <<< ${LICENSEBASE})"
    KEY="$(jq -r '.sections.profiles["rackn-license"].Params["rackn/license"]' <<< ${LICENSE})"
    VERSION="$(jq -r .Version <<< ${LICENSEBASE})"
    # first, add the leaf endpoints
    endpoints=$(cat rackn-license.json | jq -r '.sections.profiles["rackn-license"].Params["rackn/license-object"].Endpoints')
    matchany=$(jq -r "contains([\"MatchAny\"])" <<< $endpoints)
    updated=false
    for mc in $ALLSITES; do
      if [[ $SITES == 'none' ]]; then
        echo "Not building any sites."
        break
      fi
      mc="site-$mc"
      licensed=$(jq -r "contains([\"$mc\"])" <<< $endpoints)
      if [[ "${licensed}" == "true" || "${matchany}" == "true" ]]; then
        echo "  endpoint $mc found in license!"
      else
        updated=true
        echo "  adding $mc to license"
        curl -X GET "https://1p0q9a8qob.execute-api.us-west-2.amazonaws.com/v40/license" \
          -H "rackn-contactid: ${CONTACTID}" \
          -H "rackn-ownerid: ${OWNERID}" \
          -H "rackn-endpointid: ${mc}" \
          -H "rackn-key: ${KEY}" \
          -H "rackn-version: ${VERSION}" \
          >/dev/null
      fi
    done
    if [[ "$updated" == "true" ]] ; then
      cp rackn-license.json rackn-license.old
      curl -X GET "https://1p0q9a8qob.execute-api.us-west-2.amazonaws.com/v40/license" \
        -H "rackn-contactid: ${CONTACTID}" \
        -H "rackn-ownerid: ${OWNERID}" \
        -H "rackn-endpointid: ${MGR_LBL}" \
        -H "rackn-key: ${KEY}" \
        -H "rackn-version: ${VERSION}" \
        -o rackn-license.json
      echo "License Verified"
    fi
  fi
else
  echo "MISSING REQUIRED RACKN-LICENSE FILE"
  exit 1
fi

if [[ "$(_drpcli profiles get global param access-keys-global)" == "null" ]]; then
   echo "Adding SSH_KEY"
  _drpcli profiles add "global" param "access-keys-global" to - > /dev/null << EOF
{
   "${MGR_LBL}":"${SSH_KEY}"
}
EOF
else
   echo "SSH_KEY already installed"
fi

echo "Building Multi-Site Content"

cd multi-site

# upload aws & google credentials
mkdir profiles || true
if [[ -f ~/.aws/credentials ]]; then
    echo "  Adding AWS profile for cloud-wrap"
    tee profiles/aws-credentials.yaml >/dev/null << EOF
---
Name: "aws"
Description: "AWS Credentials"
Params:
  "cloud/provider": "aws"
  "aws/secret-key": $(awk '/aws_secret_access_key/{ print $3}' ~/.aws/credentials)
  "aws/access-key-id": $(awk '/aws_access_key_id/{ print $3}' ~/.aws/credentials)
  "rsa/key-user": "ec2-user"
Meta:
  color: "blue"
  icon: "amazon"
  title: "generated"
EOF
else
  echo "  no AWS credentials, skipping"
fi

# upload aws & google credentials
google=$(ls ~/.gconf/desktop/*.json || echo "none")
if [[ -f $google ]]; then
    echo "  Adding Google profile for cloud-wrap"
    gconf=$(cat $google) > /dev/null
    tee profiles/google-credentials.json >/dev/null << EOF
{
  "Name": "google",
  "Description": "GCE Credentials",
  "Params": {
    "cloud/provider": "google",
    "google/project-id": "$(jq -r .project_id <<< "$gconf")",
    "rsa/key-user": "rob",
    "google/credential": $(cat $google)
  },
  "Meta": {
    "color": "blue",
    "icon": "google",
    "title": "generated"
  }
}
EOF
else
  echo "  no Google credentials, skipping"
fi


if [[ $DO_TOKEN ]]; then
  echo "  upload digital ocean credentials"
  tee profiles/digitalocean.yaml >/dev/null << EOF
---
Name: "digitalocean"
Description: "Digital Ocean Credentials"
Params:
  "cloud/provider": "digitalocean"
  "digitalocean/token": "$DO_TOKEN"
Meta:
  color: "green"
  icon: "digital ocean"
  title: "generated"
EOF
else
  echo "  Skipping Digital Ocean, no token"
fi

echo "  upload linode credentials"
tee profiles/linode.yaml >/dev/null << EOF
---
Name: "linode"
Description: "Linode Credentials"
Params:
  "cloud/provider": "linode"
  "linode/token": "$LINODE_TOKEN"
  "linode/instance-image": "linode/centos8"
  "linode/instance-type": "g6-standard-8"
  "linode/root-password": "r0cketsk8ts"
Meta:
  color: "blue"
  icon: "linode"
  title: "generated"
EOF


echo "Setting the cluster-prefix profile ($PREFIX)"
# upload linode credentials
tee profiles/$PREFIX.yaml >/dev/null << EOF
---
Name: "$PREFIX"
Meta:
  color: "blue"
  icon: "user md"
  title: "generated"
EOF

_drpcli contents bundle ../multi-site-demo.json >/dev/null
cd ..

echo "Uploading content"
_drpcli contents upload rackn-license.json >/dev/null
items="drp-community-content task-library multi-site-demo edge-lab dev-library cloud-wrappers"
for c in $items; do
  if [[ -f $c.json ]] ; then
     echo "  ALERT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
     echo "  overriding catalog with local content $c.json"
     _drpcli contents upload $c.json >/dev/null
  fi
  if [[ -f $c.yaml ]] ; then
     echo "  ALERT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
     echo "  overriding catalog with local content $c.yaml"
     _drpcli contents upload $c.yaml >/dev/null
  fi
done

echo "Setting Catalog On Manager files"

msdv=$(cat multi-site-demo.json | jq -r .meta.Version)
_drpcli files upload multi-site-demo.json to "rebar-catalog/multi-site-demo/${msdv}.json" >/dev/null

rlv=$(cat rackn-license.json | jq -r .meta.Version)
_drpcli files upload rackn-license.json to "rebar-catalog/rackn-license/${rlv}.json"  >/dev/null

echo "uploading site specific context packs"
for s in $ALLSITES
do
  cd "${s}"
  echo "  bundle $s"
  _drpcli contents bundle ../${s}.json > /dev/null
  cd ..
  v=$(cat ${s}.json | jq -r .meta.Version)
  _drpcli files upload ${s}.json to "rebar-catalog/site-${s}/${v}.json" >/dev/null
done

echo "Building catalog"
./catalogger.py --items drp,task-library,drp-community-content,docker-context,edge-lab,dev-library,cloud-wrappers > rackn-catalog.json
_drpcli profiles set global param catalog_url to - >/dev/null <<< $RS_ENDPOINT/files/rebar-catalog/rackn-catalog.json
_drpcli profiles set global param "dr-server/initial-password" to "${MGR_PWD}" >/dev/null
_drpcli files upload rackn-catalog.json as "rebar-catalog/static-catalog.json" >/dev/null

#if [[ -f static-catalog.zip ]] ; then
#  echo "Using custom static-catalog.zip ... upload to manager"
#  _drpcli files upload static-catalog.zip >/dev/null
#fi
# XXX: When moved into static-catalog.zip, then remove
#if [[ ! -f v4.2.15.zip ]] ; then
#  curl -s -o v4.2.15.zip https://rebar-catalog.s3-us-west-2.amazonaws.com/drp/v4.2.15.zip
#fi
#_drpcli files upload v4.2.15.zip to "rebar-catalog/drp/v4.2.15.zip"
# XXX: When moved into static-catalog.zip, then remove


if [[ "$(_drpcli profiles get global param "demo/cluster-prefix")" != "$PREFIX" ]]; then
  _drpcli profiles set global set "demo/cluster-prefix" to $PREFIX >/dev/null || true
fi
echo "drpcli profiles set global param network/firewall-ports to ... "
drpcli profiles set global param "network/firewall-ports" to '[
  "22/tcp", "8091/tcp", "8092/tcp", "6443/tcp", "8379/tcp", "8080/tcp", "8380/tcp", "10250/tcp"
]' >/dev/null


echo "BOOTSTRAP export RS_ENDPOINT=$RS_ENDPOINT && export RS_KEY=${RS_KEY}"

echo "Waiting for Manager to finish bootstrap"
_drpcli prefs set manager true  >/dev/null
_drpcli machines wait "Name:$MGR_LBL" WorkflowComplete true 360

# after bootstrap, install more stuff
items="cloud-wrappers multi-site-demo dev-library ux-views"
for c in $items; do
  if [[ -f $c.json ]] ; then
     echo "ALERT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
     echo "overriding catalog with local content $c"
     _drpcli contents upload $c.json >/dev/null
  else
     _drpcli catalog item install $c --version=tip >/dev/null
  fi
done

# re-run the bootstrap
_drpcli machines update "Name:$MGR_LBL" '{"Locked":false}'  >/dev/null
_drpcli machines update "Name:$MGR_LBL" '{"Workflow":""}' >/dev/null
_drpcli machines workflow "Name:$MGR_LBL" "bootstrap-manager" >/dev/null

echo "Waiting for Manager to reach catalog state in (re)bootstrap"
_drpcli machines wait "Name:$MGR_LBL" Stage "bootstrap-manager" 600

_drpcli prefs set defaultWorkflow discover-base defaultBootEnv sledgehammer unknownBootEnv discovery  >/dev/null

# This is to attempt to reeval stages
echo "Hack to reset stages"
_drpcli contents show cloud-wrappers | _drpcli contents upload - >/dev/null
_drpcli contents show multi-site-demo --key=/tmp/keyfile.json | _drpcli contents upload --key=/tmp/keyfile.json - >/dev/null

echo "Building Context Files version_set"
tee contexts.yaml >/dev/null << EOF
---
Id: contexts
Description: "Docker Contexts"
Apply: true
Meta:
  icon: file
  color: black
  type: file
Files:
EOF
CONTEXTS="ansible runner terraform"
for c in $CONTEXTS;
do
  sum="$(drpcli files exists contexts/docker-context/digitalrebar-context-$c | awk '/: / {print $2}')"
  echo "  - Path: \"files/contexts/docker-context/digitalrebar-context-$c\"" >> contexts.yaml
  echo "    Sha256Sum: \"$sum\"" >> contexts.yaml
  echo "    Source: \"{{.ProvisionerURL}}/files/contexts/docker-context/digitalrebar-context-$c\"" >> contexts.yaml
  echo "    Explode: false" >> contexts.yaml
done
if _drpcli version_sets exists contexts ; then
  _drpcli version_sets update contexts - < contexts.yaml > /dev/null
else
  _drpcli version_sets create - < contexts.yaml > /dev/null
fi

echo "Building ALL SITES (will not deploy them all)"
for reg in $ALLSITES;
do
  mc="${PREFIX}-$reg"
  case $reg in
    us-east) color="brown" ;;
    us-central) color="green" ;;
    us-west) color="purple" ;;
    us-southeast) color="orange" ;;
    *) color="black"
  esac
  if ! drpcli users exists $mc 2>/dev/null >/dev/null; then
    drpcli users create "{\"Name\":\"$mc\", \"Roles\":[\"superuser\"]}" > /dev/null
    drpcli users password $mc $MGR_PWD > /dev/null
  else
    echo "skipping: user $mc already exists"
  fi
  if ! _drpcli machines exists Name:$mc 2>/dev/null >/dev/null; then
    echo "Creating $mc ($color)"
    echo "drpcli machines create \"{\"Name\":\"${mc}\", ... "
    drpcli machines create "{\"Name\":\"${mc}\", \
      \"Workflow\":\"discover-base\", \
      \"BootEnv\":\"sledgehammer\", \
      \"Description\":\"Edge DR Server\", \
      \"Profiles\":[\"$PREFIX\",\"linode\"], \
      \"Params\":{\"demo/cluster-color\": \"${color}\", \"dr-server/install-drpid\": \"site-${reg}\", \"dr-server/initial-user\": \"${mc}\", \"linode/region\": \"${reg}\", \"network/firewall-ports\":[\"22/tcp\",\"8091/tcp\",\"8092/tcp\"] }, \
      \"Meta\":{\"BaseContext\":\"drpcli-runner\", \"color\":\"${color}\", \"icon\":\"cloud\"}}" >/dev/null
    sleep $LOOP_WAIT
  else
    echo "machine $mc already exists"
  fi
done

for mc in $SITES;
do
  if [[ $SITES == "${PREFIX}-none" ]]; then
    echo "Not building any sites."
    break
  fi
  if _drpcli machines exists Name:$mc 2>/dev/null >/dev/null; then
    _drpcli machines workflow Name:$mc cloud-site-create >/dev/null
  else
    echo "machine $mc does not exist"
  fi
done

if [[ "$PREP" == "true" && "$SITES" != "${PREFIX}-none" ]]
then
  echo "VersionSet prep was requested."
  echo "Waiting for regional endpoints to reach 'complete-nobootenv'"
  # wait for the regional controllers to finish up before trying to do VersionSets
  for mc in $SITES
  do
    if _drpcli machines exists Name:$mc ; then
      _drpcli machines wait Name:$mc WorkflowComplete true 600 &
    fi
  done

  wait

  # Manager should have a catalog in good state before running version sets
  _drpcli machines wait "Name:$MGR_LBL" WorkflowComplete true 360

  echo "Starting Endpoint Setup"
  for mc in $SITES
  do
    reg=$mc
    [[ -n "$PREFIX" ]] && reg=$(echo $mc | sed 's/'${PREFIX}'-//g')
    echo "  $mc completed bootstrap (will be site-$reg)"
    if drpcli endpoints exists "site-$reg" > /dev/null; then
      echo "  Setting VersionSets $BASE on site-$reg"
      _drpcli endpoints update "site-$reg" "{\"VersionSets\":[\"license\",\"contexts\",\"$BASE\",\"site-$reg\"]}" > /dev/null
      _drpcli endpoints update "site-$reg" '{"Apply":true}' > /dev/null
    fi
  done

  # start at 1, do BAIL iterations of WAIT length (10 mins by default)
  LOOP=1
  BAIL=120
  WAIT=5

  # need to "wait" - monitor that we've finish applying this ...
  # check if apply set to true
  echo "Starting Endpoint bootstrap"
  for mc in $SITES
  do
    reg=$mc
    [[ -n "$PREFIX" ]] && reg=$(echo $mc | sed 's/'${PREFIX}'-//g')
    if [[ "$(drpcli endpoints show site-$reg  | jq -r '.Apply')" == "true" ]]
    then
      BRKMSG="Actions have been completed on site-$reg ..."

      while (( LOOP <= BAIL ))
      do
        COUNTER=$WAIT
        # if Actions object goes away, we've drained the queue of work
        [[ "$(drpcli endpoints show site-$reg | jq -r '.Actions')" == "null" ]] && { echo $BRKMSG; break; }
        printf "  Waiting for VersionSet Actions to complete ... (sleep $WAIT seconds ) ... "
        while (( COUNTER ))
        do
          sleep $WAIT
          printf "%s " $COUNTER
          (( COUNTER-- ))
        done
        (( LOOP++ ))
      done
      (( TOT = BAIL * WAIT ))

      if [[ $LOOP == $BAIL ]]
      then
        xiterr 1 "VersionSet apply site-$reg actions FAILED to complete in $TOT seconds."
      fi
    else
      echo "!!! Apply was not found to be 'true', check Endpoints received VersionSets appropriately."
    fi
    if _drpcli machines exists "Name:site-$reg" ; then
      echo "  Setting bootstrap edge for site-$reg"
      _drpcli machines meta set Name:site-$reg key icon val sitemap > /dev/null
      _drpcli machines workflow Name:site-$reg bootstrap-edge  > /dev/null
    else
      echo "  WARNING: expected site-$reg does not exist.  Complete bootstrap manually!!"
    fi
  done
fi # end if PREP

echo ""
echo ">>>"
echo ">>> Cluster Prefix is set to:  $PREFIX"
echo ">>>"
echo ">>> DONE !!! Example export for Endpoint:"
echo ">>>"
echo "export RS_ENDPOINT=$RS_ENDPOINT && export RS_KEY=${RS_KEY}"
echo ""
