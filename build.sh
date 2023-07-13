pushd ${PROVIDER_DIR}
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
