# Grimmory

Grimmory is deployed by Flux to the `default` namespace and exposed at `https://books.koohyom.in`.

The local chart creates the application, dedicated MariaDB, Ingress, and `local-path` PVCs: application data 2Gi, books 30Gi, BookDrop 5Gi, and MariaDB 5Gi. The `grimmory-db` Secret is managed outside Git and is created during initial deployment.

After it is ready, create the first admin account at `https://books.koohyom.in`. Add libraries from `/books`; place automatic imports in `/bookdrop`.

```sh
flux reconcile helmrelease grimmory -n default
kubectl -n default get pods,pvc,ingress
```
