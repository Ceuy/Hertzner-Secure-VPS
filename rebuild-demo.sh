#!/bin/bash
set -e

# --- One-time setup: vault password file (not committed, cleaned up at the end) ---
VAULT_PASS_FILE="$HOME/.vault_pass_demo.txt"

if [ ! -f "$VAULT_PASS_FILE" ]; then
  echo "Vault password file not found."
  read -s -p "Enter Ansible Vault password (will be stored temporarily): " VAULT_PW
  echo
  echo "$VAULT_PW" > "$VAULT_PASS_FILE"
  chmod 600 "$VAULT_PASS_FILE"
fi

# --- Terraform: destroy + rebuild ---
cd terraform
terraform destroy -auto-approve
terraform apply -auto-approve

NEW_IP=$(terraform output -raw server_ip)
echo "New server IP: $NEW_IP"

cd ../ansible

# --- Regenerate inventory fresh from Terraform output (avoids stale/hardcoded IP) ---
cat > inventory.ini << EOF
[vps]
secure-vps ansible_host=$NEW_IP
EOF

# --- Clear any stale known_hosts entry for this IP (Hetzner reuses IPs) ---
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$NEW_IP" 2>/dev/null || true

echo "Waiting for SSH to become available on $NEW_IP..."
for i in $(seq 1 30); do
  if timeout 3 bash -c "</dev/tcp/$NEW_IP/22" 2>/dev/null; then
    echo "SSH is up after ~$((i*3))s."
    break
  fi
  sleep 3
done

# --- Run the playbook against the fresh box ---
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook site.yml --vault-password-file "$VAULT_PASS_FILE"

# --- Cleanup: remove the temporary plaintext vault password file ---
rm -f "$VAULT_PASS_FILE"

echo "Done. Server IP: $NEW_IP"
