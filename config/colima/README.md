# Colima disk retention

These settings are host/VM configuration, not Flux resources. Merging changes
or running `just flux-reconcile` does not activate them. A maintenance window
and separate approval are required before restarting Colima, recreating
containers or running the live checks below.

## Policies

| Data | Policy | Scope |
| --- | --- | --- |
| Unused images | kubelet `imageMaximumGCAge: 24h` | Existing image GC; disk thresholds remain 85/80 |
| Container stdout/stderr | Docker `json-file`, `max-size: "5m"`, `max-file: "3"` | Newly created containers using the daemon defaults |
| Persistent journal | `SystemMaxUse=1G`, `SystemKeepFree=1G`, `MaxRetentionSec=7day` | `/var/log/journal` in the VM |
| Build cache | `builder.gc.enabled: true`, `defaultKeepStorage: "5GB"` | Docker Engine's built-in BuildKit builder (`docker` driver) |

Docker rotates below kubelet's default 10Mi threshold because cri-dockerd cannot
reopen container logs. Keep `json-file` for CRI compatibility. Fast log bursts
can still race kubelet rotation; verify behavior rather than assuming that the
kubelet's `containerLogMaxSize` and `containerLogMaxFiles` enforce Docker limits.

The journal drop-in is written atomically to
`/etc/systemd/journald.conf.d/60-local-helm-retention.conf`. Provisioning restarts
journald after installation because the service is already running during Lima
system provisioning. A restart failure is reported; rerunning provisioning
retries it. Other journal settings and drop-ins are left intact.

Journal retention deletes archived files, not individual entries. Active files
can keep usage above 1GiB temporarily; seven days is not a minimum preservation
guarantee. `SystemKeepFree` constrains journald, not other writers. Runtime
journals under `/run/log/journal` keep their existing defaults.

The 5GB builder setting influences native GC policies; it is not a filesystem
quota or an immediate guarantee of freed space. Separate `docker-container` or
remote BuildKit builders have their own policies and are not configured here.
Cache eviction can make subsequent builds slower. No CronJob, manual prune,
volume cleanup or application-data retention is added.

## Offline checks

```sh
ruby tests/colima_gc_test.rb
```

Tests execute the actual provision scripts against temporary directories and
stub `systemctl`; no real services, images or volumes are touched. They cover
fresh installation, updates, repeat runs, write failures, restart failure/retry
and the Docker policy values. CI runs the same tests.

With the VM already running, this optional parser-only check validates the
Docker subsection using the installed Engine. It does not start/reload Docker
or write its configuration:

```sh
ruby -ryaml -rjson -e '
  puts JSON.generate(YAML.load_file("config/colima/values.yaml").fetch("docker"))
' | colima ssh --profile default -- dockerd --validate --config-file /dev/stdin
```

## Approved activation checklist

The commands below target the `default` profile and `colima` contexts. Do not
run them against a different profile without reviewing its paths and policies.

1. Record baseline free space, node/workload health, failed Jobs, image/cache
   usage and each container's logging options. Use `df` inside the VM as well
   as on the host: the root and container-data disks are separate filesystems.
   Do not export container environment variables or credentials into reports.
2. Compare `values.yaml` with the live profile; `just colima-restart` overwrites
   that profile. Preserve any unrelated local settings before proceeding.
   Back up the live profile outside Git with restrictive permissions:

   ```sh
   umask 077
   backup_dir="$(mktemp -d "$HOME/.colima/retention-backup.XXXXXX")"
   cp "$HOME/.colima/default/colima.yaml" "$backup_dir/colima.yaml"
   printf '%s\n' "$backup_dir"
   ```

   Also save any pre-existing journal/image-GC drop-ins, or record that they
   were absent. Preserve logs needed for diagnosis before enabling retention:
   older journal files and build cache may be deleted automatically on startup.
3. Establish how non-Kubernetes containers, especially `cli-proxy-api`, are
   recreated from their existing Compose/launcher definitions. Preserve their
   mounts, environment, ports, networks, command and restart policy. Stop if a
   recoverable definition is unavailable; do not reconstruct it blindly.
4. During the approved outage, run `just colima-restart` once to apply the
   image, logging, journal and builder policies together. Check startup output
   for provisioning errors; do not treat a running VM alone as proof of success.
5. Confirm the node and workloads recover to their recorded baseline. Inspect
   every existing container's `.HostConfig.LogConfig`: daemon defaults only
   affect newly created containers. For those still missing `5m`/`3`, perform
   workload-specific, sequential recreation, checking readiness between each.
   Docker restart alone does not update a container's saved logging options.
6. Verify the effective settings using the checks below. Run a disposable,
   uniquely named logging-test container using a suitable image already present
   locally, with total output bounded to tens of MB. Verify Docker rotates logs
   and keeps at most three files, then remove only that test container. Do not
   truncate, rename or remove Docker-managed log files by hand.
7. Check for fresh K3s `Failed to rotate log` / `ReopenContainerLog` errors under
   representative logging load. Compare disk usage after native GC has run.
   If failures continue, investigate before declaring logging fixed; do not
   disable kubelet logging or delete logs to conceal the errors.

## Verification

Read the merged Docker settings without printing unrelated daemon configuration:

```sh
colima ssh --profile default -- sudo cat /etc/docker/daemon.json \
  | ruby -rjson -e '
      puts JSON.parse(STDIN.read).slice("log-driver", "log-opts", "builder").to_json
    '
```

Use `docker --context colima buildx ls` to identify the `docker` driver builder
and inspect its GC policies with `buildx inspect` (without `--bootstrap`).
Compare `docker --context colima system df` before/after GC, but do not add image
and build-cache reclaimable totals: shared data may overlap.

```sh
colima ssh --profile default -- sudo systemd-analyze cat-config systemd/journald.conf
colima ssh --profile default -- systemctl is-active systemd-journald.service
colima ssh --profile default -- sudo journalctl --disk-usage
colima ssh --profile default -- df -h / /mnt/lima-colima
df -h "$HOME"
```

Check the merged journal configuration for overrides after the owned drop-in.
Use the root README's `configz` check to verify kubelet's effective 24h image
policy. Configuration inspection alone does not prove live retention works.

## Rollback

Restore the previous Docker policy in the profile and the previous journal
drop-in. If the journal drop-in was absent before activation, remove only
`60-local-helm-retention.conf` while the VM is still running. Reverting the
provisioning block alone does not remove an already-written VM file.

After restoring the saved profile, use `colima stop --profile default` followed
by `colima start --profile default`. Do not use `just colima-restart` until the
repository configuration is reverted too, as it would overwrite the restored
profile. Recreate affected containers from their original definitions if their
previous logging policy must also be restored.

This rollback leaves the existing image-GC drop-in in place. To disable that
policy as well, follow the root README's `imageMaximumGCAge: 0s` procedure.
Already deleted logs cannot be restored by changing configuration; cache must
be rebuilt. Volumes, PVCs, database files and user uploads are never cleanup
targets of these procedures.

## References

- [Docker JSON logs](https://docs.docker.com/engine/logging/drivers/json-file/)
- [BuildKit garbage collection](https://docs.docker.com/build/cache/garbage-collection/)
- [journald limits](https://www.freedesktop.org/software/systemd/man/latest/journald.conf.html)
