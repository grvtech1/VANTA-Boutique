# Secure VANTA Boutique with Network Policies

You can use [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) enforcement to control the communication between your cluster's Pods and Services.

`NetworkPolicies` are only enforced when the CNI supports them. The kubeadm cluster built by
[`/ansible`](/ansible) uses **Calico**, so they are enforced there out of the box. On a local
cluster such as [minikube](https://minikube.sigs.k8s.io/docs/start/) or kind, install a policy-capable CNI
(e.g. `minikube start --cni=calico`); the default [Kindnet](https://github.com/aojea/kindnet) CNI does not enforce them.

## Deploy VANTA Boutique with `NetworkPolicies` via Kustomize

To automate the deployment of Online Boutique integrated with fine granular `NetworkPolicies` (one per `Deployment`), you can leverage the following variation with [Kustomize](../..).

From the `kustomize/` folder at the root level of this repository, execute this command:

```bash
kustomize edit add component components/network-policies
```

This will update the `kustomize/kustomization.yaml` file which could be similar to:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- base
components:
- components/network-policies
```

You can locally render these manifests by running `kubectl kustomize .` as well as deploying them by running `kubectl apply -k .`.

Once deployed, you can verify that the `NetworkPolicies` are successfully deployed:

```bash
kubectl get networkpolicy
```

The output could be similar to:

```output
NAME                    POD-SELECTOR                AGE
adservice               app=adservice               2m58s
cartservice             app=cartservice             2m58s
checkoutservice         app=checkoutservice         2m58s
currencyservice         app=currencyservice         2m58s
deny-all                <none>                      2m58s
emailservice            app=emailservice            2m58s
frontend                app=frontend                2m58s
loadgenerator           app=loadgenerator           2m58s
paymentservice          app=paymentservice          2m58s
productcatalogservice   app=productcatalogservice   2m58s
recommendationservice   app=recommendationservice   2m58s
redis-cart              app=redis-cart              2m58s
shippingservice         app=shippingservice         2m58s
```

_Note: `Egress` is wide open in these `NetworkPolicies`. That is on purpose: egress destinations include the Kubernetes DNS, an optional Istio control plane (`istiod`) and the OTLP collector when tracing is enabled. Ingress is where the blast radius is contained (see the prod overlay, which adds a default-deny)._

## Related Resources

- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
- [Calico network policy](https://docs.tigera.io/calico/latest/network-policy/)
