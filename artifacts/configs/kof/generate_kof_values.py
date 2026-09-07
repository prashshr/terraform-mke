#!/usr/bin/env python3
"""generate_kof_values.py — Generate Helm values files for Mirantis KOF chart.

Works without yq (pure Python standard library + PyYAML).
Usage:
  python3 generate_kof_values.py [--sc STORAGE_CLASS] [--kcm-ns KCM_NAMESPACE] [--profile lean|full] [--output-dir DIR]
"""
import argparse
import copy
import os
import sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not found. Install via 'pip3 install pyyaml' or system package.", file=sys.stderr)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Generate KOF Helm values files")
    parser.add_argument("--sc", default="nfs-storage", help="StorageClass name (default: nfs-storage)")
    parser.add_argument("--kcm-ns", default="k0rdent", help="k0rdent KCM namespace (default: k0rdent)")
    parser.add_argument("--profile", default="lean", choices=["lean", "full"], help="KOF profile (default: lean)")
    parser.add_argument("--storage-size", default="10Gi", help="Storage size for VictoriaMetrics/Logs (default: 10Gi)")
    parser.add_argument("--kof-dir", default=os.path.dirname(os.path.abspath(__file__)), help="Directory containing KOF configs")
    parser.add_argument("--output-dir", default=".", help="Directory to write generated values files")
    args = parser.parse_args()

    global_values_path = os.path.join(args.kof_dir, "global-values.yaml")
    profile_path = os.path.join(args.kof_dir, "profiles", f"{args.profile}.yaml")

    if not os.path.exists(global_values_path):
        print(f"ERROR: {global_values_path} not found.", file=sys.stderr)
        sys.exit(1)
    if not os.path.exists(profile_path):
        print(f"ERROR: {profile_path} not found.", file=sys.stderr)
        sys.exit(1)

    with open(global_values_path) as f:
        gv = yaml.safe_load(f)

    with open(profile_path) as f:
        profile = yaml.safe_load(f)

    # 1. Generate global-components.yaml
    components = ["operators", "mothership", "regional", "child", "storage", "collectors"]
    gc = {}
    for c in components:
        gc[f"kof-{c}"] = {"values": copy.deepcopy(gv)}
    gc.update(copy.deepcopy(gv))

    gc["kof-regional"]["values"]["operators"] = copy.deepcopy(gv)
    gc["kof-regional"]["values"]["storage"] = copy.deepcopy(gv)
    gc["kof-regional"]["values"]["collectors"] = copy.deepcopy(gv)
    gc["kof-child"]["values"]["operators"] = copy.deepcopy(gv)
    gc["kof-child"]["values"]["collectors"] = copy.deepcopy(gv)
    gc["victoria-metrics-operator"] = copy.deepcopy(gv.get("victoria-metrics-operator", {}))
    gc["victoria-metrics-operator"]["values"] = copy.deepcopy(gv.get("victoria-metrics-operator", {}))
    gc["victoria-metrics-operator"]["values"]["global"] = copy.deepcopy(gv.get("global", {}))

    # 2. Generate runtime.yaml
    runtime = {
        "global": {
            "helmRepo": {"namespace": args.kcm_ns}
        },
        "kof-mothership": {
            "values": {
                "global": {"storageClass": args.sc},
                "kcm": {"namespace": args.kcm_ns},
                "cert-manager-service-template": {"namespace": args.kcm_ns},
                "ingress-nginx-service-template": {"namespace": args.kcm_ns},
                "envoy-gateway-service-template": {"namespace": args.kcm_ns},
                "customRules": {
                    "KubeNodeNotReady": {"for": "5m", "severity": "critical"},
                    "KubeNodeUnreachable": {"for": "5m", "severity": "critical"},
                    "Watchdog": {"severity": "informational"}
                },
                "grafana": {"enabled": True}
            }
        },
        "kof-operators": {
            "values": {
                "grafana-operator": {"enabled": True}
            }
        },
        "kof-storage": {
            "values": {
                "global": {"storageClass": args.sc}
            }
        },
        "kof-collectors": {
            "values": {
                "kcm": {"namespace": args.kcm_ns},
                "global": {"clusterNamespace": args.kcm_ns},
                "opentelemetry-kube-stack": {
                    "defaultCRConfig": {
                        "config": {
                            "processors": {
                                "resource/k8sclustername": {
                                    "attributes": [
                                        {"action": "insert", "key": "k8s.cluster.name", "value": "mothership"},
                                        {"action": "insert", "key": "k8s.cluster.namespace", "value": args.kcm_ns}
                                    ]
                                }
                            },
                            "exporters": {
                                "prometheusremotewrite": {
                                    "external_labels": {
                                        "cluster": "mothership",
                                        "clusterNamespace": args.kcm_ns
                                    }
                                }
                            }
                        }
                    },
                    "nodeExporter": {"enabled": False},
                    "kubeProxy": {"enabled": False},
                    "coreDns": {"enabled": False},
                    "kubeApiServer": {"enabled": False},
                    "kube-state-metrics": {
                        "extraArgs": [
                            "--custom-resource-state-config-file=/etc/config/crd-metrics-config.yaml",
                            "--custom-resource-state-only"
                        ]
                    }
                }
            }
        }
    }

    os.makedirs(args.output_dir, exist_ok=True)

    with open(os.path.join(args.output_dir, "global-components.yaml"), "w") as f:
        yaml.dump(gc, f, default_flow_style=False)

    with open(os.path.join(args.output_dir, "profile.yaml"), "w") as f:
        yaml.dump(profile, f, default_flow_style=False)

    with open(os.path.join(args.output_dir, "runtime.yaml"), "w") as f:
        yaml.dump(runtime, f, default_flow_style=False)

    print(f"Generated global-components.yaml, profile.yaml, runtime.yaml in '{args.output_dir}'")


if __name__ == "__main__":
    main()
