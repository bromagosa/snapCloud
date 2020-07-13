#! /usr/bin/env bash

# renew certs using our config.
# Reference material:
# https://dev-notes.eu/2018/05/set-up-an-automatic-letsencrypt-renewal-cronjob/

pushd ~/
/usr/bin/perl -e 'sleep int(rand(3600))' && certbot renew --config-dir lets-encrypt --logs-dir lets-encrypt --work-dir lets-encrypt --deploy-hook snapCloud/bin/deploy_certs.sh
popd
