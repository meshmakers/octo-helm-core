# octo-helm
Helm charts for OctoMesh

# About OctoMesh
OctoMesh is at the forefront of data infrastructure innovation, enabling organizations to build decentralized data architectures that are both scalable and resilient. With OctoMesh, you can connect disparate data sources with unprecedented ease, ensuring that your data is accessible, secure, and compliant across the board.

# Getting started

## Generate a new key pair for the Identity Server

Create Private/Public Key
```bash
openssl req -x509 -newkey rsa:2048 -sha256 -keyout IdentityServer4Auth.key -out IdentityServer4Auth.crt -subj "/CN=<identity URI>" -days 10950 -passout pass:"<password>"
```
Create PFX 
```bash
openssl pkcs12 -export -out IdentityServer4Auth.pfx -inkey IdentityServer4Auth.key -in IdentityServer4Auth.crt -passin pass:"<password>" -passout pass:"<password>"
```

## Check prerequisites
Octo Mesh needs a running MongoDB and RabbitMQ instance, for stream data CrateDB is required. Ingress NGINX is recommended for routing. Cert Manager or valid public certificates are required for HTTPS.

## Create a values file to configure OctoMesh

See the [values.yaml](src/octoMesh/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

## Install Octo Mesh core services

Register meshmaker's helm repository 
```bash
helm repo add meshmakers https://meshmakers.github.io/charts
helm repo update
```

Execute the following command to install Octo Mesh
```bash
helm upgrade --install --namespace octo --create-namespace --values ./src/examples/aks-cert-manager-sample.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx <releaseName> meshmakers/octo-mesh
```

Custom root certicates can be added to the secrets using the `--set-file secrets.rootCa=<rootCa.crt>` flag.
```bash
helm upgrade --install --namespace octo --create-namespace --values local-cluster-sample.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx --set-file secrets.rootCa=rootca.crt octo-mesh meshmakers/octo-mesh 
helm upgrade --install --namespace octo --create-namespace --values rke2-local-values.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx --set-file secrets.rootCa=root-ca-collection.crt --set services.identity.image.tag="0.0.2406.3001" octo-mesh meshmakers/octo-mesh
helm upgrade --install --namespace octo --create-namespace --values rke2-local-values.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx --set-file secrets.rootCa=root-ca-collection.crt --set services.identity.image.tag="0.0.2406.3001" --set services.assetRepository.image.tag="0.0.2406.3001" --set services.bot.image.tag="0.0.2406.3001" --set services.communication.image.tag="0.0.2406.3001" --set services.adminPanel.image.tag="0.0.2406.3001" octo-mesh ..\..\..\..\octo-helm\src\octoMesh\ 
```

## Render chart template locally and display the output

```bash
helm template --namespace octo --values local-cluster-sample.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx --set-file secrets.rootCa=rootca.crt octo-mesh ../octoMesh
```

## Install Octo Mesh mesh adapter

```bash
helm upgrade --install --namespace octo --create-namespace --values rke2-local-meshTest-adapter-values.yaml --set-file secrets.rootCa=root-ca-collection.crt --set image.tag="0.0.2406.3001" mesh-test-adapter ..\..\..\..\octo-helm\src\octoMeshAdapter\ 
```
