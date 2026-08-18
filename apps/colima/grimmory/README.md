# Grimmory

Grimmory is deployed by Flux to the `default` namespace and exposed at `https://books.koohyom.in`.

The local chart creates the application, dedicated MariaDB, Ingress, and `local-path` PVCs: application data 2Gi, books 30Gi, BookDrop 5Gi, and MariaDB 5Gi. The `grimmory-db` Secret is managed outside Git and is created during initial deployment.

After it is ready, create the first admin account at `https://books.koohyom.in`. Add libraries from `/books`; place automatic imports in `/bookdrop`.

```sh
flux reconcile helmrelease grimmory -n default
kubectl -n default get pods,pvc,ingress
```

## Korean translation sidecar

The optional `translation-sidecar` watches `/books/translations-original` for stable EPUB files, translates them with `yihong0618/bilingual_book_maker`, and atomically publishes Korean EPUB files with the same relative path under `/books/epub_kr`. Job state and resumable checkpoints live in `/books/.translation-sidecar` on the books PVC.

The sidecar defaults to the OpenAI-compatible endpoint at `http://host.docker.internal:8317/v1` and model `gpt-5.6-luna`. Every translation and polling option can be overridden under `translationSidecar.config` in [`values.yaml`](values.yaml). The API key is intentionally kept out of Git. The Colima overlay uses the locally built `grimmory-translation-sidecar:dev` image with `pullPolicy: Never`.

To reproduce the deployment on a fresh Colima VM:

1. Build `grimmory-translation-sidecar:dev` from the sidecar source repository using the Colima Docker context. Alternatively, publish it and change the image repository, tag, and pull policy.
2. Create the runtime Secret:

   ```sh
   kubectl -n default create secret generic grimmory-translator-runtime \
     --from-literal=LLM_API_KEY='replace-with-the-runtime-key'
   ```

3. Ensure `translationSidecar.enabled: true` in [`values.yaml`](values.yaml) and reconcile the release.
4. In Grimmory, register `/books/translations-original` as the source library and `/books/epub_kr` as the Korean output library. Enable watching on the output library so newly published translations are indexed.

```sh
flux reconcile helmrelease grimmory -n default
kubectl -n default logs deployment/grimmory -c translation-sidecar -f
kubectl -n default port-forward deployment/grimmory 18081:8081
# In another terminal:
curl --fail http://127.0.0.1:18081/readyz
```

Only upload works that are public domain or that you are authorized to translate.
