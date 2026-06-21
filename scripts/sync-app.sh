#!/bin/bash
export PATH=/home/gaurav/.local/bin:$PATH
kubectl patch app online-boutique -n argocd --type=merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}' --kubeconfig /home/gaurav/online-boutique/kubeconfig-aws
