#!/bin/bash

# Variables
storageAccount="$1"
fileSystem="$2"
baseUrl="$3"
managedIdentityClientId="$4"

echo "Script Started"

# Authenticate with Azure
if az account show &> /dev/null; then
    echo "Already authenticated with Azure."
else
    if [ -n "$managedIdentityClientId" ]; then
        # Use managed identity if running in Azure
        echo "Authenticating with Managed Identity..."
        az login --identity --client-id ${managedIdentityClientId}
    else
        # Use Azure CLI login if running locally
        echo "Authenticating with Azure CLI..."
        az login
    fi
    echo "Not authenticated with Azure. Attempting to authenticate..."
fi

# if using managed identity, skip role assignments as its already provided via bicep
if [ -n "$managedIdentityClientId" ]; then
    echo "Skipping role assignments as managed identity is used"
else
    echo "Getting signed in user id"
    signed_user_id=$(az ad signed-in-user show --query id -o tsv)

    echo "Getting storage account resource id"
    storage_account_resource_id=$(az storage account show --name $storageAccount --query id --output tsv)

    #check if user has the Storage Blob Data Contributor role, add it if not
    echo "Checking if user has the Storage Blob Data Contributor role"
    role_assignment=$(MSYS_NO_PATHCONV=1 az role assignment list --assignee $signed_user_id --role "Storage Blob Data Contributor" --scope $storage_account_resource_id --query "[].roleDefinitionId" -o tsv)
    if [ -z "$role_assignment" ]; then
        echo "User does not have the Storage Blob Data Contributor role. Assigning the role."
        MSYS_NO_PATHCONV=1 az role assignment create --assignee $signed_user_id --role "Storage Blob Data Contributor" --scope $storage_account_resource_id --output none
        if [ $? -eq 0 ]; then
            echo "Role assignment completed successfully."
        else
            echo "Error: Role assignment failed."
            exit 1
        fi
    else
        echo "User already has the Storage Blob Data Contributor role."
    fi
fi

zipFileName1="clientdata.zip"
extractedFolder1="clientdata"

zipFileName2="clienttranscripts.zip"
extractedFolder2="clienttranscripts"

#check if baseUrl is provided, if not, set it to empty string
if [ -z "$baseUrl" ]; then
    baseUrl=""
fi

zipUrl1=${baseUrl}"infra/data/$zipFileName1"
zipUrl2=${baseUrl}"infra/data/$zipFileName2"

extractionPath1=""
extractionPath2=""

# Check if running in Azure Container App
if !([ -z "$baseUrl" ] && [ -z "$managedIdentityClientId" ]); then
    $extractionPath1="/mnt/azscripts/azscriptinput/$extractedFolder1"
    $extractionPath2="/mnt/azscripts/azscriptinput/$extractedFolder2"

    # Create the folders if they do not exist
    mkdir -p $extractionsPath1
    mkdir -p $extractionsPath2

    # Download the zip file
    curl --output /mnt/azscripts/azscriptinput/"$zipFileName1" "$zipUrl1"
    curl --output /mnt/azscripts/azscriptinput/"$zipFileName2" "$zipUrl2"

    # Extract the zip file
    unzip /mnt/azscripts/azscriptinput/"$zipFileName1" -d $extractionPath1
    unzip /mnt/azscripts/azscriptinput/"$zipFileName2" -d $extractionPath2

else
    extractionPath1="infra/data/$extractedFolder1"
    extractionPath2="infra/data/$extractedFolder2"

    unzip -o $zipUrl1 -d $extractionPath1
    unzip -o $zipUrl2 -d $extractionPath2
fi

# Using az storage blob upload-batch to upload files with managed identity authentication, as the az storage fs directory upload command is not working with managed identity authentication.
az storage blob upload-batch --account-name "$storageAccount" --destination data/"$extractedFolder1" --source $extractionPath1 --auth-mode login --pattern '*' --overwrite --output none
az storage blob upload-batch --account-name "$storageAccount" --destination data/"$extractedFolder2" --source $extractionPath2 --auth-mode login --pattern '*' --overwrite --output none
# az storage fs directory upload -f "$fileSystem" --account-name "$storageAccount" -s "$extractedFolder1" --account-key "$accountKey" --recursive
# az storage fs directory upload -f "$fileSystem" --account-name "$storageAccount" -s "$extractedFolder2" --account-key "$accountKey" --recursive
