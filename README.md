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
2) octo-mesh-crds: This chart contains all custom resource definitions (CRDs) required by OctoMesh Communication Operator
3) octo-mesh-communication-operator: This chart contains the OctoMesh Communication Operator, which is responsible for managing adapters on edge clusters.
4) octo-mesh-demo-app: This chart contains the OctoMesh demo app.

Adapter charts now live in their respective adapter repositories and are published from there:
- `octo-mesh-adapter` — published by [`octo-mesh-adapter`](https://github.com/meshmakers/octo-mesh-adapter)
- `octo-eda-adapter` — published by [`octo-adapter-eda`](https://github.com/meshmakers/octo-adapter-eda)

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

### Create a values-file to configure OctoMesh
See the [values.yaml](src/octo-mesh/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Install OctoMesh core services

Execute the following command to install OctoMesh

```bash
helm upgrade --install --namespace octo --create-namespace --values ./src/examples/aks-cert-manager-sample.yaml --set-file services.identity.signingKey.key=IdentityServer4Auth.pfx <releaseName> meshmakers/octo-mesh
```

### Enable Data Protection key persistence for Identity Service

By default, ASP.NET Data Protection keys are stored in-memory and lost on pod restart. This causes refresh token invalidation and forces all users to re-authenticate after each redeployment. To persist keys across pod restarts, enable the `dataProtection` option:

```yaml
services:
  identity:
    dataProtection:
      enabled: true
      storageSize: "100Mi"
      storageClass: ""  # optional, uses default storage class if empty
```

This creates a PersistentVolumeClaim and mounts it at `/var/dpapi-keys` in the identity service container.

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

## Setup OctoMesh Demo App

OctoMesh Demo App shows the possibilities for the frontend UI provides

### Create a values-file to configure demo app
See the [values.yaml](src/octo-mesh-demo-app/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Render octo-mesh-demo-app chart template locally and display the output

```bash
helm template --namespace octo --values demo-app-sample.yaml mydemoapp ../octo-mesh-demo-app
```

### Install OctoMesh Excel Add-in

```bash
helm upgrade --install --namespace octo --create-namespace --values office-values.yaml --set image.tag="0.0.2406.3001" mesh-add-in meshmakers/octo-mesh-office
```

## Setup OctoMesh Communication Operator

OctoMesh Communication Operator is responsible for managing adapters on edge clusters. The operator requires octo-mesh-crds to be installed.

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

### Running multiple operators on one cluster (edge devices)

When deploying multiple operator instances onto the same Kubernetes cluster — typically one per target communication controller on an edge device — each instance must be isolated to its own namespace. Otherwise all operators watch every `CommunicationPool` CR cluster-wide and race on reconciliation.

Two values switch the chart from cluster-wide to namespace-scoped mode:

| Value | Default | Namespace-scoped mode |
|-------|---------|------------------------|
| `rbac.scope` | `cluster` | `namespace` — emits `Role` + `RoleBinding` in `.Release.Namespace` instead of `ClusterRole` + `ClusterRoleBinding` |
| `operator.watchNamespace` | _(empty — watch all)_ | namespace name — sets `OPERATOR__WATCHNAMESPACE`, restricting the CR watcher to that namespace |

Example: install one operator per target cluster, each into its own namespace:

```bash
helm install --namespace octo-mesh-test-2 --create-namespace \
  --set rbac.scope=namespace \
  --set operator.watchNamespace=octo-mesh-test-2 \
  octo-mesh-op-test-2 ./octo-mesh-communication-operator/

helm install --namespace octo-mesh-prod-1 --create-namespace \
  --set rbac.scope=namespace \
  --set operator.watchNamespace=octo-mesh-prod-1 \
  octo-mesh-op-prod-1 ./octo-mesh-communication-operator/
```

The two operators stay completely isolated — their RBAC reaches only their own namespace, and the watcher only sees `CommunicationPool` CRs in that namespace.

### Install Schema Provider

Schema Provider is a small container that provides construction kit schema files as a Web API.

### Create a value file to configure Schema Provider
See the [values.yaml](src/octo-mesh-schema-provider/values.yaml) file for configuration options.
Examples are available in the [example's](src/examples) directory.

### Render octo-mesh-schema-provider chart template locally and display the output

```bash
helm template --namespace octo --values schema-provider-sample.yaml schema-provider ../octo-mesh-schema-provider
```