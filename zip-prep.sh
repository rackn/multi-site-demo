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

echo "Waiting for zip processes to finish..."
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
echo "Done - creating TGZ file... "
echo ""
tar -czvf $HOME/multi-site-demo.tgz multi-site-demo/
echo ""
echo "Updated TGZ is at:"
ls -lh $HOME/multi-site-demo.tgz
echo ""
