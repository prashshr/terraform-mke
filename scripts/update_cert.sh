#!/bin/bash

rm -f /etc/ssl/certs/ca-certificates.crt
ln -s /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem /etc/ssl/certs/ca-certificates.crt
