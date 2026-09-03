# =============================================================================
# Patch: CurrencyService using ConfigMap + PaymentService using Secret
# =============================================================================
# This script patches both deployments to read config from ConfigMap/Secret
# instead of hardcoded env values.
#
# WHY PATCH INSTEAD OF EDIT THE YAML?
#   kubectl patch lets you modify a running deployment without touching
#   the original file. In production, you'd update the YAML in Git and
#   let ArgoCD sync it. But for learning, patching shows the immediate effect.
# =============================================================================

export KUBECONFIG=/home/gaurav/online-boutique/kubeconfig-aws
K=/home/gaurav/.local/bin/kubectl

echo "=== PHASE 3: ConfigMaps and Secrets ==="
echo ""

# --- Step 1: Verify ConfigMap and Secret exist ---
echo "--- Step 1: Verifying ConfigMap and Secret ---"
$K get configmap currency-config -n boutique
$K get secret payment-secrets -n boutique
echo ""

# --- Step 2: Patch CurrencyService to use ConfigMap ---
echo "--- Step 2: Patching CurrencyService to read from ConfigMap ---"
cat <<'EOF' | $K apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: currencyservice
  namespace: boutique
  labels:
    app: currencyservice
spec:
  selector:
    matchLabels:
      app: currencyservice
  template:
    metadata:
      labels:
        app: currencyservice
    spec:
      serviceAccountName: currencyservice
      terminationGracePeriodSeconds: 5
      securityContext:
        fsGroup: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        runAsUser: 1000
      containers:
      - name: server
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - ALL
          privileged: false
          readOnlyRootFilesystem: true
        image: gcr.io/google-samples/microservices-demo/currencyservice:v0.10.1
        imagePullPolicy: Always
        ports:
        - name: grpc
          containerPort: 7000
        # ──────────────────────────────────────────────────────
        # BEFORE: env values were HARDCODED here
        # AFTER:  env values come FROM the ConfigMap
        # ──────────────────────────────────────────────────────
        envFrom:
        - configMapRef:
            name: currency-config
        readinessProbe:
          grpc:
            port: 7000
        livenessProbe:
          grpc:
            port: 7000
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
EOF
echo ""

# --- Step 3: Patch PaymentService to use Secret ---
echo "--- Step 3: Patching PaymentService to read from Secret ---"
cat <<'EOF' | $K apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: paymentservice
  namespace: boutique
  labels:
    app: paymentservice
spec:
  selector:
    matchLabels:
      app: paymentservice
  template:
    metadata:
      labels:
        app: paymentservice
    spec:
      serviceAccountName: paymentservice
      terminationGracePeriodSeconds: 5
      securityContext:
        fsGroup: 1000
        runAsGroup: 1000
        runAsNonRoot: true
        runAsUser: 1000
      containers:
      - name: server
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - ALL
          privileged: false
          readOnlyRootFilesystem: true
        image: gcr.io/google-samples/microservices-demo/paymentservice:v0.10.1
        imagePullPolicy: Always
        ports:
        - containerPort: 50051
        env:
        - name: PORT
          value: "50051"
        - name: DISABLE_PROFILER
          value: "1"
        # ──────────────────────────────────────────────────────
        # NEW: Secret injected as environment variable
        # The pod can read this via process.env.PAYMENT_API_KEY
        # ──────────────────────────────────────────────────────
        - name: PAYMENT_API_KEY
          valueFrom:
            secretKeyRef:
              name: payment-secrets
              key: PAYMENT_API_KEY
        - name: PAYMENT_GATEWAY_URL
          valueFrom:
            secretKeyRef:
              name: payment-secrets
              key: PAYMENT_GATEWAY_URL
        readinessProbe:
          grpc:
            port: 50051
        livenessProbe:
          grpc:
            port: 50051
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
EOF
echo ""

# --- Step 4: Wait for rollout ---
echo "--- Step 4: Waiting for rollouts to complete ---"
$K rollout status deployment/currencyservice -n boutique --timeout=60s
$K rollout status deployment/paymentservice -n boutique --timeout=60s
echo ""

# --- Step 5: Verify env variables are injected ---
echo "--- Step 5: Verify ConfigMap env in CurrencyService ---"
CURRENCY_POD=$($K get pod -n boutique -l app=currencyservice -o jsonpath='{.items[0].metadata.name}')
echo "CurrencyService pod: $CURRENCY_POD"
$K get pod $CURRENCY_POD -n boutique -o jsonpath='{range .spec.containers[0].envFrom[*]}{.configMapRef.name}{"\n"}{end}'
echo "  ConfigMap reference: currency-config"
echo ""

echo "--- Step 6: Verify Secret env in PaymentService ---"
PAYMENT_POD=$($K get pod -n boutique -l app=paymentservice -o jsonpath='{.items[0].metadata.name}')
echo "PaymentService pod: $PAYMENT_POD"
$K describe pod $PAYMENT_POD -n boutique | grep -A 2 "PAYMENT_API_KEY"
echo ""

echo "=== PHASE 3 COMPLETE ==="
echo "  ConfigMap: currency-config -> currencyservice (envFrom)"
echo "  Secret: payment-secrets -> paymentservice (secretKeyRef)"
