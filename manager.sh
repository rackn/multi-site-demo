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
                             defaults to 'linode/centos7'
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
          * if cluster_prefix is set, then Regional Controllers, and LINDOE
            machine names will be prefixed with '<cluster-prefix>-REGION
            eg. '-c foo' produces a region controller named 'foo-us-west'
          * cluster_prefix is prepended to Manager Label and regional managers

          * SHANE's preferred start up:
            ./manager.sh -p -c sg -L global

EO_USAGE
}

install_tools() {
  local os=$(uname -s | tr '[:upper:]' '[:lower:]')
  if ! which drpcli >/dev/null 2>/dev/null ; then
    curl -s -o drpcli https://rebar-catalog.s3-us-west-2.amazonaws.com/drpcli/v4.2.0/amd64/$os/drpcli
    chmod +x drpcli
  fi
  if ! which jq >/dev/null 2>/dev/null ; then
    ln -s $(which drpcli) jq
  fi
  if ! which terraform >/dev/null 2>/dev/null ; then
    curl -s -o tf.zip https://releases.hashicorp.com/terraform/0.12.13/terraform_0.12.13_${os}_amd64.zip
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
PREP="false"
BASE="site-base-v4.2.2"           # "stable" is not fully available in the catalog
OPTS=""
MGR_LBL="global-manager"
MGR_PWD="r0cketsk8ts"
MGR_RGN="us-west"
MGR_IMG="linode/centos7"
MGR_TYP="g6-standard-2"
LINODE_TOKEN=${LINODE_TOKEN:-""}
SITES="us-central us-east us-west us-southeast"
DBG=0
LOOP_WAIT=15
VER_CONTENT="stable"
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
linode_token     = "$LINODE_TOKEN"
cluster_prefix   = "$PREFIX"
EO_MANAGER_VARS

echo "remove cached DRP token"
rm -f ~/.cache/drpcli/tokens/.rocketskates.token || true

(( $DBG )) && { echo "manager.tfvars set to:"; cat manager.tfvars; }

# verify our command line flags and validate site-base requested
AVAIL=$(ls multi-site/version_sets/site-base*.yaml | sed 's|^.*sets/\(.*\)\.yaml$|\1|g')
( echo "$AVAIL" | grep -q "$BASE" ) || xiterr 1 "Unsupported 'site-base', available values are: \n$AVAIL"

terraform init -no-color
terraform apply -no-color -auto-approve -var-file=manager.tfvars

export RS_ENDPOINT=$(terraform output drp_manager)
export RS_IP=$(terraform output drp_ip)

if [[ ! -e "rackn-catalog.json" ]]; then
  echo "Missing rackn-catalog.json... using the provided .ref version"
  cp rackn-catalog.ref rackn-catalog.json
else
  echo "catalog files exist - skipping"
fi

if [[ -f rackn-license.json ]]; then
  if [[ "$VALIDATE_LIC" == "true" ]] ; then
    echo "Checking Online License for rackn-license updates"
    LICENSE=$(cat rackn-license.json)
    LICENSEBASE=$(jq -r '.sections.profiles["rackn-license"].Params["rackn/license-object"]' <<< ${LICENSE})
    CONTACTID="$(jq -r .ContactId <<< ${LICENSEBASE})"
    OWNERID="$(jq -r .OwnerId <<< ${LICENSEBASE})"
    KEY="$(jq -r '.sections.profiles["rackn-license"].Params["rackn/license"]' <<< ${LICENSE})"
    VERSION="$(jq -r .Version <<< ${LICENSEBASE})"
    curl -X GET "https://1p0q9a8qob.execute-api.us-west-2.amazonaws.com/v40/license" \
      -H "rackn-contactid: ${CONTACTID}" \
      -H "rackn-ownerid: ${OWNERID}" \
      -H "rackn-endpointid: ${MGR_LBL}" \
      -H "rackn-key: ${KEY}" \
      -H "rackn-version: ${VERSION}" \
      -o rackn-license.json
    echo "License Verified"
  fi
else
  echo "MISSING REQUIRED RACKN-LICENSE FILE"
  exit 1
fi

echo "Building Multi-Site Content"

cd multi-site
_drpcli contents bundle ../multi-site-demo.json >/dev/null
cd ..
echo "Building Linode Content"
cd linode
_drpcli contents bundle ../linode.json >/dev/null
cd ..

echo "Script is idempotent - restart if needed!"
echo "Waiting for endpoint to be up.  export RS_ENDPOINT=$RS_ENDPOINT"
timeout 300 bash -c 'while [[ "$(curl -fsSLk -o /dev/null -w %{http_code} ${RS_ENDPOINT} 2>/dev/null)" != "200" ]]; do sleep 3; done' || false

echo "Setup Starting for endpoint export RS_ENDPOINT=$RS_ENDPOINT"
_drpcli contents upload rackn-license.json >/dev/null

_drpcli catalog item install manager --version=$VER_CONTENT >/dev/null

_drpcli contents upload linode.json >/dev/null
_drpcli prefs set defaultWorkflow discover-linode defaultBootEnv sledgehammer unknownBootEnv discovery >/dev/null

echo "Setting Catalog On Manager files"
_drpcli files upload linode.json to "rebar-catalog/linode/v1.1.0.json" >/dev/null
_drpcli files upload multi-site-demo.json to "rebar-catalog/multi-site-demo/v1.2.0.json" >/dev/null
_drpcli profiles set global set catalog_url to - >/dev/null <<< $RS_ENDPOINT/files/rebar-catalog/rackn-catalog.json
_drpcli files upload rackn-catalog.json as static-catalog.json >/dev/null
if [[ -f static-catalog.zip ]] ; then
  echo "Using custom static-catalog.zip ... upload to manager"
  _drpcli files upload static-catalog.zip >/dev/null
fi
# XXX: When moved into static-catalog.zip, then remove
if [[ ! -f v4.2.4.zip ]] ; then
  curl -s -o v4.2.4.zip https://rebar-catalog.s3-us-west-2.amazonaws.com/drp/v4.2.4.zip
fi
_drpcli files upload v4.2.4.zip to "rebar-catalog/drp/v4.2.4.zip"
# XXX: When moved into static-catalog.zip, then remove


echo "Start the manager workflow"
_drpcli contents upload multi-site-demo.json >/dev/null

echo "Setting the 'demo/cluster-prefix' param"
_drpcli profiles set global set demo/cluster-prefix to $PREFIX

_drpcli profiles set global set "linode/stackscript_id" to 548252 >/dev/null
_drpcli profiles set global set "linode/instance-image" to "linode/centos7" >/dev/null
_drpcli profiles set global set "linode/instance-type" to "g6-standard-1" >/dev/null
_drpcli profiles set global set "linode/token" to "$LINODE_TOKEN" >/dev/null
_drpcli profiles set global set "linode/root-password" to "r0cketsk8ts" >/dev/null
_drpcli profiles set global set "demo/cluster-count" to 0 >/dev/null
echo "drpcli profiles set global param network/firewalld-ports to ... "
drpcli profiles set global param "network/firewalld-ports" to '[
  "22/tcp", "8091/tcp", "8092/tcp", "6443/tcp", "8379/tcp", "8080/tcp", "8380/tcp", "10250/tcp"
]' >/dev/null

if [[ -f ~/.ssh/id_rsa.pub ]]; then
  echo "adding SSH key to global profile"
  drpcli profiles set global param "access-keys" to "{\"bootstrap\": \"$(cat ~/.ssh/id_rsa.pub)\"}"  >/dev/null
fi

echo "Upload Contexts if found"
raw=$(drpcli contexts list Engine=docker-context)
contexts=$(jq -r ".[].Name" <<< "${raw}")
i=0
for context in $contexts; do
  image=$(jq -r ".[$i].Image" <<< "${raw}")
  if [[ -f $context.tar ]] ; then
    echo "uploading $image for $context context"
    drpcli files upload $context.tar as "contexts/docker-context/$image"
  else
    echo "no local $context.tar file, will have to build in bootstrap"
  fi
  i=$(($i + 1))
done

echo "BOOTSTRAP export RS_ENDPOINT=$RS_ENDPOINT"

if ! drpcli machines exists "Name:$MGR_LBL" 2>/dev/null >/dev/null; then
  echo "Error - Boostrap Machine($MGR_LBL) was not created!"
  exit 1
else
  echo "Bootstrap machine exists as $MGR_LBL... starting bootstrap workflow"
  _drpcli machines workflow Name:"$MGR_LBL" "manager-bootstrap" >/dev/null
fi

echo "upload edge-lab"
_drpcli catalog item install edge-lab --version=tip >/dev/null

echo "Waiting for Manager to finish bootstrap"
_drpcli machines wait "Name:$MGR_LBL" Stage "complete-nobootenv" 360

for mc in $SITES;
do
  if ! _drpcli machines exists Name:$mc 2>/dev/null >/dev/null; then
    reg=$mc
    [[ -n "$PREFIX" ]] && reg=$(echo $mc | sed 's/'${PREFIX}'-//g')
    echo "Creating $mc"
    echo "drpcli machines create \"{\"Name\":\"${mc}\", ... "
    drpcli machines create "{\"Name\":\"${mc}\", \
      \"Workflow\":\"site-create\", \
      \"Description\":\"Edge DR Server\", \
      \"Params\":{\"linode/region\": \"${reg}\", \"network\firewalld-ports\":[\"22/tcp\",\"8091/tcp\",\"8092/tcp\"] }, \
      \"Meta\":{\"BaseContext\":\"runner\", \"icon\":\"cloud\"}}" >/dev/null
    sleep $LOOP_WAIT
  else
    echo "machine $mc already exists"
  fi
done

if [[ "$PREP" == "true" ]]
then
  echo "VersionSet prep was requested."
  echo "Waiting for regional endpoints to reach 'complete-nobootenv'"
  # wait for the regional controllers to finish up before trying to do VersionSets
  for mc in $SITES
  do
    if drpcli machines exists Name:$mc > /dev/null; then
      _drpcli machines wait Name:$mc Stage "complete-nobootenv" 240 &
    fi
  done

  wait
  echo "Regional endpoints done, starting VersionSet prep on global manager."

  # start at 1, do BAIL iterations of WAIT length (10 mins by default)
  LOOP=1
  BAIL=120
  WAIT=5

  _drpcli extended -l endpoints update $MGR_LBL '{"VersionSets":["license","manager-ignore","'$BASE'"]}'
  _drpcli extended -l endpoints update $MGR_LBL '{"Apply":true}'

  # need to "wait" - monitor that we've finish applying this ...
  # check if apply set to true
  if [[ "$(drpcli extended -l endpoints show $MGR_LBL  | jq -r '.Apply')" == "true" ]]
  then
    BRKMSG="Actions have been completed on global manager..."

    while (( LOOP <= BAIL ))
    do
      COUNTER=$WAIT
      # if Actions object goes away, we've drained the queue of work
      [[ "$(drpcli extended -l endpoints show $MGR_LBL | jq -r '.Actions')" == "null" ]] && { echo $BRKMSG; break; }
      printf "Waiting for VersionSet Actions to complete ... (sleep $WAIT seconds ) ... "
      while (( COUNTER ))
      do
        sleep $WAIT
        printf "%s " $COUNTER
        (( COUNTER-- ))
      done
      (( LOOP++ ))
      echo ""
    done
    (( TOT = BAIL * WAIT ))

    if [[ $LOOP == $BAIL ]]
    then
      xiterr 1 "VersionSet apply actions FAILED to complete in $TOT seconds."
    fi
  else
    echo "!!! Apply was not found to be 'true', check Endpoints received VersionSets appropriately."
  fi
fi # end if PREP

echo ""
echo ">>>"
echo ">>> Cluster Prefix is set to:  $PREFIX"
echo ">>>"
echo ">>> DONE !!! Example export for Endpoint:"
echo ">>>"
echo "export RS_ENDPOINT=$RS_ENDPOINT"
echo ""
