# Hetzner Secure VPS — Zero Trust Infrastructure as Code

A reproducible, self-healing VPS deployment on Hetzner Cloud, provisioned with
Terraform and configured with Ansible. Started as a manually-hardened server
(SSH key-only auth, pre-boot firewall, Tailscale-gated access); rebuilt as
fully declarative infrastructure to demonstrate IaC, configuration management,
and Zero Trust network design end to end.

## Architecture

```
   ┌─────────────┐        provisions        ┌──────────────────┐
   │  Terraform   │ ───────────────────────▶ │  Hetzner Cloud    │
   │  (this repo) │                          │  - VPS (cx23)      │
   └─────────────┘                          │  - Cloud Firewall  │
          │                                  │  - SSH Key         │
          │ hands off IP                     └──────────────────┘
          ▼                                            │
   ┌─────────────┐        configures                   │
   │   Ansible    │ ───────────────────────────────────▶│
   │  (this repo) │                                     ▼
   └─────────────┘                          ┌──────────────────┐
                                             │  Hardened Host     │
                                             │  - SSH key-only     │
                                             │  - unattended-upgr. │
                                             │  - UFW (host-level) │
                                             │  - Tailscale mesh   │
                                             │    (Zero Trust)     │
                                             │  - Config backups   │
                                             └──────────────────┘
```

**Access model:** two independent layers enforce Zero Trust, deliberately
redundant:

1. **Hetzner Cloud Firewall** — allows only Tailscale's UDP port
   (and, optionally, a single-IP bootstrap SSH rule for emergency recovery).
2. **UFW (host-level)** — default deny on all incoming traffic, with an
   explicit allow only for the `tailscale0` interface.

Practical effect: SSH over the public IP is blocked at the host level
regardless of cloud firewall state. **All administration happens over the
Tailscale mesh IP** — the inventory and every example below use that address,
not the public one.

## Stack

| Layer | Tool | Why |
|---|---|---|
| Provisioning | Terraform + `hcloud` provider | Declarative, reproducible infra; destroy/recreate in minutes |
| Configuration | Ansible | Idempotent OS hardening and service setup |
| Access | Tailscale (WireGuard mesh) | Zero Trust — no standing public SSH port |
| Host firewall | UFW | Defense-in-depth if the cloud firewall is ever changed/bypassed |
| Secrets | Ansible Vault | Encrypted authkey storage, safe to commit |

## Repository layout

```
.
├── terraform/
│   ├── provider.tf       # hcloud provider config
│   ├── variables.tf      # server type, location, image, SSH key path
│   ├── main.tf            # hcloud_ssh_key + hcloud_server resources
│   ├── firewall.tf        # hcloud_firewall — bootstrap SSH + Tailscale UDP
│   ├── outputs.tf          # server_ip, server_id
│   └── terraform.tfvars.example
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.ini
│   ├── site.yml            # main playbook
│   ├── vault.yml           # encrypted secrets (Tailscale authkey)
│   └── roles/
│       ├── users/          # non-root admin user, passwordless sudo,
│       │                   # PermitRootLogin no
│       ├── hardening/      # unattended-upgrades, general OS hardening
│       ├── tailscale/      # keyring install, idempotent join/status check,
│       │                   # disables Tailscale's own SSH server
│       ├── firewall/       # UFW: default deny, allow tailscale0 only
│       └── backup/         # config/state backup + cron schedule
├── .gitattributes           # enforces LF line endings for shell scripts
└── README.md
```

## Setup

### 1. Provision infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: Hetzner API token + your current IP for bootstrap SSH

terraform init
terraform plan
terraform apply
```

### 2. Configure the host

`inventory.ini` and `ansible.cfg` ship configured for **first-time
bootstrap**: the public IP, connecting as `root` (the only account that
exists before the `users` role runs). This is deliberate — a freshly
provisioned box has no `viktor` user and no Tailscale connection yet.

```bash
cd ../ansible
ansible-vault edit vault.yml   # set tailscale_authkey (reusable key, Tailscale admin console)

ansible vps -m ping             # confirm connectivity first
ansible-playbook site.yml --ask-vault-pass
```

**After this first run completes**, root SSH is disabled and the box is
on the Tailscale mesh. Switch to steady-state access before running the
playbook again:
```bash
ssh -i ~/.ssh/id_ed25519_vps viktor@<public-ip-or-old-tailscale-ip> tailscale ip -4
```
Update `inventory.ini` with that Tailscale IP and change `ansible.cfg`'s
`remote_user` from `root` to `viktor`. All subsequent runs (and the
`rebuild-demo.sh` script) use this steady-state config — but note that a
**destroy + recreate** returns the box to bootstrap state, so this
switch has to happen again after every full rebuild.

### 3. Verify

```bash
# via the bootstrap IP, before hardening runs, using the key Terraform
# uploaded (root is still open at this point — before the `users` role runs):
ssh -i ~/.ssh/id_ed25519_vps root@$(terraform output -raw server_ip) tailscale status

# after the full playbook has run, root SSH is permanently disabled —
# use the non-root admin user instead, over the Tailscale IP:
ssh -i ~/.ssh/id_ed25519_vps viktor@<tailscale-ip>
sudo whoami   # -> root, no password prompt (passwordless sudo)
```

Should show `Running`, with the node visible in the Tailscale admin console.
Update `ansible/inventory.ini` to point at the Tailscale IP once confirmed —
all subsequent `ansible-playbook` runs go over the mesh, not the public IP.

## Proof points

**Reproducibility** — the entire server was destroyed and rebuilt from code
alone (triggered by an SSH key rotation forcing a resource replacement):

```
hcloud_server.vps: Destruction complete after 16s
hcloud_server.vps: Creation complete after 16s
```

No manual intervention beyond re-running `terraform apply`.

**Idempotency and self-healing** — running the playbook against an
already-configured host produces zero unnecessary changes. When the
Tailscale node was found logged out (authkey expiry), the playbook detected
the drift via a parsed `tailscale status --json` check and re-authenticated
automatically, rather than silently skipping or failing:

```
TASK [tailscale : Join Tailscale network] ... changed   # drift detected, fixed
# second run:
TASK [tailscale : Join Tailscale network] ... skipped   # already healthy
```

**Defense in depth confirmed** — after applying the `firewall` role, the
public IP stopped accepting SSH entirely (connection timeout), while the
Tailscale mesh connection remained unaffected:

```
$ ssh viktor@<public-ip>          # blocked, as intended
ssh: connect to host <public-ip> port 22: Connection timed out

$ ssh viktor@<tailscale-ip>       # still works
Last login: ...
```

**Root access fully disabled, verified against the real SSH daemon:**
```
$ ssh -i ~/.ssh/id_ed25519_vps root@<tailscale-ip>
root@<tailscale-ip>: Permission denied (publickey).

$ ssh -i ~/.ssh/id_ed25519_vps viktor@<tailscale-ip>
[connects normally]
```

**Backup verification:**
```bash
/opt/backup/backup.sh
tar -tzf /home/backups/system-config-backup-*.tar.gz
```
Confirms the archive actually contains the intended SSH, UFW,
unattended-upgrades, and Tailscale state files.

## Challenges encountered

A few real issues came up building this, each fixed by understanding the
underlying cause rather than trial-and-error:

- **`apt-key` removal (Ubuntu 24.04+/26.04):** the original Tailscale role
  used the classic `apt_key` module, which shells out to a binary removed
  from modern Ubuntu. Fixed by switching to the current `signed-by=`
  keyring method — downloading the GPG key directly and referencing it
  explicitly in the repo definition instead of trusting a global keyring.
- **GPG key / repo codename mismatch:** the GPG key was fetched for the
  server's actual codename (`resolute`, Ubuntu 26.04) but the repo line
  still pointed at `jammy` (22.04), so apt correctly refused to trust an
  inconsistent, unsigned-looking source. Fixed by aligning both to the
  server's real `lsb_release -cs` output.
- **False idempotency failures:** an early drift-check used a raw substring
  match against `tailscale status --json` output, which broke on JSON
  formatting differences and always reported "changed." Fixed by parsing
  the JSON properly with Ansible's `from_json` filter and checking the
  `BackendState` field directly.
- **Cross-filesystem tooling issues (WSL + Windows):** running Terraform
  from Windows while Ansible ran from WSL caused the two tools to read
  different copies of the SSH keypair, producing confusing
  "Permission denied (publickey)" errors that looked like a key problem
  but were actually an environment-split problem. Resolved by moving the
  whole project and toolchain (Terraform, Ansible, SSH keys) natively into
  WSL's filesystem.
- **UFW module parameter errors:** the Ansible `ufw` module's interface
  parameter is `interface_in`, not `interface` or `in_interface` — and it's
  mutually exclusive with `direction` (specifying an inbound interface
  already implies direction). Fixed by reading the module's own error
  output, which lists valid parameters directly.
- **CRLF line endings breaking a shebang:** `backup.sh`, edited in VS Code
  on Windows before being copied into WSL, picked up Windows-style `\r\n`
  line endings. This corrupted the shebang line (`/bin/bash\r`), which
  Linux reads as a literal, nonexistent interpreter path — producing a
  "bad interpreter" error that looks unrelated to line endings at first
  glance. Fixed on the host with `sed -i 's/\r$//'`, and permanently with
  a `.gitattributes` rule (`*.sh text eol=lf`) so Git normalizes line
  endings on checkout regardless of which OS/editor touches the file next.
- **Tailscale SSH silently bypassing OpenSSH's access controls:** after
  adding a `users` role to create a non-root admin account and fully
  disable root SSH login (`PermitRootLogin no`), root login still
  appeared to succeed. Root cause: `tailscale up --ssh` (run during
  initial setup) enables Tailscale's own built-in SSH server, which
  authenticates connections over the Tailscale IP using the tailnet's
  own ACL policy — a completely separate trust model from OpenSSH,
  with no awareness of `sshd_config` at all. Two independent SSH
  servers were both listening; Tailscale's answered first and used its
  own (permissive-by-default) rules, making `PermitRootLogin no` look
  broken when it was actually just being bypassed. Confirmed via
  `ssh -vvv`, which showed `remote software version Tailscale` and
  `Authenticated ... using "none"` instead of a real OpenSSH key
  exchange. Fixed with `tailscale set --ssh=false`, restoring OpenSSH
  as the sole authority over SSH access — now codified as an explicit
  task in the `tailscale` role so it survives every rebuild.
- **`tailscale up --ssh` re-introducing the bypass on every rejoin:** even
  after disabling Tailscale SSH, the `Join Tailscale network` task still
  passed `--ssh` to `tailscale up`. Any time that task actually ran
  (rather than being skipped), it silently re-enabled Tailscale SSH,
  relying on a later task to disable it again — fragile, and it broke
  outright once Tailscale itself started refusing the flag when run
  over an active Tailscale SSH session ("this action will result in your
  session disconnecting"). Fixed by dropping `--ssh` from the join
  command entirely, since Tailscale SSH is never wanted here.

## Security notes

- No password authentication anywhere; SSH key-only access.
- Root SSH login is fully disabled (`PermitRootLogin no`); a dedicated
  non-root user has passwordless sudo instead. Verified directly against
  OpenSSH (not Tailscale SSH — see Challenges above).
- Tailscale's own SSH server is explicitly disabled (`tailscale set
  --ssh=false`) so OpenSSH remains the single, auditable point of access
  control — no second, independently-governed SSH path.
- `vault.yml` is encrypted with Ansible Vault and safe to commit — the
  vault password itself is never stored in the repo.
- `terraform.tfvars` (containing the Hetzner API token) is gitignored and
  never committed; only `terraform.tfvars.example` is tracked.
- Public SSH access is intentionally temporary — the bootstrap firewall
  rule exists only until Tailscale is confirmed working, after which
  access is Tailscale-only, enforced redundantly at both the cloud
  firewall and host (UFW) level.

## Limitations

- The `backup` role captures **configuration and state** (SSH config,
  UFW rules, unattended-upgrades config, Tailscale state) — not
  application data. This host doesn't currently serve an application;
  the backup scope will expand once it does.
- Backups have been created and their contents verified (`tar -tzf`),
  but a full **restore** has not yet been tested end-to-end.
- No intrusion detection or log monitoring (`fail2ban` or equivalent)
  is in place yet — UFW blocks by default policy, but nothing currently
  alerts on or throttles repeated connection attempts.

## Roadmap

- [ ] `fail2ban` + basic log monitoring
- [ ] Test an actual backup restore, not just backup creation
- [ ] CI check (GitHub Actions) running `terraform plan` on pull requests
- [ ] Expand backup scope once the host serves an actual application
- [ ] Dynamic Ansible inventory sourced directly from Terraform output
- [ ] Phase 3: deploy an actual service onto the hardened box
