# MSR4 Offline Velero + MinIO Backup Artifacts

**MSR4 Version:** 4.13.5  
**Last Validated:** July 2026  
**Purpose:** Air-gapped offline bundle for Velero-based backup of MSR4 namespace  

---

## Component Versions

| # | Component | Version | Source |
|---|-----------|---------|--------|
| 1 | Velero Helm Chart | 12.1.0 | `vmware-tanzu/velero` |
| 2 | Velero Server Image | `velero/velero:v1.18.1` | Embedded in chart v12.1.0 |
| 3 | Velero AWS Plugin | `velero/velero-plugin-for-aws:v1.14.2` | — |
| 4 | MinIO Operator Helm Chart | 7.1.1 | `minio-operator/operator` |
| 5 | MinIO Operator Image | `quay.io/minio/operator:v7.1.1` | Embedded in chart v7.1.1 |
| 6 | MinIO Tenant Helm Chart | 7.1.1 | `minio-operator/tenant` |
| 7 | MinIO Server Image | `quay.io/minio/minio:RELEASE.2025-04-08T15-41-24Z` | Embedded in chart v7.1.1 |
| 8 | Velero CLI Binary | v1.18.2 | GitHub releases (for `velero backup` commands) |
| 9 | MinIO Client (mc) | latest | `dl.min.io` (for MinIO bucket operations) |

**NOT required:**
- `velero/velero-plugin-for-csi` — not used (backup mode is filesystem, `--use-volume-snapshots=false`)
- `velero/velero-plugin-for-kopia` — embedded in Velero server image since v1.14
- `quay.io/minio/operator-sidecar` — not referenced by MinIO charts v7.x
- `postgresql-client` — logical dump is a separate workflow, not part of Velero

---

## Block 1 — Download & Save (on internet-connected host)

```bash
# === Setup workspace ===
mkdir -p ~/velero-artifacts/{bin,charts,images}
cd ~/velero-artifacts

# === 1. Velero CLI binary (v1.18.2) ===
curl -L -o bin/velero-v1.18.2-linux-amd64.tar.gz \
  https://github.com/vmware-tanzu/velero/releases/download/v1.18.2/velero-v1.18.2-linux-amd64.tar.gz
tar -xzf bin/velero-v1.18.2-linux-amd64.tar.gz -C bin/
cp bin/velero-v1.18.2-linux-amd64/velero bin/velero
chmod +x bin/velero

# === 2. MinIO Client (mc) ===
curl -L -o bin/mc https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x bin/mc

# === 3. Helm Chart: Velero v12.1.0 ===
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update
helm pull vmware-tanzu/velero --version 12.1.0 -d charts/
echo "Velero chart saved: $(ls charts/velero-*.tgz)"

# === 4. Helm Chart: MinIO Operator v7.1.1 ===
helm repo add minio-operator https://operator.min.io
helm repo update
helm pull minio-operator/operator --version 7.1.1 -d charts/
echo "MinIO Operator chart saved: $(ls charts/operator-*.tgz)"

# === 5. Helm Chart: MinIO Tenant v7.1.1 ===
helm pull minio-operator/tenant --version 7.1.1 -d charts/
echo "MinIO Tenant chart saved: $(ls charts/tenant-*.tgz)"

# === 6. Container Images ===
docker pull docker.io/velero/velero:v1.18.1
docker save docker.io/velero/velero:v1.18.1 | gzip > images/velero-v1.18.1.tar.gz

docker pull docker.io/velero/velero-plugin-for-aws:v1.14.2
docker save docker.io/velero/velero-plugin-for-aws:v1.14.2 | gzip > images/velero-plugin-for-aws-v1.14.2.tar.gz

docker pull quay.io/minio/operator:v7.1.1
docker save quay.io/minio/operator:v7.1.1 | gzip > images/minio-operator-v7.1.1.tar.gz

docker pull quay.io/minio/minio:RELEASE.2025-04-08T15-41-24Z
docker save quay.io/minio/minio:RELEASE.2025-04-08T15-41-24Z | gzip > images/minio-server-2025-04-08.tar.gz

# === Verify ===
echo "--- Binaries ---"
ls -lh bin/velero bin/mc
echo "--- Helm Charts ---"
ls -lh charts/
echo "--- Images ---"
ls -lh images/
echo "--- Total size ---"
du -sh ~/velero-artifacts
```

---

## Block 2 — Load & Deploy (on target air-gapped cluster)

```bash
# === 1. Load images into local registry or node ===
cd ~/velero-artifacts/images
for img in *.tar.gz; do
  gunzip -c "$img" | docker load
done
docker images | grep -E 'velero|minio'

# === 2. Create namespaces ===
kubectl create namespace minio-operator --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace minio-tenant --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace velero --dry-run=client -o yaml | kubectl apply -f -

# === 3. Install MinIO Operator ===
helm install minio-operator ~/velero-artifacts/charts/operator-7.1.1.tgz \
  --namespace minio-operator

# === 4. Deploy MinIO Tenant ===
helm install minio-tenant ~/velero-artifacts/charts/tenant-7.1.1.tgz \
  --namespace minio-tenant \
  --set tenant.name=minio \
  --set tenant.buckets[0].name=msr4-backup \
  --set tenant.buckets[0].policy=none \
  --set tenant.users[0].accessKey=minio \
  --set tenant.users[0].secretKey=minio123

# === 5. Create Velero credentials secret ===
kubectl create secret generic velero-secret \
  --namespace velero \
  --from-literal=cloud="[default]
aws_access_key_id=minio
aws_secret_access_key=minio123"

# === 6. Install Velero ===
helm install velero ~/velero-artifacts/charts/velero-12.1.0.tgz \
  --namespace velero \
  --set credentials.useSecret=true \
  --set credentials.existingSecret=velero-secret \
  --set configuration.backupStorageLocation[0].name=default \
  --set configuration.backupStorageLocation[0].provider=aws \
  --set configuration.backupStorageLocation[0].bucket=msr4-backup \
  --set configuration.backupStorageLocation[0].config.s3Url=http://minio.minio-tenant.svc.cluster.local:9000 \
  --set configuration.backupStorageLocation[0].config.s3ForcePathStyle=true \
  --set configuration.backupStorageLocation[0].config.insecureSkipTLSVerify=true \
  --set configuration.volumeSnapshotLocation[0].name=default \
  --set configuration.volumeSnapshotLocation[0].provider=aws \
  --set configuration.volumeSnapshotLocation[0].config.s3Url=http://minio.minio-tenant.svc.cluster.local:9000 \
  --set configuration.volumeSnapshotLocation[0].config.s3ForcePathStyle=true \
  --set configuration.volumeSnapshotLocation[0].config.insecureSkipTLSVerify=true \
  --set snapshotsEnabled=false \
  --set defaultVolumesToFsBackup=true \
  --set deployNodeAgent=true \
  --set nodeAgent.privileged=true \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.14.2 \
  --set initContainers[0].volumeMounts[0].name=plugins \
  --set initContainers[0].volumeMounts[0].mountPath=/target

# === 7. Verify ===
kubectl -n velero get pods
kubectl -n minio-operator get pods
kubectl -n minio-tenant get pods
~/velero-artifacts/bin/velero backup-location get
~/velero-artifacts/bin/velero snapshot-location get
```

---

## Transfer Checklist

Copy `~/velero-artifacts/` to the target air-gapped host, then run Block 2.

```
velero-artifacts/
├── bin/
│   ├── velero              (Linux binary)
│   └── mc                  (Linux binary)
├── charts/
│   ├── velero-12.1.0.tgz
│   ├── operator-7.1.1.tgz
│   └── tenant-7.1.1.tgz
└── images/
    ├── velero-v1.18.1.tar.gz
    ├── velero-plugin-for-aws-v1.14.2.tar.gz
    ├── minio-operator-v7.1.1.tar.gz
    └── minio-server-2025-04-08.tar.gz
```

Total: **3 charts + 4 images + 2 binaries** = 9 files. Approximately **~1.2 GB**.
