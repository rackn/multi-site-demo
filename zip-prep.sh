#!/usr/bin/env bash

# zip up files for packing up


FILES="dangerzone drpcli runner.tar terraform terraform.tar .terraform/plugins/linux_amd64/terraform-provider-linode_v1.9.0_x4"

set -e

for FILE in $FILES
do
	[[ ! -r "$FILE" ]] && continue || true
	echo "Zipping up:  $FILE"
	gzip $FILE &
done

wait

echo ""
printf "Removing TF log file... "
rm -f .terraform/plugins/linux_amd64/lock.json
echo "done"

echo ""
printf "Nuke big fat catalog zip file ... "
rm -f static-catalog.zip
echo "done"

echo ""
printf "Nuke terraform state files ... "
rm -f terraform.tfstate terraform.tfstate.BACKUP
echo "done"

echo ""
echo "Done - now pack things up by running: "
echo ""
echo "  cd $HOME"
echo "  tar -czvf multi-site-demo.tgz multi-site-demo/"
echo ""
