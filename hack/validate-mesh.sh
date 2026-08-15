#!/usr/bin/env bash
# =============================================================================
# validate-mesh.sh — end-to-end validation of the Mesh node on a real cluster.
#
# NOT part of the deployment. This is the test harness used to verify the
# manifest behaves correctly against a live kubelet + a REAL Mesh node token.
#
# Usage:
#   export MESH_NODE_TOKEN="<real token from Networking > Mesh, or terraform output>"
#   ./hack/validate-mesh.sh                      # full run
#   NS=other ./hack/validate-mesh.sh             # different namespace
#   ./hack/validate-mesh.sh --probes-only        # skip deploy, just re-check probes
#
# Safe to re-run. Cleans up its own A/B test pods. Does NOT delete your node.
# =============================================================================
set -uo pipefail

NS="${NS:-cloudflare-mesh}"
IMAGE="${IMAGE:-cloudflare/mesh:2026.7.0}"
POD="cloudflare-mesh-0"
PASS=0; FAIL=0; WARN=0
ok()   { echo "  ✓ $*"; PASS=$((PASS+1)); }
bad()  { echo "  ✗ $*"; FAIL=$((FAIL+1)); }
warn() { echo "  ! $*"; WARN=$((WARN+1)); }
hdr()  { echo; echo "── $* ─────────────────────────────────────────"; }

command -v kubectl >/dev/null || { echo "kubectl not found"; exit 1; }
echo "context: $(kubectl config current-context)"
echo "namespace: $NS   image: $IMAGE"

# ─────────────────────────────────────────────────────────────────────────────
hdr "0. Cluster prerequisites"
NODES=$(kubectl get nodes -o name 2>/dev/null | wc -l | tr -d ' ')
[ "$NODES" -gt 0 ] && ok "$NODES node(s) reachable" || { bad "no nodes"; exit 1; }

# /dev/net/tun must exist on at least one schedulable node
kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | while read -r n; do
  [ -n "$n" ] && echo "    node: $n"
done
if kubectl get sc 2>/dev/null | grep -q '(default)'; then
  ok "default StorageClass present: $(kubectl get sc 2>/dev/null | awk '/\(default\)/{print $1}')"
else
  bad "NO default StorageClass — the StatefulSet PVC will stay Pending"
fi

# PSA: kubeadm enforces this for real
ENF=$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
if [ "$ENF" = "privileged" ]; then ok "namespace PSA enforce=privileged"
elif [ -z "$ENF" ]; then warn "namespace $NS has no PSA enforce label (cluster default applies)"
else bad "namespace PSA enforce=$ENF — mesh Pod will be REJECTED (needs privileged)"; fi

# ─────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" != "--probes-only" ]; then
hdr "1. Deploy"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label namespace "$NS" \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=privileged \
  pod-security.kubernetes.io/audit=privileged --overwrite >/dev/null
ok "namespace + PSA labels applied"

if [ -z "${MESH_NODE_TOKEN:-}" ]; then
  bad "MESH_NODE_TOKEN unset — export a REAL token or the node cannot register"
  echo "     (without it the entrypoint retries 5x then exits 1: expected, not a probe bug)"
else
  kubectl -n "$NS" delete secret cloudflare-mesh --ignore-not-found >/dev/null 2>&1
  kubectl -n "$NS" create secret generic cloudflare-mesh \
    --from-literal=MESH_NODE_TOKEN="$MESH_NODE_TOKEN" >/dev/null
  ok "Secret cloudflare-mesh created (token length ${#MESH_NODE_TOKEN})"
fi

kubectl -n "$NS" apply -k "$(dirname "$0")/../manifests/" >/dev/null && ok "kustomize applied"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "2. Pod scheduling / privileges / storage"
kubectl -n "$NS" wait --for=condition=PodScheduled pod/$POD --timeout=60s >/dev/null 2>&1 \
  && ok "Pod scheduled" || bad "Pod not scheduled — check PSA / admission webhooks"

for i in $(seq 1 30); do
  PH=$(kubectl -n "$NS" get pod $POD -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$PH" = "Running" ] && break; sleep 5
done
[ "${PH:-}" = "Running" ] && ok "Pod Running" || warn "Pod phase=${PH:-unknown}"

PVC=$(kubectl -n "$NS" get pvc "warp-data-$POD" -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$PVC" = "Bound" ] && ok "PVC warp-data-$POD Bound" || bad "PVC phase=$PVC"

kubectl -n "$NS" get pod $POD -o jsonpath='{.spec.containers[0].securityContext.capabilities.add}' 2>/dev/null | grep -q NET_ADMIN \
  && ok "NET_ADMIN granted" || bad "NET_ADMIN missing"
kubectl -n "$NS" exec $POD -- sh -c 'test -c /dev/net/tun' 2>/dev/null \
  && ok "/dev/net/tun present in container" || bad "/dev/net/tun NOT a char device in container"

# image pull problems show up here (corporate TLS inspection)
if kubectl -n "$NS" get events --field-selector involvedObject.name=$POD 2>/dev/null | grep -qi "x509\|ImagePullBackOff"; then
  warn "image pull errors seen — if x509, install the TLS-inspection CA into the node trust store"
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "3. warp-cli / ToS behaviour (the trap)"
TOS=$(kubectl -n "$NS" exec $POD -- sh -c 'warp-cli status 2>&1 | head -1' 2>/dev/null)
case "$TOS" in
  *"Terms of Service"*) ok "confirmed: bare 'warp-cli status' is ToS-gated → --accept-tos required" ;;
  *"Status update"*)    warn "bare status worked — image behaviour CHANGED, probes may no longer need --accept-tos" ;;
  *)                    warn "unexpected bare-status output: $TOS" ;;
esac
echo "    --accept-tos status:"
kubectl -n "$NS" exec $POD -- sh -c 'warp-cli --accept-tos status' 2>&1 | sed 's/^/      /'

# ─────────────────────────────────────────────────────────────────────────────
hdr "4. Probe correctness (as kubelet runs them)"
R_CMD="warp-cli --accept-tos status | grep -q 'Status update: Connected'"
L_CMD="warp-cli --accept-tos status >/dev/null 2>&1"

if kubectl -n "$NS" exec $POD -- sh -c "$R_CMD" 2>/dev/null; then
  ok "readiness: tunnel CONNECTED (this is the state we could not reach without a real token)"
  CONNECTED=1
else
  warn "readiness: not Connected yet (fine if still registering / token invalid)"
  CONNECTED=0
fi
kubectl -n "$NS" exec $POD -- sh -c "$L_CMD" 2>/dev/null \
  && ok "liveness passes (daemon alive)" || bad "liveness FAILS while Pod is up — would CrashLoop"

# the bug this repo fixed: does the OLD pattern false-positive?
OUT=$(kubectl -n "$NS" exec $POD -- sh -c 'warp-cli --accept-tos status' 2>/dev/null)
if echo "$OUT" | grep -qi 'disconnected'; then
  echo "$OUT" | grep -qi 'Connected' && bad "OLD grep -qi Connected matches Disconnected (regression!)" \
                                     || ok "old-pattern false positive not reproducible in this state"
fi

# kubelet's own verdict
READY=$(kubectl -n "$NS" get pod $POD -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
RESTARTS=$(kubectl -n "$NS" get pod $POD -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
echo "    kubelet: ready=$READY restarts=$RESTARTS"
if [ "$CONNECTED" = "1" ] && [ "$READY" = "true" ]; then ok "kubelet agrees: Pod is Ready while Connected"; fi
if [ "${RESTARTS:-0}" -gt 0 ]; then
  REASON=$(kubectl -n "$NS" get pod $POD -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null)
  EXIT=$(kubectl -n "$NS" get pod $POD -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}' 2>/dev/null)
  if kubectl -n "$NS" get events 2>/dev/null | grep -q "failed liveness probe"; then
    bad "restarts caused by LIVENESS probe — investigate"
  else
    warn "restarts=$RESTARTS but no liveness kill (reason=$REASON exit=$EXIT) — likely token/entrypoint self-exit"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
hdr "5. A/B: prove --accept-tos is load-bearing on a real kubelet"
for V in old new; do
  [ "$V" = old ] && C="warp-cli status >/dev/null 2>&1" || C="warp-cli --accept-tos status >/dev/null 2>&1"
  kubectl -n "$NS" delete pod "probe-$V" --ignore-not-found --wait=false >/dev/null 2>&1
  cat <<YAML | kubectl -n "$NS" apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: {name: probe-$V}
spec:
  terminationGracePeriodSeconds: 1
  containers:
    - name: mesh
      image: $IMAGE
      command: ["sh","-c","nft -f /init.nft 2>/dev/null; warp-svc >/tmp/svc.log 2>&1 & sleep 900"]
      securityContext: {capabilities: {add: [NET_ADMIN, NET_RAW]}}
      livenessProbe:
        exec: {command: ["sh","-c","$C"]}
        initialDelaySeconds: 10
        periodSeconds: 5
        failureThreshold: 2
      volumeMounts: [{name: tun, mountPath: /dev/net/tun}]
  volumes: [{name: tun, hostPath: {path: /dev/net/tun, type: CharDevice}}]
YAML
done
echo "    waiting 90s for liveness to act..."
sleep 90
RO=$(kubectl -n "$NS" get pod probe-old -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
RN=$(kubectl -n "$NS" get pod probe-new -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
echo "    flagless liveness restarts : ${RO:-?}"
echo "    --accept-tos liveness      : ${RN:-?}"
if [ "${RO:-0}" -gt 0 ] && [ "${RN:-1}" -eq 0 ]; then
  ok "A/B confirms the fix: flagless CrashLoops, --accept-tos does not"
else
  warn "A/B inconclusive (old=$RO new=$RN) — image ToS behaviour may have changed"
fi
kubectl -n "$NS" delete pod probe-old probe-new --wait=false >/dev/null 2>&1
ok "A/B test pods cleaned up"

# ─────────────────────────────────────────────────────────────────────────────
hdr "Summary"
echo "  passed: $PASS   failed: $FAIL   warnings: $WARN"
[ "$FAIL" -eq 0 ] && echo "  RESULT: PASS" || echo "  RESULT: FAIL"
echo
echo "Next (needs a real token + routes in Terraform):"
echo "  * dashboard: Networking > Mesh — node should appear Connected"
echo "  * from another Mesh participant: curl a ClusterIP in the advertised CIDR"
echo "  * confirm the route's virtual network matches the client's vnet (warp-cli vnet)"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
