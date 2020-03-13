## some tips

* Install the azure cli - https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest
* Follow the ["before you begin"](https://docs.microsoft.com/en-us/azure/aks/use-multiple-node-pools#before-you-begin)

## prep
Link in the secrets
`ln -s ../private-config/external-dns/azure-secrets.yaml charts/azure-secrets.yaml`


## Install from scratch:

Work in the `bin` dir:

`cd bin`

Install from scratch
`./azure_pangeo_setup -a -r <name_for_resource_group_and_cluster>`

e.g.

dev: `./azure_pangeo_setup -a -r panzure-dev`
prod: `./azure_pangeo_setup -a -r panzure`


## Delete it all:

If you are really sure you want to delete everything *including* user homespaces and data then you can delete the resource group through the azure portal:- https://portal.azure.com/

## Update

You should just be able to re-run the install to update but if in doubt delete and install again from scratch.

## GOTCHA
At time of writing there is a bug in the Azure CLI that will prevent you creating the volume on the NetApp Files (you'll get 500 errors). At this step you need to go in to he Azure web GUI and do it manually. You can the continue/re-run the install.
