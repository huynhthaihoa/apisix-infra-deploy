# Apache APISIX Deployment with Terraform & Ansible

Deploy **Apache APISIX** (a production-ready API gateway) on AWS EC2 with automated infrastructure provisioning and configuration. This project combines **Terraform** for infrastructure-as-code and **Ansible** for application setup, with optional **GitHub Actions** CI/CD automation.

```mermaid
flowchart TD
    A[Developer Pushes to GitHub] --> B[GitHub Actions CI/CD]
    B --> C[Terraform: Provision EC2 + Security Group]
    C --> D[Terraform Outputs EC2 Public IPs]
    D --> E[Shell Script: Generate Ansible Inventory]

    E --> F[Ansible Playbook: Install Apache APISIX]
    F --> G[EC2 Instance: Apache APISIX Running]

    G --> H[Client Requests to APISIX]

    subgraph Local Option
        A2[Developer Runs Terraform Manually]
        A2 --> C
        D --> E2[Run Inventory Script Locally]
        E2 --> F2[Run Ansible Locally]
        F2 --> G
    end
```

---

## 📋 Prerequisites

Before running this deployment, ensure you have:

### Required Tools
- **Terraform** v1.0+ — [Install](https://developer.hashicorp.com/terraform/downloads)
- **Ansible** v2.9+ — [Install](https://docs.ansible.com/)
- **AWS CLI** v2 — [Install](https://docs.aws.amazon.com/cli/)
- **jq** v1.6+ — [Install](https://stedolan.github.io/jq/)
- **SSH client** (built-in on macOS/Linux; use Git Bash or WSL on Windows)

### AWS Setup
- Valid AWS account with EC2 and VPC permissions
- AWS credentials configured: `aws configure`
- Default region: `us-east-1` (customizable in `terraform/main.tf`)

### Local SSH Key
Generate an SSH key pair for EC2 access:
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/my-key -N ""
```

This creates:
- `~/.ssh/my-key` (private key — keep safe)
- `~/.ssh/my-key.pub` (public key — uploaded to EC2)

### Quick Validation
Verify everything is installed and configured:
```bash
terraform version && echo "✓ Terraform"
ansible --version && echo "✓ Ansible"
aws sts get-caller-identity && echo "✓ AWS credentials"
jq --version && echo "✓ jq"
test -f ~/.ssh/my-key && test -f ~/.ssh/my-key.pub && echo "✓ SSH keys"
```

All checks should pass before proceeding.

---

## 🛠️ Quick Start (Local Deployment)

### 1. Clone the Repository
```bash
git clone https://github.com/huynhthaihoa/apisix-infra-deploy.git
cd apisix-infra-deploy
```

### 2. Provision Infrastructure with Terraform
```bash
cd terraform
terraform init
terraform apply -auto-approve
```

**Output:** You'll see EC2 instance public IP(s) at the end. Example:
```
Outputs:

public_ips = [
  "203.0.113.42"
]
```

**Note:** This creates real AWS resources and will incur charges. See [Cleanup](#-cleanup) to remove them.

### 3. Generate Ansible Inventory
```bash
cd ..
bash scripts/update_inventory.sh
```

This queries Terraform outputs and creates `ansible/inventory.ini` with the EC2 instance details.

### 4. Deploy APISIX with Ansible
```bash
bash scripts/trigger_ansible.sh
```

This installs Apache APISIX, adds it to systemd, and starts the service.

**Expected output:**
```
PLAY RECAP ****
  203.0.113.42 : ok=5 changed=4 unreachable=0 failed=0
```

---

## 🚀 GitHub Actions CI/CD Deployment (Automated)

The `.github/workflows/deploy.yml` workflow automates all steps above. To use it:

### 1. Add AWS Credentials to GitHub
Go to your repository:
1. **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add two secrets:
   - Name: `AWS_ACCESS_KEY_ID` | Value: `your-access-key-id`
   - Name: `AWS_SECRET_ACCESS_KEY` | Value: `your-secret-access-key`

Get these from AWS IAM:
- Console: https://console.aws.amazon.com/iam/
- Create a user with EC2 and VPC permissions, generate access keys.

### 2. Update SSH Key (if needed)
If your SSH key is not `~/.ssh/my-key`, update the path in `.github/workflows/deploy.yml`:
```yaml
# Line ~35: Update the key file path
ansible_ssh_private_key_file=~/.ssh/your-key-name.pem
```

Also ensure your public key is added to the GitHub runner or stored as a secret.

### 3. Push to Main and Watch
```bash
git push origin main
```

Go to **Actions** tab in GitHub to watch the deployment. The workflow will:
1. Provision EC2 instance
2. Generate Ansible inventory
3. Deploy APISIX
4. Output the instance public IP

---

## ⚙️ Configuration & Customization

### Change AWS Region
Edit `terraform/main.tf`:
```hcl
provider "aws" {
  region = "us-west-2"  # Change from us-east-1
}
```

### Change EC2 Instance Type
Edit `terraform/main.tf` (line ~35):
```hcl
resource "aws_instance" "apisix" {
  ami           = "ami-0c02fb55956c7d316"
  instance_type = "t3.small"  # Options: t3.micro (free-tier), t3.small, t3.medium (default), t3.large, m5.xlarge

  # ... rest of config
}
```

**Instance type recommendations:**
- **Dev/Test:** `t3.micro` or `t3.small`
- **Production:** `t3.medium`, `t3.large`, or `m5.xlarge` (depends on traffic)

### Change APISIX Version
Edit `ansible/playbook.yml` (line ~4):
```yaml
vars:
  apisix_version: "3.7.0"  # Update to desired version
```

Check [Apache APISIX releases](https://github.com/apache/apisix/releases) for available versions.

### Restrict Security Group (Production)
By default, SSH and APISIX ports are open to `0.0.0.0/0` (public internet). For production, restrict access.

Edit `terraform/main.tf`:
```hcl
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["YOUR_IP/32"]  # Replace with your IP, e.g., "203.0.113.1/32"
}

ingress {
  from_port   = 9080
  to_port     = 9080
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # Keep open for API gateway, or restrict to your app servers
}
```

Find your IP: `curl ifconfig.me`

### Change APISIX Admin API Key
⚠️ **Security Warning:** The default API key in APISIX is publicly known and should **never** be used in production.

The current deployment uses the default key. To change it after deployment:

```bash
# SSH into the instance
ssh -i ~/.ssh/my-key ubuntu@<PUBLIC_IP>

# Edit APISIX config
sudo nano /etc/apisix/config.yaml

# Find the admin section and update:
admin:
  admin_key:
    - name: "admin"
      key: "your-new-secret-key-here"  # Generate: openssl rand -hex 16
      role: admin

# Restart APISIX
sudo systemctl restart apisix
```

Or configure it via the admin API (see [APISIX Docs](https://apisix.apache.org/docs/apisix/admin-api/#authentication)).

---

## ✅ Validation & Access

### Check APISIX Status
```bash
# Replace <PUBLIC_IP> with the output IP from Terraform
curl http://<PUBLIC_IP>:9080/apisix/admin/status \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1"
```

Expected response:
```json
{
  "status": "success"
}
```

### Create a Test Route
```bash
curl -X PUT http://<PUBLIC_IP>:9080/apisix/admin/routes/1 \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "/demo",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "httpbin.org:80": 1
      }
    }
  }'
```

### Test the Route
```bash
curl http://<PUBLIC_IP>:9080/demo/get
```

This should return a JSON response from httpbin.org, routed through APISIX.

### View APISIX Dashboard (Optional)
APISIX includes a web dashboard. Access it at:
```
http://<PUBLIC_IP>:9000
```

Default credentials: `admin` / `admin` (changeable in config).

---

## 🔧 Troubleshooting

### Terraform Issues

| Error | Solution |
|-------|----------|
| `Error: AuthFailure. Unauthorized Operation` | AWS credentials not configured. Run `aws configure` and verify with `aws sts get-caller-identity` |
| `Error: InvalidKeyPair.NotFound: The key pair 'my-key' does not exist` | SSH public key not found. Ensure `~/.ssh/my-key.pub` exists; regenerate if needed: `ssh-keygen -t rsa -b 4096 -f ~/.ssh/my-key -N ""` |
| `Error: VpcLimitExceeded` | AWS account VPC limit reached. Check EC2 Dashboard or delete unused VPCs |

### Ansible Issues

| Error | Solution |
|-------|----------|
| `Permission denied (publickey)` | SSH key permissions incorrect. Fix with: `chmod 600 ~/.ssh/my-key` |
| `Unable to parse output of command` | `jq` not installed. Install: `sudo apt install jq` (Ubuntu) or `brew install jq` (macOS) |
| `Failed to connect to the host via ssh` | EC2 not ready yet; wait 30-60 seconds and retry. Or security group blocks port 22; check AWS Console |
| `UNREACHABLE! → { "changed": false, "msg": "Failed to connect to...` | Ensure `~/.ssh/my-key.pem` exists and has correct permissions (600) |

### Runtime Issues

| Error | Solution |
|-------|----------|
| `curl: (7) Failed to connect` to APISIX | Wait 30-60 seconds for APISIX service to start after Ansible completes; then retry |
| `curl: (7) Failed to resolve host` | EC2 public IP is invalid or instance was not created. Verify with `terraform output public_ips` |
| `Connection timed out` on port 9080 | Security group missing ingress rule for port 9080. Check AWS Console → EC2 → Security Groups |

### GitHub Actions Issues

| Error | Solution |
|-------|----------|
| `Error: Failed to retrieve available provider plugins` | Terraform state locked. Run `terraform force-unlock <LOCK_ID>` locally, or clear `.terraform` and retry |
| `AWS credentials not found` | GitHub Secrets not set. Go to Repo Settings → Secrets and add `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` |
| `ansible-playbook: command not found` | Ansible not installed in GitHub runner. Workflow installs it; if error persists, check workflow logs |

---

## 🧼 Cleanup

### Remove All Infrastructure (AWS)
```bash
cd terraform
terraform destroy -auto-approve
```

This removes:
- EC2 instance
- Security group
- Key pair

**Cost note:** Destroy immediately if this is a test deployment to avoid unnecessary AWS charges.

### Clean Local Files
```bash
# Remove generated inventory
rm ansible/inventory.ini

# Remove Terraform state (if starting fresh)
rm -rf terraform/.terraform terraform/.terraform.lock.hcl terraform/terraform.tfstate*
```

---

## 📂 Project Structure

```
apisix-infra-deploy/
├── terraform/               Infrastructure provisioning
│   └── main.tf             AWS resources (EC2, Security Group, Key Pair)
├── ansible/                Application configuration
│   ├── playbook.yml        APISIX installation and setup
│   └── inventory.ini       Dynamic inventory (generated)
├── scripts/                Orchestration utilities
│   ├── update_inventory.sh Generate Ansible inventory from Terraform outputs
│   └── trigger_ansible.sh  Execute Ansible playbook
├── .github/
│   └── workflows/
│       └── deploy.yml      GitHub Actions CI/CD pipeline
├── README.md               This file
└── LICENSE                 MIT License
```

---

## 🎯 What Each Tool Does

- **Terraform (HCL):** Defines and provisions AWS infrastructure (compute, networking, security)
- **Ansible (YAML):** Configures the provisioned EC2 instance, installs APISIX, and manages services
- **Shell scripts:** Bridge Terraform and Ansible; generate dynamic inventory and trigger playbooks
- **GitHub Actions:** Orchestrates the full workflow: Terraform → Inventory → Ansible, triggered on push to `main`

---

## 📚 Next Steps

### Add More Routes
Use APISIX Admin API to create additional routes:
```bash
curl -X PUT http://<PUBLIC_IP>:9080/apisix/admin/routes/2 \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
  -H "Content-Type: application/json" \
  -d '{
    "uri": "/api/*",
    "upstream": {
      "type": "roundrobin",
      "nodes": {
        "your-backend-api.example.com:8080": 1
      }
    }
  }'
```

See [APISIX Admin API Documentation](https://apisix.apache.org/docs/apisix/admin-api/).

### Enable HTTPS/TLS
Configure SSL certificates in APISIX:
```bash
curl -X PUT http://<PUBLIC_IP>:9080/apisix/admin/ssls/1 \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
  -H "Content-Type: application/json" \
  -d '{
    "cert": "-----BEGIN CERTIFICATE-----\n...",
    "key": "-----BEGIN PRIVATE KEY-----\n...",
    "snis": ["example.com"]
  }'
```

### Scale to Multiple Instances
Modify `terraform/main.tf` to increase instance count:
```hcl
resource "aws_instance" "apisix" {
  # ...
  count = 3  # Provision 3 instances instead of 1
}
```

Ansible will configure all instances.

### Monitor APISIX
SSH into the instance and check logs:
```bash
ssh -i ~/.ssh/my-key ubuntu@<PUBLIC_IP>
sudo journalctl -u apisix -f  # Follow APISIX logs
sudo systemctl status apisix   # Check service status
```

---

## 🔒 Security Considerations

⚠️ **For production use, remember:**

1. **Change the default APISIX admin API key** — See [Configuration](#-configuration--customization)
2. **Restrict security group rules** — Don't leave SSH and APISIX ports open to `0.0.0.0/0`
3. **Enable HTTPS/TLS** — Use certificates, not HTTP
4. **Rotate AWS credentials** regularly and use IAM roles when possible
5. **Monitor APISIX logs** for unauthorized access attempts
6. **Use Ansible vault** to encrypt sensitive data (for advanced users)

---

## 📝 License

This project is licensed under the **MIT License**. See [LICENSE](LICENSE) for details.

---

## 💡 Support & Contributing

For issues, questions, or suggestions:
- Open an issue on [GitHub](https://github.com/huynhthaihoa/apisix-infra-deploy/issues)
- Check [Apache APISIX Documentation](https://apisix.apache.org/docs/)
- Review [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

Contributions and improvements are welcome!
