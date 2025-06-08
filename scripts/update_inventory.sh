#!/bin/bash

echo "[apisix]" > ansible/inventory.ini
terraform -chdir=terraform output -json | jq -r '.public_ips.value[]' | while read ip; do
  echo "$ip ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/my-key.pem" >> ansible/inventory.ini
done
