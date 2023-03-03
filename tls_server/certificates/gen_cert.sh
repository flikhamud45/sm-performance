# This script creates a self-signed certificate and CA root
PASSPHRASE=$( head -c 12 /dev/urandom | base64 )
SERVER_NS='workload'
SERVER_NAME='simulated-server'
# Create the private key for the Root CA:
openssl genrsa -des3 -passout pass:${PASSPHRASE} -out rootCA.key 4096

# Create the Root CA's certificate and sign it with the Root CA's private key:
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 2048 \
-subj "/C=DE/ST=baden-wurttemberg/O=IDC, Inc./CN=runi.ac.il" \
-addext "subjectAltName = DNS:runi.ac.il" -passin pass:${PASSPHRASE} -out rootCA.crt

# Create a private key for the TLS server:
openssl genrsa -out "${SERVER_NAME}.${SERVER_NS}.svc.key" 2048

# Create the certificate signing request (CSR) for the server's certificate:
openssl req -new -key "${SERVER_NAME}.${SERVER_NS}.svc.key" \
-subj "/C=DE/ST=baden-wurttemberg/O=IDC, Inc./CN=${SERVER_NAME}.${SERVER_NS}.svc.cluster.local" \
-addext "subjectAltName = DNS:${SERVER_NAME}.${SERVER_NS}.svc.cluster.local" \
-config <(cat /etc/ssl/openssl.cnf <(printf "\n[SAN]\nsubjectAltName=DNS:${SERVER_NAME}.${SERVER_NS}.svc.cluster.local")) \
-out ${SERVER_NAME}.${SERVER_NS}.svc.csr

# Verify the CSR content:
openssl req -in "${SERVER_NAME}.${SERVER_NS}.svc.csr" -noout -text

# Generate the certificate itself with the CSR, and add the root CA to the chain:
openssl x509 -req -extfile <(printf "subjectAltName=DNS:${SERVER_NAME}.${SERVER_NS}.svc.cluster.local") \
-in "${SERVER_NAME}.${SERVER_NS}.svc.csr" -CA rootCA.crt -CAkey rootCA.key -CAcreateserial \
-passin pass:${PASSPHRASE} -out ${SERVER_NAME}.${SERVER_NS}.svc.crt -days 2048 -sha256

# Verify the final certificate
openssl x509 -in "${SERVER_NAME}.${SERVER_NS}.svc.crt" -text -noout

mkdir -p results
cp ./rootCA.crt ./results
cp "./${SERVER_NAME}.${SERVER_NS}.svc.crt" ./results
cp "./${SERVER_NAME}.${SERVER_NS}.svc.key" ./results
