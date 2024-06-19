#!/usr/bin/env bash

# Generate self-signed certificates

CA_PREFIX='root'
VALID_DAYS=3650
CERT_DIR="certs"
CERTS=( "example.com" )

# create subdirectory to store certs
echo "Creating '${CERT_DIR}' directory"
mkdir -p $CERT_DIR

# create CA cert
echo "Creating CA certificate"
openssl req -new -newkey rsa:4096 -x509 -days ${VALID_DAYS} -nodes -extensions v3_ca -keyout ${CERT_DIR}/${CA_PREFIX}.ca.key -out ${CERT_DIR}/${CA_PREFIX}.ca.crt -subj "/CN=${CA_PREFIX}.ca"

# create certs
for CERT in "${CERTS[@]}"
do
    echo "Creating ${CERT} certificate"
    openssl genrsa -out ${CERT_DIR}/${CERT}.key 4096
    openssl req -new -key ${CERT_DIR}/${CERT}.key -out ${CERT_DIR}/${CERT}.csr -subj "/CN=${CERT}"
    openssl x509 -req -days ${VALID_DAYS} -in ${CERT_DIR}/${CERT}.csr -CA ${CERT_DIR}/${CA_PREFIX}.ca.crt -CAkey ${CERT_DIR}/${CA_PREFIX}.ca.key -CAcreateserial -out ${CERT_DIR}/${CERT}.crt
    rm ${CERT_DIR}/${CERT}.csr
done