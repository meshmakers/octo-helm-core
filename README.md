# OctoMesh Helm Charts

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
5) octo-mesh-office: This chart contains the OctoMesh Office, which is an Excel add-in that allows users to interact with OctoMesh.
6) octo-mesh-reporting: This chart contains OctoMesh Reporting, which is a service that provides reporting capabilities for OctoMesh.
7) octo-mesh-app-template: This chart contains a template for an OctoMesh frontend app.

To use the charts, add the repository to your helm configuration:

```bash
helm repo add meshmakers https://meshmakers.github.io/charts
helm repo update
```

## Setup octo-mesh core services

OctoMesh needs a running MongoDB and RabbitMQ instance, for stream data CrateDB is required. Ingress NGINX is recommended for routing. Cert Manager or valid public certificates are required for HTTPS.

Summarized, the following prerequisites are required to install OctoMesh:
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

Execute the following command to install OctoMesh

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
helm template --namespace octo --values local-cluster-sample.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx --set-file secrets.rootCa=rootca.crt octo-mesh ../octo-mesh
```

## Setup OctoMesh Adapter

OctoMesh Adapter is a service that hosts mesh pipelines and is installed in the same cluster as the core services, but for each tenant. The adapter requires a running MongoDB instance and CRATE DB for stream data.

### Create a values file to configure OctoMesh Adapter
See the [values.yaml](src/octo-mesh-adapter/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Render octo-mesh-adapter chart template locally and display the output

```bash
helm template --namespace octo --values adapter-sample.yaml octo-mesh-adapter ../octo-mesh-adapter
```

### Install OctoMesh Adapter

```bash
helm upgrade --install --namespace octo --create-namespace --values rke2-local-meshTest-adapter-values.yaml --set-file secrets.rootCa=root-ca-collection.crt --set image.tag="0.0.2406.3001" mesh-test-adapter meshmakers/octo-mesh-adapter
```

## Setup OctoMesh Excel Add-in

OctoMesh Excel Add-In is a service that allows users to interact with OctoMesh using Excel. The add-in does not have nay prerequisites, because the connection to OctoMesh is done through Excel.

### Create a values file to configure OctoMesh Office
See the [values.yaml](src/octo-mesh-office/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Render octo-mesh-office chart template locally and display the output

```bash
helm template --namespace octo --values office-sample.yaml octo-mesh-office ../octo-mesh-office
```

### Install OctoMesh Excel Add-in

```bash
helm upgrade --install --namespace octo --create-namespace --values office-values.yaml --set image.tag="0.0.2406.3001" mesh-add-in meshmakers/octo-mesh-office
```

### Install OctoMesh Adapter

```bash
helm upgrade --install --namespace octo --create-namespace --values rke2-local-meshTest-adapter-values.yaml --set-file secrets.rootCa=root-ca-collection.crt --set image.tag="0.0.2406.3001" mesh-test-adapter meshmakers/octo-mesh-adapter
```

## Setup OctoMesh Frontend App Template

OctoMesh App Template shows the possibilities for the frontend UI provides

### Create a values file to configure app template
See the [values.yaml](src/octo-mesh-app-template/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Render octo-mesh-app-template chart template locally and display the output

```bash
helm template --namespace octo --values template-app-sample.yaml mytemplate ../octo-mesh-app-template
```

### Install OctoMesh Excel Add-in

```bash
helm upgrade --install --namespace octo --create-namespace --values office-values.yaml --set image.tag="0.0.2406.3001" mesh-add-in meshmakers/octo-mesh-office
```

## Setup OctoMesh Communication Operator

OctoMesh Communication Operator is responsible for managing adapters on edge clusters. The operator requires octo-mesh-crts to be installed.

### Create a value file to configure OctoMesh Communication Operator
See the [values.yaml](src/octo-mesh-communication-operator/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Generate CA and server certificates

For webhooks to work, the operator requires a CA certificate and key, as well as a server certificate and key. The following command can be used to generate the certificates:

```bash
octo-cli -c GenerateOperatorCertificates -o . -n octo-operator-system -s octo-mesh-op1-communication-operator
```
-n is the namespace where the operator is installed, -s is the name of the operator server, it is the combination of the release name and "communication-operator".

### Install OctoMesh CRDs

```bash
helm install --namespace octo-operator-system octo-mesh-crds ./octo-mesh-crds/
```

### Install the OctoMesh Communication Operator

```bash
helm install --namespace octo-operator-system --values ./examples/operator-sample.yaml --set-file serviceHooks.caKey=examples/ca-key.pem --set-file serviceHooks.caCrt=examples/ca.pem --set-file serviceHooks.svcKey=examples/svc-key.pem --set-file serviceHooks.svcCrt=examples/svc.pem octo-mesh-op1 --set "octo-mesh-crds.enabled=false" ./octo-mesh-communication-operator/
```
The operator requires the CRDs to be installed, but they are installed by default. To disable install the CRDs, set the `octo-mesh-crds.enabled` value to `false`.

```bash
helm install --namespace octo-operator-system --values ./examples/operator-sample.yaml --set image.tag=0.0.2408.23001-main  --set-file serviceHooks.caKey=examples/ca-key.pem --set-file serviceHooks.caCrt=examples/ca.pem --set-file serviceHooks.svcKey=examples/svc-key.pem --set-file serviceHooks.svcCrt=examples/svc.pem octo-mesh-op1 ./octo-mesh-communication-operator/
```

### Install OctoMesh Reporting

OctoMesh Reporting is a service that provides reporting capabilities for OctoMesh. This chart requires running octo-mesh core services.

### Create a value file to configure OctoMesh Reporting
See the [values.yaml](src/octo-mesh-reporting/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Render octo-mesh-reporting chart template locally and display the output

```bash
helm template --namespace octo --values reporting-sample.yaml octo-mesh-reporting ../octo-mesh-reporting
```

