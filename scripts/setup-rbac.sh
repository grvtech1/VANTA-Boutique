# =============================================================================
# Phase 6: RBAC (Role-Based Access Control)
# =============================================================================
# WHAT IS RBAC?
#   "WHO can do WHAT on WHICH resources"
#
#   Example:
#     WHO:   developer-gaurav (ServiceAccount)
#     WHAT:  get, list, create pods
#     WHICH: namespace developer-sandbox only
#
# THE 4 RBAC OBJECTS:
#   1. Role           = permissions within ONE namespace
#   2. ClusterRole    = permissions across ALL namespaces
#   3. RoleBinding    = assigns a Role to a user/SA
#   4. ClusterRoleBinding = assigns ClusterRole to a user/SA
#
# PRINCIPLE OF LEAST PRIVILEGE:
#   Give the MINIMUM permissions needed. Never give cluster-admin
#   to someone who only needs to deploy pods in their namespace.
# =============================================================================

export KUBECONFIG=/home/gaurav/online-boutique/kubeconfig-aws
K=/home/gaurav/.local/bin/kubectl

echo "=== PHASE 6: RBAC (Role-Based Access Control) ==="
echo ""

# --- Step 1: Create developer-sandbox namespace ---
echo "--- Step 1: Creating developer-sandbox namespace ---"
$K create namespace developer-sandbox --dry-run=client -o yaml | $K apply -f -
echo ""

# --- Step 2: Create ServiceAccount ---
echo "--- Step 2: Creating ServiceAccount 'sandbox-developer' ---"
cat <<'EOF' | $K apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sandbox-developer
  namespace: developer-sandbox
  labels:
    purpose: rbac-learning
EOF
echo ""

# --- Step 3: Create Role (what actions are allowed) ---
echo "--- Step 3: Creating Role 'pod-manager' ---"
cat <<'EOF' | $K apply -f -
# This Role allows managing pods and services in developer-sandbox ONLY.
# It does NOT allow accessing secrets, configmaps, or other namespaces.
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-manager
  namespace: developer-sandbox
rules:
# Can view, create, delete pods
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch", "create", "delete"]
# Can view services
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list", "watch"]
# Can view deployments
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
# CANNOT: access secrets, configmaps, persistent volumes
# CANNOT: delete deployments, modify services
# CANNOT: access any other namespace
EOF
echo ""

# --- Step 4: Create RoleBinding (who gets the role) ---
echo "--- Step 4: Creating RoleBinding ---"
cat <<'EOF' | $K apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-binding
  namespace: developer-sandbox
subjects:
# WHO gets this role
- kind: ServiceAccount
  name: sandbox-developer
  namespace: developer-sandbox
roleRef:
  # WHICH role they get
  kind: Role
  name: pod-manager
  apiGroup: rbac.authorization.k8s.io
EOF
echo ""

# --- Step 5: TEST PERMISSIONS ---
echo "--- Step 5: Testing RBAC permissions ---"
echo ""
SA="system:serviceaccount:developer-sandbox:sandbox-developer"

echo "TEST 1: Can developer create pods in sandbox?"
$K auth can-i create pods --as=$SA -n developer-sandbox
echo ""

echo "TEST 2: Can developer list pods in sandbox?"
$K auth can-i list pods --as=$SA -n developer-sandbox
echo ""

echo "TEST 3: Can developer view pod logs in sandbox?"
$K auth can-i get pods/log --as=$SA -n developer-sandbox
echo ""

echo "TEST 4: Can developer access SECRETS in sandbox? (should be NO)"
$K auth can-i get secrets --as=$SA -n developer-sandbox
echo ""

echo "TEST 5: Can developer access BOUTIQUE namespace? (should be NO)"
$K auth can-i get pods --as=$SA -n boutique
echo ""

echo "TEST 6: Can developer delete NODES? (should be NO)"
$K auth can-i delete nodes --as=$SA
echo ""

echo "TEST 7: Can developer access kube-system? (should be NO)"
$K auth can-i get pods --as=$SA -n kube-system
echo ""

echo "=== PHASE 6 COMPLETE ==="
echo "  Namespace: developer-sandbox"
echo "  ServiceAccount: sandbox-developer"
echo "  Role: pod-manager (pods + services, read-only deployments)"
echo "  RoleBinding: developer-binding"
echo "  Least privilege enforced!"
