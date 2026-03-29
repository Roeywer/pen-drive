# Pen-drive in disconnected (air-gapped) environments

In a disconnected environment the workstation that runs Podman cannot reach `registry.redhat.io`. Prepare the scanner image on a **connected** host, move it into the isolated network, then run [`run-pen-drive-in-cluster.sh`](run-pen-drive-in-cluster.sh) the same way as online—after the image exists locally (or in your **internal mirror**).

## What you need

- A **connected** machine with Podman (or Docker) and access to Red Hat Container Registry.
- Red Hat registry credentials (e.g. `podman login registry.redhat.io` using your Red Hat account or pull secret).
- A way to transfer files into the disconnected zone (SCP, sneakernet, approved file share, etc.).
- From the OpenShift cluster: the **API URL** (`https://api.<cluster>.<domain>:6443`) and the **cluster CA** Certificate (same inputs as the script).

The image referenced by the script is:

`registry.redhat.io/pen-drive/pen-drive-scanner-rhel9:0.1`

## Image archive (tar)

### 1. On a connected host

Log in and pull:

```bash
podman login registry.redhat.io
podman pull registry.redhat.io/pen-drive/pen-drive-scanner-rhel9:0.1
```

Write a portable archive (adjust the filename if you prefer):

```bash
podman save -o pen-drive-scanner-rhel9-0.1.tar \
  registry.redhat.io/pen-drive/pen-drive-scanner-rhel9:0.1
```

Copy `pen-drive-scanner-rhel9-0.1.tar` into the disconnected environment.

### 2. On the disconnected host

Load the image:

```bash
podman load -i pen-drive-scanner-rhel9-0.1.tar
```

Optionally, get the cluster CA certificate directly from the cluster:

```bash
# Download the CA certificate
oc get configmap user-ca-bundle -n openshift-config -o jsonpath='{.data.ca-bundle\.crt}' > ca.crt
or
oc get configmap kube-root-ca.crt -n openshift-config -o jsonpath='{.data.ca\.crt}' > ca.crt
```

If `podman images` shows a **different** name (for example `localhost/...`), retag so it matches what the script expects:

```bash
podman tag <image-id-or-local-name> \
  registry.redhat.io/pen-drive/pen-drive-scanner-rhel9:0.1
```

### 3. Run the scanner

The script will prompt you for:

- The **cluster API URL** (HTTPS, for example `https://api.<cluster>.<domain>:6443`).
- The **path to the cluster CA certificate** (CA file used to verify the API).

After the container is running, **Pen-drive** will prompt for a **privileged username and password** so it can authenticate to the cluster API and run the in-cluster tests. Use credentials that meet your organization’s policy (for example a user or service account with the permissions Pen-drive needs).

From this repository:

```bash
chmod +x run-pen-drive-in-cluster.sh
./run-pen-drive-in-cluster.sh
```

With a local image present, Podman typically uses it without contacting the registry (`pull` policy `missing`). If your Podman version tries to pull anyway, run the underlying command manually with `--pull=never`, or set the pull policy in `containers.conf` for that host.

### 4. Open the HTML report

When the run finishes, the script prints where to find the **newest** report: it searches under your output directory (by default `pen-drive-mg/<cluster-name>/`, or `MG_DIR` if you set it), including timestamped folders such as `pendrive-YYYY-MM-DD_HH-MM-SS/`.

You should see something like:

```text
────────────────────────────────────────
  Check the latest HTML report
────────────────────────────────────────

  /path/to/pen-drive-mg/<cluster>/pendrive-2026-03-24_13-38-11/<cluster>-report.html

  Output directory: /path/to/pen-drive-mg/<cluster>
```

Open the **HTML file path** in a browser on the bastion, or copy that file to your workstation. The exact filename depends on the cluster ID Pen-drive reports.


### In-cluster help flags:

```bash

options:
  -h, --help            show this help message and exit
  --log-level {DEBUG,INFO,WARNING,ERROR,CRITICAL}
                        Logging level (default: INFO)
  --cluster-url CLUSTER_URL
                        OpenShift cluster API URL (e.g., https://api.your-cluster.com:6443). To find it, run 'oc whoami --show-server' command
  --insecure-skip-tls-verify [[true|false]]
                        Skip TLS certificate verification. Use alone to enable, or specify =true or =false
  --debug-rule DEBUG_RULE
                        Run specific rule in debug mode with full command output (no secret filtering). Specify rule unique name (e.g., 'ovs_interface_and_port_managed_by_network_manager') or title
                        (e.g., 'Verify that ovs interface and port are managed by network manager')
  --format {json,html}  Output format: json or html (default: html)
  ```