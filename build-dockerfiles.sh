#!/usr/bin/env bash

function xiterr() { [[ $1 =~ ^[0-9]+$ ]] && { XIT=$1; shift; } || XIT=1; printf "FATAL: $*\n"; exit $XIT; }

which docker > /dev/null 2>&1 || xiterr 1 "Missing 'docker' tool"

#ls dockerfiles/*dockerfile* | while read dockerfile ; do
for dockerfile in $(cd dockerfiles; ls -1 *dockerfile*)
do

  container=$(echo "$dockerfile" | sed -e 's|-dockerfile||g' -e 's|dockerfiles/||')
  tag="digitalrebar/$container"

  [[ -f "${container}.tar" ]] && rm -f ${container}.tar
  [[ -f "${container}.tar.gz" ]] && rm -f ${container}.tar.gz

  echo "================================================================================="
  echo "Starting container build for '$container' with image tag '$tag'."
  echo ">>> docker build"
  docker build --tag=$tag --file=dockerfiles/"${container}-dockerfile" .
  echo ">>> docker save"
  docker save $tag > ${container}.tar
  gzip -9 ${container}.tar
  echo ""
done
