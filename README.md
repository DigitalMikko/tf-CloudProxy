# Description
A way to create containers in the cloud w/ tailscale for proxying traffic through a public IP from a cloud provider. 

Made for:
- security consultants
- pentesters
- sec researchers
- etc

First intended for burp suite traffic. But you can technically proxy a lot of other stuff. 

> Works best with some hot coffee ☕️

# DISCLAIMER
This is intended to aide authorized security work. Never test a system you are not authorized to test.


# Getting started (Azure)
## Clone repo
Just clone this repo to get everything you need. 
```sh
git clone https://github.com/DigitalMikko/tf-CloudProxy.git
```

## Add your Sub ID
I've had some issues on my end with terraform seeing my Azure subscription ID in my terminal env vars. So I made a `terraform.tfvars` with a placeholder for you to add the ID. That's all.
Edit the `terraform.tfvars` file in both `/core` & `/runtime` directories.
```sh
# Template
subscription_id = "Your-Sub-ID"
```

## Register Azure sub to use container apps
If this is a brand new subscription, you need to tell Azure that you will use the `Microsoft.App` service. It's how we can use containers instead of VMs. 

Here's how:
```sh
# First things, login > select sub > follow the standard temrminal prompts
az login

az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.OperationalInsights
```
> This might take a few minutes. You can check the status like this:
```sh
az provider show --namespace Microsoft.App --query"registrationState" -o tsv
```
You want it to say `Registered`. (If it still says `Registering`, wait, coffee break > then re-run the command until it flips.)

Otherwise, you'll get this error:
- `error message: 409 MissingSubscriptionRegistration: not registered for Microsoft.App`

## Quick description of setup
I went with a core + runtime approach. 

Core sets up the following:
- Public IP registration
  - To give to a client to whitelist
- Keyvault
	- To set up your tailscale secret out of band so that `runtime` can use it to register the container into your tailnet.

This was ideal for me since the IP registration is really the only thing I needed before starting an engament. This is also cost effective as having the entire setup weeks before the engagement start is not ideal/wasteful. 
The core keeps everything minimum while letting you provide a client with a public IP address of where you'll be testing from (use responsibly).

Then once an engagement starts, you deploy the rest in `runtime`

## Deploying Core
To deploy `Core`, all you need is to move (`cd`) into the `/core` directory and run the following commands:

This will get everthing setup in tf.
```sh
# Init
terraform init
```

Then you can check if there are any errors with `terraform plan` or you can simply run:
```sh
terraform apply
```
This will take a few minutes and will ask you to type `yes` to provision up to Azure. 

When done, the terminal should output the public IP address that was registered. 


## Deploying Runtime

### Pre-req
You need to create your tailscale secret inside your keyvault.

#### Create a tailscale `Container` tag
This is needed for containers in tailnets. Since they are non-user machines.
- Go to Access Controls
- `json editor`
- Add the following:
```json
"tagOwners": {
		// Docker containers
		"tag:Container": ["autogroup:owner", "autogroup:admin"],
	}
```

#### Create the tailscale auth key
You create a tailscale secret at Tailscale > Settings > Keys > Auth Keys section > Generate Auth key...
- Make sure you enable "Tags"
- Select the "`Container`" tag from the dropdown

#### Add the key to Azure
Go to Azure > select your subscription > go to `Key Vaults` and find the `cntpxykv` keyvault. 

Then under the Objects left sidebar, find `Secrets` and select the `Create/Import` action from the navbar. (Azure changes names from time to time, so just find secrets and create one)

Leave everything as is, and enter the following:
- name: `TS-AUTHKEY`
- Secret value: `Your TS_AUTHKEY from tailscale (looks like tskey-auth-k......)`


### Deploying
When you are ready to deploy the rest of the setup. Just `cd` into the `/runtime` directory then:
```sh
terraform init
```

Once done, you can do the same as core:
```
# If you want to see the plan and if there are any errors. 
terraform plan

# Deploy the plan
terraform apply
```

This will take considerably longer as we are deploying more infrastructure. 

Once done, your terminal should output the IP address again. 

## Connecting
Because this setups uses tailnets, and we are using the SSH feature within tailnets. We can connect directly to the container, without having to expose any ports on the Azure side.

The container gets a private tailsnet IP which you should be able to see from your tailscale dashboard. 

To make sure that works, go to the Access Controls section in Tailscale and enter the following using the `json editor` in the `"ssh"` section:
```json
"ssh": [
		{
			"src":    ["autogroup:admin"],
			"dst":    ["tag:Container"],
			"users":  ["root"],
			"action": "accept",
		},
	],
```
This allows admins in your tailnet to be able to ssh into the container with the `Container` tag as `root`. 
- You can adjust ACLs as you see fit.

Then all you have to do from a host on your tailnet:
```sh
ssh root@<Container TailScale IP>
```
