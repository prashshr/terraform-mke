#!/usr/bin/env bash

NODE="${1:-34.254.91.201}"
SSH_KEY="${2:-./ps-mke-aws.pem}"
SSH_USER="${3:-ec2-user}"

echo "======================================================"
echo "MKE4 / k0s Runtime Flag Verification"
echo "Node: $NODE"
echo "======================================================"

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ${SSH_USER}@${NODE} <<'EOF'

echo
echo "================ kube-apiserver ================"
ps -ef | grep kube-apiserver | grep -v grep | tr ' ' '\n' | egrep --color=never \
'tls-|watch-cache|storage-media-type|feature-gates|enable-admission|event-ttl|authorization-mode|authentication-config'

echo
echo "================ kubelet ======================="
ps -ef | grep kubelet | grep -v grep | tr ' ' '\n' | egrep --color=never \
'image-gc|eviction|max-pods|logging-format|node-status-update|streaming-connection|cpu-manager|registry-qps|event-qps|tls-'

echo
echo "================ scheduler ====================="
ps -ef | grep kube-scheduler | grep -v grep | tr ' ' '\n' | egrep --color=never \
'permit-port-sharing|profiling|logging-format|feature-gates|v='

echo
echo "================ controller-manager ============"
ps -ef | grep kube-controller-manager | grep -v grep | tr ' ' '\n' | egrep --color=never \
'profiling|logging-format|feature-gates|concurrent-|leader-elect|v='

echo
echo "================ k0s controller ================"
ps -ef | grep "k0s controller" | grep -v grep | tr ' ' '\n' | egrep --color=never \
'image-gc|logging-format|max-pods|registry-qps|event-qps|streaming-connection'

echo
echo "================ kubelet worker-profile ========"
grep -E \
'tlsCipherSuites|tlsMinVersion|maxPods|eventRecordQPS|streamingConnectionIdleTimeout|kubeReserved|seccompDefault' \
/var/lib/k0s/worker-profile.yaml

echo
echo "================ admission webhooks ============"
kubectl get validatingwebhookconfigurations --no-headers 2>/dev/null | wc -l
kubectl get mutatingwebhookconfigurations --no-headers 2>/dev/null | wc -l

echo
echo "================ TLS verification =============="
echo | openssl s_client -connect 127.0.0.1:6443 -tls1_2 2>/dev/null | grep "Cipher is"

echo
echo "================ SUMMARY ======================="
echo "If all expected flags appear above, MKE3 -> MKE4 flag migration succeeded."

EOF
