### Securing OpenSearch Domain by Isolating in a VPC
* When creating the domain (standard create), ensure to select `VPC acess` under `Network` settings.
* Specify the subnets, then select a security group
* Optionally, Enable fine-grained access control
    - Select `Create master user` if you would like to create a Master username and Master password. YThese credentials would be used for logion to the OpenSearch dashboards later.

## EC2 instance
* Create a Publicly accessible EC2 instance by associating a public subnet with it during set up. Should be one of the subnets asociated with your OpenSearch VPC.

## Configure Security Group Access.
* **OpenSearch Domain `Security Group`:** Add an inbound rule to allow HTTPs traffic from the EC2 instance's security group. (Source *custom*)

* **EC2 (Nginx) `Security Group`: Add an inbound rule to allow HTTPS traffic from your current IP address. (Source *My IP*)

## Prepare the EC2 instance
* Connect to the instance via SSH
