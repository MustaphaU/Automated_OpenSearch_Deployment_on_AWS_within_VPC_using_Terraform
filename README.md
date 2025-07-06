# OpenSearch VPC Deployment with Terraform

This repository provides **automated Terraform infrastructure** to deploy a secure OpenSearch domain within a VPC, accessible through an EC2 instance running Nginx as a reverse proxy.

## Architecture

- **VPC**: Isolated network environment
- **OpenSearch Domain**: Deployed in private subnet with fine-grained access control  
- **EC2 Instance**: Public instance running Nginx as a reverse proxy
- **Security Groups**: Properly configured to allow secure access
- **SSL/TLS**: Self-signed certificates for HTTPS communication

## Automated Deployment

### Prerequisites

1. **AWS CLI configured** with appropriate credentials
2. **Terraform installed** (version >= 1.2.0)
3. **EC2 Key Pair** will be created automatically

### Option 1: Use the Automated Deployment Script

```bash
# Clone the repository
git clone https://github.com/MustaphaU/opensearch_vpc.git
cd opensearch_vpc

# Make the scripts executable
chmod +x deploy.sh cleanup.sh user_data.sh

# Run the automated deployment script
./deploy.sh 

# Optional: Specify custom key pair name and region
./deploy.sh my-custom-key us-west-2
```

### Option 2: Manual Terraform Commands

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

### Access Your OpenSearch Dashboard

After deployment completes, you'll see output with:

```
Dashboard URL: https://[EC2_PUBLIC_IP]/_dashboards
Login Credentials:
  Username: admin
  Password: TempPassword123!
SSH Command: ssh -i opensearch-key.pem ec2-user@[EC2_PUBLIC_IP]
```

## Project Files

| File | Description |
|------|-------------|
| `main.tf` | Complete Terraform infrastructure configuration |
| `deploy.sh` | Automated deployment script with error handling |
| `cleanup.sh` | Script to destroy all resources safely |
| `user_data.sh` | EC2 bootstrap script for Nginx configuration |
| `terraform.tfvars.example` | Template for customizing deployment variables |

## Configuration Options

Edit `terraform.tfvars` to customize your deployment:

```hcl
aws_region = "us-east-1"
domain_name = "your-opensearch-domain"
master_username = "admin"
master_password = "YourSecurePassword123!"
key_pair_name = "your-key-pair-name"
```

## Architecture Details

### Network Configuration
- **VPC**: `10.0.0.0/16`
- **Public Subnet**: `10.0.1.0/24` (for EC2 instance)
- **Private Subnets**: `10.0.2.0/24` and `10.0.3.0/24` (for OpenSearch)

### Security Groups
1. **OpenSearch Security Group**: HTTPS (443) from EC2 security group only
2. **EC2 Security Group**: SSH (22) and HTTPS (443) from your current IP

### OpenSearch Configuration
- **Instance Type**: `r5.large.search`
- **Instance Count**: 1 node (configurable)
- **Storage**: 20GB GP3 EBS volumes
- **Encryption**: At rest and in transit
- **Fine-grained Access Control**: Enabled with master user

## Troubleshooting

### SSH into EC2 Instance
```bash
ssh -i opensearch-key.pem ec2-user@[EC2_PUBLIC_IP]
```

### Check Nginx Status
```bash
sudo systemctl status nginx
sudo nginx -t  # Test configuration
```

### View Logs
```bash
# Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# Setup logs
sudo cat /var/log/opensearch-proxy-setup.log
```

### Common Issues

1. **Cannot access dashboard**: 
   - Check security group rules
   - Verify your current IP in the security group
   - Wait 2-3 minutes for EC2 user data script to complete

2. **SSL certificate warnings**:
   - Expected with self-signed certificates
   - Click "Advanced" and "Proceed" in browser

3. **Connection timeout**:
   - Ensure OpenSearch domain is in "Active" state
   - Check VPC configuration and route tables

## Cleanup

To destroy all resources:

```bash
./cleanup.sh
# OR
terraform destroy -auto-approve
```

## Security Considerations

- **Change default passwords** before production use


---

## Manual Setup Guide (Alternative Approach)
* When creating the OpenSearch domain (standard create), ensure to select `VPC access` under `Network` settings.
* Specify the subnets, then select a security group
* Optionally, Enable fine-grained access control
    - Select `Create master user` if you would like to create a Master username and Master password. These credentials would be used for login to the OpenSearch dashboards later.

## EC2 instance
* Create a Publicly accessible EC2 instance by associating a public subnet with it during set up. Should be one of the subnets asociated with your OpenSearch VPC.

## Configure Security Group Access.
* **OpenSearch Domain `Security Group`:** Add an inbound rule to allow HTTPs traffic from the EC2 instance's security group. (Source *custom*)

* **EC2 (Nginx) `Security Group`:** Add an inbound rule to allow HTTPS traffic from your current IP address. (Source *My IP*)

## Prepare the EC2 instance
* Connect to the instance via SSH. (remember to `chmod 400 your_key.pem`)
* Install Nginx in the instance
* Generate a self-signed SSL certificate using OpenSSL for HTTPS support.
    ```python
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/cert.key -out /etc/nginx/cert.crt
    ```

## Configure Nginx as a Reverse Proxy
* Edit the Nginx configuration file by:
    - Setting up a server block that listens on port 443 (HTTPS).
    - Configure a `location /` block that uses `proxy_pass` to forward requests to your OpenSearch domain VPC endpoint

    Open the Nginx config:
    ```bash
    sudo nano /etc/nginx/nginx.conf
    ```
    Add this to the bottom of the file
    ```
    server {
    listen 443 ssl;
    listen [::]:443;
    server_name localhost;
    root /usr/share/nginx/html;

    ssl_certificate /etc/nginx/cert.crt;
    ssl_certificate_key /etc/nginx/cert.key;
    ssl_session_cache builtin:1000 shared:SSL:10m;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers HIGH:!aNULL:!eNULL:!EXPORT:!CAMELLIA:!DES:!MD5:!PSK:!RC4;
    ssl_prefer_server_ciphers on;

    # Load configuration files for the default server block.
    include /etc/nginx/default.d/*.conf;
    
    #EDIT THIS PART 
    location / {
        proxy_pass https://copy_your_opensearch_domain_endpoint_here.aos.us-east-1.on.aws;
    }
    }

    ```

    * Save write and close: ctrl+o, ENTER, ctrl+x


* Start or restart (`start` or `restart`) the Nginx server:
    ```bash
    sudo service nginx restart
    ```

Now you can access your OpenSearch Dashboards securely over the internet using the public IPV4 address of your EC2 Instance like so:

https://31.XXXX.XX.XX/_dashboards  
(the public IPV4 is used to replace the Opensearch domain endpoint). Log in with your credentials created earlier.

Nginx acts as a gateway into your private VPC OpenSearch Domain.


## References
1. Video: [Access OpenSearch Dashboards in a VPC](https://www.youtube.com/watch?v=oyHhNIj4t7I)