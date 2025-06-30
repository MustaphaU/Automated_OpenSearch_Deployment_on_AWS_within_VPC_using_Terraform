### Securing OpenSearch Domain by Isolating in a VPC
* When creating the domain (standard create), ensure to select `VPC access` under `Network` settings.
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
(the public IPV4 isn used to replace the Opensearch domain endpoint). Log in with your credentials created earlier.

Nginx acts as a gateway into your private VPC OpenSearch Domain.


## References
1. Video: [Access OpenSearch Dashboards in a VPC](https://www.youtube.com/watch?v=oyHhNIj4t7I)