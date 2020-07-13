#! /usr/bin/env bash

# ./deploy.sh [BRANCH]

# Allow specifcying a branch or commit to deploy.
branch=${1-'master'}

echo "Deploying branch: $branch"

# Deploy a copy of snapCloud
pushd ~/snapCloud/ > /dev/null;

git checkout $branch
git pull origin $branch
git submodule update --recursive --remote

# Build community site
pushd site
Snippets/build.sh
popd

# Create a release on GitHub
source .env
deploy_sha=$(git rev-parse HEAD)
# A modified ISO8601 format. GitHub does not support tags
current_time=$(date -u +"%Y-%m-%dT%H-%M-%S")
repo='https://api.github.com/repos/snap-cloud/snapCloud/releases'
# tag non-production releases as 'prerelase'
prelease=$(if [ "$LAPIS_ENVIRONMENT" = 'production' ]; then echo 'false'; else echo 'true'; fi)
curl -X POST -H "Content-Type:application/json" -u cycomachead:$GITHUB_TOKEN $repo -d "{\"tag_name\": \"$current_time\", \"target_commitish\": \"$deploy_sha\", \"prerelease\": $prelease}"

# Mark a deploy in Rollbar
echo 'Tagging Deploy in Rollbar'
curl -POST --url https://api.rollbar.com/api/1/deploy/ \
    --data "{\"access_token\": \"$ROLLBAR_TOKEN\", \"environment\":\"$LAPIS_ENVIRONMENT\", \"revision\": \"$deploy_sha\"}"
echo
echo

echo 'Tagging Deploy in Sentry'
# Tag a release in Sentry, too.
curl https://sentry.cs10.org/api/hooks/release/builtin/2/aca228bdf5410118114d83644397592ba4c12bc165a9d34f0e7c08c2e2103bf4/ \
  -X POST \
  -H 'Content-Type: application/json' \
  -d "{\"version\": \"$current_time\"}"

echo
echo

# Always update the letsencrypt script incase it changes.
cp bin/deploy_certs.sh ../lets-encrypt/renewal-hooks/deploy/1-deploy.sh

# The cloud user only has the ability to restart this service.
echo 'Restarting snapcloud daemon'
sudo service snapcloud_daemon restart

popd > /dev/null;

echo 'Done!'
