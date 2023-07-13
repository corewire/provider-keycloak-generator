#!/bin/bash
set -euox pipefail

# This script is used to build the provider and push it to the registry, by only providing the configuration files that are necessary
# You just have to provide a configuration folder that contains the files explained here: https://github.com/upbound/upjet/blob/main/docs/generating-a-provider.md
# In our example this looks as follows:
# ├── configuration
# │   ├── config
# │   │   ├── external_name.go
# │   │   ├── group
# │   │   │   └── config.go
# │   │   ├── mapper
# │   │   │   └── config.go
# │   │   ├── openidclient
# │   │   │   └── config.go
# │   │   ├── provider.go
# │   │   ├── realm
# │   │   │   └── config.go
# │   │   ├── role
# │   │   │   └── config.go
# │   │   └── schema.json
# │   ├── internal
# │   │   └── clients
# │   │       └── keycloak.go


########################
####### Versions #######
########################

# If CI_COMMIT_TAG is set, use this tag as VERSION, otherwise use the default.
if [[ ${CI_COMMIT_TAG+x} ]]; then
  VERSION="$CI_COMMIT_TAG"
  export VERSION
  # Print the value of VERSION for verification
  echo "VERSION=$VERSION"
else
  echo "CI_COMMIT_TAG is not set. VERSION variable not exported."
fi

# Terraform version
# renovate: datasource=github-releases depName=hashicorp/terraform
export TERRAFORM_VERSION="1.4.6"

# Terraform provider version
# renovate: datasource=github-releases depName=mrparkers/terraform-provider-keycloak
export TERRAFORM_PROVIDER_VERSION="4.2.0"

########################
###### Variables #######
########################

export PROVIDER_NAME_LOWER=keycloak
export PROVIDER_NAME_NORMAL=keycloak
export ORGANIZATION_NAME=corewire
export PROVIDER_DIR="src/provider-${PROVIDER_NAME_LOWER}"
export CONFIG_DIR="configuration"
export PROJECT_NAME=provider-keycloak
export DISABLE_GITHUB=false
export ENABLE_CUSTOM_API_NAME=true
export CUSTOM_API_NAME="${PROVIDER_NAME_LOWER}.crossplane.io"

# Repository name
export PROJECT_REPO=${PROJECT_NAME}

# Terraform provider source
export TERRAFORM_PROVIDER_SOURCE=mrparkers/keycloak

# Terraform provider repository that contains the source code/release,
export TERRAFORM_PROVIDER_REPO=https://github.com/mrparkers/terraform-provider-keycloak

# Provider download name is the name of the release
# e.g. https://github.com/mrparkers/terraform-provider-keycloak/releases contains terraform-provider-keycloak_4.2.0_linux_amd64.zip
export TERRAFORM_PROVIDER_DOWNLOAD_NAME=terraform-provider-keycloak
export TERRAFORM_PROVIDER_DOWNLOAD_URL_PREFIX=${TERRAFORM_PROVIDER_REPO}/releases/download/v${TERRAFORM_PROVIDER_VERSION}

# Binary name of the provider, usually providers are packaged as zips, which contain a binary.
export TERRAFORM_NATIVE_PROVIDER_BINARY=terraform-provider-keycloak_v${TERRAFORM_PROVIDER_VERSION}

# Documentation path.
export TERRAFORM_DOCS_PATH=docs/resources

# Platforms to build the provider for, e.g. linux_amd64, darwin_amd64, windows_amd64 - basicallycp ${CONFIG_DIR}/cmd/provider/main.go ${PROVIDER_DIR}/cmd/provider/main.go everything that is supported by buildx.
# Should be pretty much always linux_amd64 unless you want to build for ARM or something and run on mac servers.
export PLATFORMS=${PLATFORMS:=linux_amd64 linux_arm64}

# Target Registry to push the provider to.
export REGISTRY_ORGS=registry.example.com/provider-keycloak
export XPKG_REG_ORGS=${REGISTRY_ORGS}
export XPKG_REG_ORGS_NO_PROMOTE=${REGISTRY_ORGS}

echo "PROVIDER_NAME_LOWER: $PROVIDER_NAME_LOWER"
echo "PROVIDER_NAME_NORMAL: $PROVIDER_NAME_NORMAL"
echo "ORGANIZATION_NAME: $ORGANIZATION_NAME"

########################
###### Pre Build #######
########################

mkdir src || true
rm -R -f ${PROVIDER_DIR}
git clone https://github.com/upbound/upjet-provider-template ${PROVIDER_DIR}

pushd ${PROVIDER_DIR}

git reset --hard 108a029078b02312357d777e33b7ae6236d997dc

bash hack/prepare.sh <<EOF
$PROVIDER_NAME_LOWER
$PROVIDER_NAME_NORMAL
$ORGANIZATION_NAME
EOF

REPLACE_FILES='./* ./.github :!build/** :!go.* :!hack/prepare.sh'

# if DISABLE_GITHUB is set to true, we replace the references
if [ "${DISABLE_GITHUB}" = true ]; then
  echo "Replacing 'github.com/${ORGANIZATION_NAME}/provider-${PROVIDER_NAME_LOWER}' with 'provider-${PROVIDER_NAME_LOWER}' in ${REPLACE_FILES}.."
  git grep -l "github.com/${ORGANIZATION_NAME}/provider-${PROVIDER_NAME_LOWER}" -- ${REPLACE_FILES} | xargs sed -i.bak "s|github.com/${ORGANIZATION_NAME}/provider-${PROVIDER_NAME_LOWER}|provider-${PROVIDER_NAME_LOWER}|g"
  sed -i.bak "s|github.com/${ORGANIZATION_NAME}/provider-${PROVIDER_NAME_LOWER}|provider-${PROVIDER_NAME_LOWER}|g" go.mod
fi

# if ENABLE_CUSTOM_API_NAME is set to true, we replace the occurences of the default API name
if [ "${ENABLE_CUSTOM_API_NAME}" = true ]; then
  echo "Replacing '${PROVIDER_NAME_LOWER}.upbound.io' with '${CUSTOM_API_NAME}' in ${REPLACE_FILES}.."
  git grep -l "${PROVIDER_NAME_LOWER}.upbound.io" -- ${REPLACE_FILES} | xargs sed -i.bak "s|${PROVIDER_NAME_LOWER}.upbound.io|${CUSTOM_API_NAME}|g"
fi


# Clean up the .bak files created by sed
git clean -fd

if [ "${DISABLE_GITHUB}" = true ]; then
  echo "Searching for github.com/${ORGANIZATION_NAME}/provider-${PROVIDER_NAME_LOWER}.."
  grep -rwniro -E "github.com/${ORGANIZATION_NAME}/provider-${PROVIDER_NAME_LOWER}" . && exit 1 || echo "nothing found"
  echo "Searching for github.com/provider-${PROVIDER_NAME_LOWER}.."
  grep -rwniro -E "github.com/provider-${PROVIDER_NAME_LOWER}" . && exit 1 || echo "nothing found"
fi

if [ "${ENABLE_CUSTOM_API_NAME}" = true ]; then
  echo "Searching for ${PROVIDER_NAME_LOWER}.upbound.io.."
  grep -rwniro -E "${PROVIDER_NAME_LOWER}.upbound.io" . && exit 1 || echo "nothing found"
fi

popd


### We can remove this after our PRs have been merged:
# https://github.com/upbound/upjet-provider-template/pull/29
# https://github.com/upbound/upjet-provider-template/pull/30
rm -r ${PROVIDER_DIR}/cluster/images/provider-${PROVIDER_NAME_LOWER}
cp -r ${CONFIG_DIR}/cluster/images/provider-${PROVIDER_NAME_LOWER}  ${PROVIDER_DIR}/cluster/images/provider-${PROVIDER_NAME_LOWER}
cp ${CONFIG_DIR}/Makefile ${PROVIDER_DIR}/Makefile
cp ${CONFIG_DIR}/cmd/provider/main.go ${PROVIDER_DIR}/cmd/provider/main.go


# Check if ${CONFIG_DIR}/config exists
if [ ! -d "${CONFIG_DIR}/config" ]; then
  echo "ERROR: ${CONFIG_DIR}/config does not exist"
  exit 1
fi

# Remove the config folder and replace it with our own
rm -f -R ${PROVIDER_DIR}/config
cp -r ${CONFIG_DIR}/config ${PROVIDER_DIR}/config

# Check if ${CONFIG_DIR}/internal/clients/${PROVIDER_NAME_LOWER}.go exists
if [ ! -f "${CONFIG_DIR}/internal/clients/${PROVIDER_NAME_LOWER}.go" ]; then
  echo "ERROR: ${CONFIG_DIR}/internal/clients/${PROVIDER_NAME_LOWER}.go does not exist"
  exit 1
fi

# Copy client
cp ${CONFIG_DIR}/internal/clients/${PROVIDER_NAME_LOWER}.go ${PROVIDER_DIR}/internal/clients/${PROVIDER_NAME_LOWER}.go


rm -f -R provider-keycloak-github
git clone git@github.com:corewire/provider-keycloak.git  provider-keycloak-github
# Copy stuff from PROVIDER_DIR to provider-keycloak-github and commit it
cp -r ${PROVIDER_DIR}/* provider-keycloak-github/

pushd provider-keycloak-github
git config user.email "github-action@example.com"
git config user.name "keycloak-provider-generator"
git add -A
git commit -m "Update provider"
git push 

exit 0

pushd "${PROVIDER_DIR}"
# Dummy user for CI builds to avoid dirty states
git config user.email "you@example.com"
git config user.name "Your Name"


########################
######## Build #########
########################

# Initialize submodules
make submodules
# Generate code and CRDs
make generate

# Dummy commit to avoid dirty git state
git status
git add -A
git commit -m "dummy commit"

# Build the provider and push it to the registry
make build.all
make publish
