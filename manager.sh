#!/usr/bin/env bash
# RackN Copyright 2019
# Build Manager Demo

export PATH=$PATH:$PWD

xiterr() { [[ $1 =~ ^[0-9]+$ ]] && { XIT=$1; shift; } || XIT=1; printf "FATAL: $*\n"; exit $XIT; }

usage() {
  echo "USAGE:  $0 [ -p ] [ -b site-base-VER ]"
  echo "           [ -L label ] [ -P password ] [ -R region ] [ -I image ] [ -T type ]"
  echo "WHERE:"
  echo "          -p                prep manager (lowercase 'p')"
  echo "                            set the global manager to apply VersionSets"
  echo "                            automatically - by default specifying the"
  echo "                            site-base-stable VersionSet, if there is an"
  echo "                            additional option to 'prep-manager', that"
  echo "                            will be used in place of 'site-base-stable'"
  echo ""
  echo "           -L label         set Manager Label (endpoint name)"
  echo "                            defaults to 'rackn-manager-demo'"
  echo "           -P password      set Manager Password for root user"
  echo "                            defaults to 'r0cketsk8ts'"
  echo "           -R region        set Manager Region to be installed in"
  echo "                            defaults to 'us-west'"
  echo "           -I image         set Manager Image name as supported by Linode"
  echo "                            defaults to 'linode/centos7'"
  echo "           -T type          set Manager Type of virtual machine"
  echo "                            defaults to 'g6-standard-2'"
  echo ""
  echo ""
  echo "          -b site-base-VER  (optional) VersionSet to use for the site-base"
  echo ""
  echo "NOTES:  * 'prep-manager site-base-v4.1.2' would replace the 'site-base-stable'":
  echo "          version set with the v4.1.2 version"
  echo ""
  echo "        * if 'site-base-VER' is specified, 'prep-manager' must also"
  echo ""
	echo "        * Regions: ca-central, us-central, us-west, us-southeast, us-east"
  echo ""
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

set -e

check_tools jq drpcli terraform curl docker dangerzone

###
#  some defaults - note that Manager defaults are written to a tfvars
#  file which is used to set the manager.tf variables values
#
#  WARNING:  no input checking is performed on the values at this time
#            you must insure your input is sane and matches real values
#            that can be set for the terraform provider (linode)
###
PREP=false
BASE="site-base-stable"
OPTS=""
MGR_LBL="rackn-manager-demo"
MGR_PWD="r0cketsk8ts"
MGR_RGN="us-west"
MGR_IMG="linode/centos7"
MGR_TYP="g6-standard-2"

while getopts ":pb:t:L:P:R:I:T:u" CmdLineOpts
do
  case $CmdLineOpts in
    p) PREP="true"            ;;
    b) BASE=${OPTARG}         ;;
    t) LINODE_TOKEN=${OPTARG} ;;
    L) MGR_LBL=${OPTARG}      ;;
    P) MGR_PWD=${OPTARG}      ;;
    R) MGR_RGN=${OPTARG}      ;;
    I) MGR_IMG=${OPTARG}      ;;
    T) MGR_TYP=${OPTARG}      ;;
    u) usage; exit 0          ;;
    \?)
      echo "Incorrect usage.  Invalid flag '${OPTARG}'."
      usage
      exit 1
      ;;
  esac
done
variable "manager_label" {
  type      = string
  default   = "rackn-manager-demo"
}

# write terraform manager.tfvars file - setting our Manager characteristics
cat <<EO_MANAGER_VARS > manager.tfvars
manager_label = $MGR_LBL
manager_password = $MGR_PWD
manaager_region = $MGR_RGN
manager_image = $MGR_IMG
manager_type = $MGR_TYP
EO_MANAGER_VARS

# verify our command line flags and validate site-base requested
AVAIL=$(ls multi-site/version_sets/site-base*.yaml | sed 's|^.*sets/\(.*\)\.yaml$|\1|g')
( echo "$AVAIL" | grep -q "$BASE" ) || xiterr 1 "Unsupportes 'site-base', availalbe values are: \n$AVAIL"

if [[ "$LINODE_TOKEN" == "" ]]; then
    echo "you must export LINODE_TOKEN=[your token]"
    exit 1
else
    echo "ready, LINODE_TOKEN set!"
fi

terraform init -no-color
terraform apply -no-color -auto-approve --var="linode_token=$LINODE_TOKEN"

export RS_ENDPOINT=$(terraform output drp_manager)
export RS_IP=$(terraform output drp_ip)

if [[ ! -e "rackn-catalog.json" ]]; then
  echo "Missing rackn-catalog.json... using the provided .ref version"
  cp rackn-catalog.ref rackn-catalog.json
else
  echo "catalog files exist - skipping"
fi

if [[ ! -e "v4drp-install.zip" ]]; then
  curl -sfL -o v4drp-install.zip https://s3-us-west-2.amazonaws.com/rebar-catalog/drp/v4.1.0.zip
  curl -sfL -o install.sh get.rebar.digital/tip
else
  echo "install files exist - skipping"
fi

echo "Building Multi-Site Content"
cd multi-site
drpcli contents bundle multi-site-demo.json
mv multi-site-demo.json ..
cd ..

echo "Script is idempotent - restart if needed!"
echo "Waiting for endpoint export RS_ENDPOINT=$RS_ENDPOINT"
echo ">>> NOTE: 'Failed to connect ...' messages are normal during system bring up."
sleep 10
timeout 300 bash -c 'while [[ "$(curl -fsSLk -o /dev/null -w %{http_code} ${RS_ENDPOINT})" != "200" ]]; do sleep 5; done' || false

echo "FIRST, reset the tokens! export RS_ENDPOINT=$RS_ENDPOINT"
# extract secretes from config
baseTokenSecret=$(jq -r -c -M .sections.version_sets.credential.Prefs.baseTokenSecret multi-site-demo.json)
systemGrantorSecret=$(jq -r -c -M .sections.version_sets.credential.Prefs.systemGrantorSecret multi-site-demo.json)
drpcli prefs set baseTokenSecret "${baseTokenSecret}" systemGrantorSecret "${systemGrantorSecret}"

echo "Setup Starting for endpoint export RS_ENDPOINT=$RS_ENDPOINT"
drpcli contents upload rackn-license.json
drpcli bootenvs uploadiso sledgehammer &

drpcli catalog item install drp-community-content --version=tip
drpcli catalog item install task-library --version=tip
drpcli catalog item install manager --version=tip

echo "Building Linode Content"
cd linode
drpcli contents bundle ../linode.json
cd ..
drpcli contents upload linode.json
drpcli prefs set defaultWorkflow discover-linode unknownBootEnv discovery

drpcli files upload linode.json to "rebar-catalog/linode/v1.0.0.json"
drpcli plugins runaction manager buildCatalog
drpcli files upload rackn-catalog.json to "rebar-catalog/rackn-catalog.json"
drpcli contents upload $RS_ENDPOINT/files/rebar-catalog/rackn-catalog.json

# cache the catalog items on the DRP Server
drpcli profiles set global set catalog_url to - <<< $RS_ENDPOINT/files/rebar-catalog/rackn-catalog.json
if [[ ! -e "static-catalog.zip" ]]; then
  echo "downloading static from s3"
  curl --compressed -o static-catalog.zip https://rackn-private.s3-us-west-2.amazonaws.com/static-catalog.zip
else
  echo "using found static-catalog.zip"
fi
catalog_sum=$(drpcli files exists rebar-catalog/static-catalog.zip || true)
if [[ "$catalog_sum" == "" ]]; then
  drpcli files upload static-catalog.zip as "rebar-catalog/static-catalog.zip" --explode
else
  echo "catalog already uploaded, skipping...($catalog_sum)"
fi;
(
  RS_ENDPOINT=$(terraform output drp_manager)
  drpcli catalog updateLocal -c rackn-catalog.json
  drpcli plugins runaction manager buildCatalog
  echo "Catalog Updated and Ready for endpoint export RS_ENDPOINT=$RS_ENDPOINT"
) &

drpcli plugin_providers upload dangerzone from dangerzone

drpcli contents upload multi-site-demo.json


drpcli profiles set global set "linode/stackscript_id" to 548252
drpcli profiles set global set "linode/image" to "linode/centos7"
drpcli profiles set global set "linode/type" to "g6-standard-1"
drpcli profiles set global set "linode/token" to "$LINODE_TOKEN"
drpcli profiles set global set "linode/root-password" to "r0cketsk8ts"
drpcli profiles set global set "demo/cluster-count" to 0
drpcli profiles set global param "network/firewalld-ports" to '[
  "22/tcp", "8091/tcp", "8092/tcp", "6443/tcp", "8379/tcp",  "8380/tcp", "10250/tcp"
]'

echo "BOOTSTRAP export RS_ENDPOINT=$RS_ENDPOINT"

if ! drpcli machines exists Name:bootstrap > /dev/null; then
  echo "Creating bootstrap machine object"
  drpcli machines create '{"Name":"bootstrap",
    "Workflow": "context-bootstrap",
    "Meta":{"BaseContext": "bootstrapper", "icon":"bolt"}}'
  install_sum=$(drpcli files exists bootstrap/v4drp-install.zip || true)
  if [[ "$install_sum" == "" ]]; then
    echo "upload install files..."
    drpcli files upload v4drp-install.zip as "bootstrap/v4drp-install.zip"
    drpcli files upload install.sh as "bootstrap/install.sh"
    sleep 5
  else
    echo "found installed files $install_sum"
  fi
else
  echo "Bootstrap machine exists"
fi

drpcli machines wait Name:bootstrap Stage "complete-nobootenv" 45

echo "SETUP DOCKER-CONTEXT export RS_ENDPOINT=$RS_ENDPOINT"

raw=$(drpcli contexts list Engine=docker-context)
contexts=$(jq -r -c -M ".[].Name" <<< "${raw}")
i=0
for context in $contexts; do
  image=$(jq -r -c -M ".[$i].Image" <<< "${raw}")
  echo "Uploading Container for $context named [$image] using [$context-dockerfile]"
  container_sum=$(drpcli files exists "contexts/docker-context/$image" || true)
  if [[ "$container_sum" == "" ]]; then
    echo "  Building Container"
    docker build --tag=$image --file="$context-dockerfile" .
    docker save $image > $context.tar
    echo "  Uploading Container"
    drpcli files upload $context.tar as "contexts/docker-context/$image"
  else
    echo "  Found $container_sum, skipping upload"
  fi
  i=$(($i + 1))
done
echo "uploaded $(drpcli files list contexts/docker-context)"
drpcli catalog item install docker-context

echo "ADD CLUSTERS export RS_ENDPOINT=$RS_ENDPOINT"
drpcli contents update multi-site-demo multi-site-demo.json

# prepopulate containers
sleep 30
i=0
for context in $contexts; do
  image=$(jq -r -c -M ".[$i].Image" <<< "${raw}")
  echo "Installing Container for $context named from $image"
  drpcli plugins runaction docker-context imageUpload \
    context/image-name ${image} \
    context/image-path files/contexts/docker-context/${image}
  i=$(($i + 1))
done

sites="us-central us-west us-east us-southeast"
for mc in $sites;
do
  if ! drpcli machines exists Name:$mc > /dev/null; then
    echo "Creating $mc"
    drpcli machines create "{\"Name\":\"${mc}\", \
      \"Workflow\":\"site-create\",
      \"Params\":{\"linode/region\": \"${mc}\", \"network\\firewalld-ports\":[\"22/tcp\",\"8091/tcp\",\"8092/tcp\"] }, \
      \"Meta\":{\"BaseContext\":\"runner\", \"icon\":\"cloud\"}}"
  else
    echo "machine $mc already exists"
  fi
done

###################################
################################### THIS IS COMPLETELY UNTESTED CODE
###################################
if [[ "$PREP" == "true" ]]
then
  # TODO: Need to get endpoint name dynamically if it's different going forward
  MGR="rackn-manager-demo"

  # start at 1, do COUNT iterations of WAIT length (10 mins by default)
  COUNT=1
  BAIL=120
  WAIT=5

  drpcli extended -l endpoints update $MGR '{"VersionSets":["cluster-3","credential","license","manager-ignore","'$BASE'"]}'
  drpcli extended -l endpoints update $MGR '{"Apply":true]}'

  # need to "wait" - monitor that we've finish applying this ...

  # check if apply set to true
  if [[ "$(drpcli extended -l endpoints show $MGR  | jq -r '.Apply')" == "true" ]]

  while (( COUNT <= BAIL ))
  do
    SEC=1
    # if Actions object goes away, we've drained the queue of work
    [[ "$(drpcli extended -l endpoints show $MGR | jq -r '.Actions')" == "null" ]] && break
    printf "Waiting for VersionSet Actions to drain ... (sleep $WAIT seconds ) $SEC "
    while (( SEC <= WAIT ))
    do
      sleep $WAIT
      printf "%s " $SEC
      (( SEC++ ))
    done
    (( COUNT++ ))
  done

  if [[ "$(drpcli extended -l endpoints show $MGR | jq -r '.Actions')" != "null" ]]
  then
    (( TOT = SEC * WAIT ))
    xiterr 1 "VersionSet apply actions FAILED to complete in $TOT seconds."
  fi

fi # end if PREP
###################################
################################### end of COMPLETELY UNTESTED CODE
###################################

for mc in $sites;
do
  echo "Adding $mc to install DRP"
  drpcli machines wait Name:$mc Stage "complete-nobootenv" 180
  sleep 5
  machine=$(drpcli machines show Name:$mc)
  ip=$(jq -r -c -M .Address <<< "${machine}")
  echo "Adding $mc to Endpoints List"
  drpcli plugins runaction manager addEndpoint manager/url https://$ip:8092 manager/username rocketskates manager/password r0cketsk8ts
done

echo ""
echo "DONE !!! Example export for Endpoint:"
echo "export RS_ENDPOINT=$RS_ENDPOINT"
echo ""
