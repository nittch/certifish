# certifish
Certifish is a shell script that helps you generate an x509 certificate with OpenSSL.

You have to configure it once (CA, country, organization...) and usage is very simple (./certifish.sh requestedCommonName.example.com).

The script creates a new directory with that common name, and populates it with the key and the CSR.
It helps you to communicate with your CA by displaying the CSR and prompts you for the signed certificate.

