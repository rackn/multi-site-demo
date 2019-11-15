#!/usr/bin/env bash
# RackN Copyright 2019
# Build Manager Demo

export PATH=$PATH:$PWD

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
drpcli files upload static-catalog.zip as "rebar-catalog/static-catalog.zip" --explode
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
  echo "upload install files..."
  drpcli files upload v4drp-install.zip as "bootstrap/v4drp-install.zip"
  drpcli files upload install.sh as "bootstrap/install.sh"
  sleep 5
else
  echo "Boostrap machine exists"
fi

drpcli machines wait Name:bootstrap Stage "complete-nobootenv" 45

echo "SETUP DOCKER-CONTEXT export RS_ENDPOINT=$RS_ENDPOINT"

raw=$(drpcli contexts list Engine=docker-context)
contexts=$(jq -r -c -M ".[].Name" <<< "${raw}")
i=0
for context in $contexts; do
  image=$(jq -r -c -M ".[$i].Image" <<< "${raw}")
  echo "Uploading Container for $context named [$image] using [$context-dockerfile]"
  docker build --tag=$image --file="$context-dockerfile" .
  docker save $image > $context.tar
  drpcli files upload $context.tar as "contexts/docker-context/$image"
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

echo "DONE export RS_ENDPOINT=$RS_ENDPOINT"
