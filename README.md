# Secure Zero-Trust VPS Infrastructure (+Guide)

A hardened cloud VPS demonstrating security-first provisioning — SSH access restricted exclusively through a Tailscale mesh VPN, with automated backups and infrastructure built with Zero Trust networking principles in mind.

## Why this project

I wanted to understand secure infrastructure provisioning from first principles rather than relying on managed platform defaults. This project applies Zero Trust networking concepts (never trust, always verify — no implicit trust based on network location) to a real, internet-facing server.

## Architecture
```
Local Machine (SSH client)
│
│ SSH over Tailscale (WireGuard-based mesh VPN,
│ encrypted, private, not public internet)
▼
Hetzner Cloud VPS
├── Firewall — SSH (port 22) allowed ONLY
│   from Tailscale's private IP range, never from 0.0.0.0/0
├── Tailscale daemon (100.x.x.x private mesh address)
├── SSH key-based authentication only (password auth disabled)
├── Nginx (web server, ready for deployment)
└── Automated backup system (cron + backup.sh)
```

## What I built, step by step

1. **Key generation** — Local SSH keypair (RSA), private key never leaves my machine
"ssh-keygen -t rsa -b 4096" - Generates a 4096 bit RSA key pair on PC. The key is generated in .ssh folder on your user.
It will ask for a name of file and a passphrase (optional, do not forget passphrase it will be used to log into the VPS).

2. **VPS provisioning** — Hetzner Cloud instance, firewall rules applied at creation time
Hertzner Cloud instance set up for as low as 7 euro/month. Firewall rules template can be created on their website to be used for your instances.

3. **Zero-trust network access** — Installed Tailscale, restricted all SSH access to the Tailscale mesh IP range only
Tailscale is installed first on local pc. After installation it is assigned a tailscale IP that can be added to a tailnet using a online console.
Cloud instance needs to be temporarely available to connect via ssh over the internet. Firewall rules restict it so it only accepts ssh connection from our public IP. We then install tailscale on it and get the taiscale ip:
```tailscale ip -4```
and add that to the online console with our pc. 
Finally update the firewall to accept ssh connection only from our Tailscale IPs.

4. **System hardening** — Package updates, minimal exposed services
Regular upgrades to keep everything up to date:
```sudo apt update && sudo apt upgrade -y```
On my VPS I also personally installed nginx to host web apps. installing is as follows:
```
sudo apt install nginx -y
sudo systemctl start nginx
sudo systemctl enable nginx
```

5. **Automated backups** — Cron-scheduled backup.sh archiving critical configuration, with 7-day retention
backup.sh is the backup script I use for my VPS. once created on the server I make the file executable and make a cronjob for to backup every X days:

```sudo nano /usr/local/bin/backup.sh``` - create script file
Then paste the script code (Note, the script tries to backup nginx files/folders aswell, if you don't have nginx installed, remove the nginx line.
```sudo chmod +x /usr/local/bin/backup.sh``` - make file executable

Then we add the cronjob to the cron editor:
```sudo crontab -e```
Open with nano if prompted then add this line after the comment lines:
```0 2 * * * /usr/local/bin/backup.sh``` - executes script every night at 2am system time.
save and quit.
