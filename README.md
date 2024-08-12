# octo-helm

This repository contains the helm charts for OctoMesh. The charts are hosted on GitHub pages and can be accessed using the following URL:

```bash
https://meshmakers.github.io/charts
```
# About OctoMesh

OctoMesh is at the forefront of data infrastructure innovation, enabling organizations to build decentralized data architectures that are both scalable and resilient. With OctoMesh, you can connect disparate data sources with unprecedented ease, ensuring that your data is accessible, secure, and compliant across the board.

# Getting started

There are several helm charts available in this repository:
1) octo-mesh: The core services of OctoMesh. This is typically installed centrally and supports multiple tenants.
2) octo-mesh-adapter: Mesh Adapters host mesh pipelines and are installed in the same cluster as the core services, but for each tenant.
3) octo-mesh-crts: This chart contains all custom resource definitions (CRDs) required by OctoMesh Communication Operator
4) octo-mesh-communication-operator: This chart contains the OctoMesh Communication Operator, which is responsible for managing adapters on edge clusters.

To use the charts, add the repository to your helm configuration:

```bash
helm repo add meshmakers https://meshmakers.github.io/charts
helm repo update
```

## Setup octo-mesh core services

Octo Mesh needs a running MongoDB and RabbitMQ instance, for stream data CrateDB is required. Ingress NGINX is recommended for routing. Cert Manager or valid public certificates are required for HTTPS.

Summarized, the following prerequisites are required to install Octo Mesh:
1) Ingress NGINX
2) Cert Manager
3) MongoDB
4) RabbitMQ
5) CrateDB

For support to set up the prerequisites, please contact us at [support@meshmakers.io](mailto:support@meshmakers.io)

If you have the prerequisites ready, you can install the core services using the following steps:

### Generate a new key pair for the Identity Server

Create Private/Public Key

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -keyout IdentityServer4Auth.key -out IdentityServer4Auth.crt -subj "/CN=<identity URI>" -days 10950 -passout pass:"<password>"
```

Create PFX

```bash
openssl pkcs12 -export -out IdentityServer4Auth.pfx -inkey IdentityServer4Auth.key -in IdentityServer4Auth.crt -passin pass:"<password>" -passout pass:"<password>"
```

### Create a values file to configure OctoMesh
See the [values.yaml](src/octo-mesh/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Install OctoMesh core services

Execute the following command to install Octo Mesh

```bash
helm upgrade --install --namespace octo --create-namespace --values ./src/examples/aks-cert-manager-sample.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx <releaseName> meshmakers/octo-mesh
```

Custom root certificates can be added to the secrets using the `--set-file secrets.rootCa=<rootCa.crt>` flag.

```bash
helm upgrade --install --namespace octo --create-namespace --values local-cluster-sample.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx --set-file secrets.rootCa=rootca.crt octo-mesh meshmakers/octo-mesh
```

It is also possible to set the image tag for the services using the `--set services.<service>.image.tag=<tag>` flag.

```bash
helm upgrade --install --namespace octo --create-namespace --values rke2-local-values.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx --set-file secrets.rootCa=root-ca-collection.crt --set services.identity.image.tag="0.0.2406.3001" octo-mesh meshmakers/octo-mesh
```

### Render octo-mesh chart template locally and display the output

```bash
helm template --namespace octo --values local-cluster-sample.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx --set-file secrets.rootCa=rootca.crt octo-mesh ../octoMesh
```

## Setup Octo Mesh Adapter

Octo Mesh Adapter is a service that hosts mesh pipelines and is installed in the same cluster as the core services, but for each tenant. The adapter requires a running MongoDB instance and CRATE DB for stream data.

### Create a values file to configure OctoMesh Adapter
See the [values.yaml](src/octo-mesh-adapter/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Render octo-mesh-adapter chart template locally and display the output

```bash
helm template --namespace octo --values adapter-sample.yaml octo-mesh-adapter ../octoMeshAdapter
```

### Install Octo Mesh Adapter

```bash
helm upgrade --install --namespace octo --create-namespace --values rke2-local-meshTest-adapter-values.yaml --set-file secrets.rootCa=root-ca-collection.crt --set image.tag="0.0.2406.3001" mesh-test-adapter meshmakers/octo-mesh-adapter
```

## Setup Octo Mesh Communication Operator

Octo Mesh Communication Operator is responsible for managing adapters on edge clusters. The operator requires octo-mesh-crts to be installed.

### Create a values file to configure OctoMesh Communication Operator
See the [values.yaml](src/octo-mesh-communication-operator/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Render octo-mesh-crts chart template locally and display the output

```bash
helm template --namespace octo --values crts-sample.yaml octo-mesh-crts ../octoMeshCrts
```

### Install Octo Mesh CRDs

```bash
helm upgrade --install octo-mesh-crts meshmakers/octo-mesh-crts
```

helm install --namespace octo-ns --values ./examples/operator-sample.yaml --set-file serviceHooks.caKey=examples/ca-key.pem --set-file serviceHooks.caCrt=examples/ca.pem --set-file serviceHooks.svcKey=examples/svc-key.pem --set-file serviceHooks.svcCrt=examples/svc.pem octo-mesh-op1 --set "octo-mesh-crds.enabled=false" ./octo-mesh-communication-operator/