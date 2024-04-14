
#monitoring:
#	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
#	helm repo update
#	helm install sm -f ./monitoring-values.yaml prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
#	kubectl apply -f dashboards/


deploy-fortio:
	kubectl create ns workload --dry-run=client -o yaml | kubectl apply -f -
	oc adm policy add-scc-to-group anyuid system:serviceaccounts:workload
	kubectl apply -f fortio/

prepare-fortio-istio:
	kubectl create ns workload --dry-run=client -o yaml | kubectl apply -f -
	kubectl label ns workload istio-injection=enabled
	oc -n workload create -f istio-resources/NetworkAttachmentDefinition.yaml

prepare-fortio-linkerd:
	kubectl create ns workload --dry-run=client -o yaml | kubectl apply -f -
	kubectl annotate ns workload linkerd.io/inject=enabled

deploy-server:
	helm template tls_server/charts/simulated-server/ | kubectl apply -f -

deploy-linkerd:
	oc new-project linkerd-cni
	oc annotate ns linkerd-cni linkerd.io/inject=disabled
	oc adm policy add-scc-to-user privileged -z linkerd-cni -n linkerd-cni
	helm install linkerd2-cni --set installNamespace=false --set destCNIBinDir=/var/lib/cni/bin --set destCNINetDir=/etc/kubernetes/cni/net.d linkerd/linkerd2-cni
	# prepare linkerd
	oc new-project linkerd
	oc annotate ns linkerd linkerd.io/inject=disabled
	oc label ns linkerd linkerd.io/control-plane-ns=linkerd linkerd.io/is-control-plane=true config.linkerd.io/admission-webhooks=disabled
	# deploy policies
	oc adm policy add-scc-to-user privileged -z default -n linkerd
	oc adm policy add-scc-to-user privileged -z linkerd-destination -n linkerd
	oc adm policy add-scc-to-user privileged -z linkerd-identity -n linkerd
	oc adm policy add-scc-to-user privileged -z linkerd-proxy-injector -n linkerd
	oc adm policy add-scc-to-user privileged -z linkerd-heartbeat -n linkerd
	# install CRDs
	helm install linkerd2 -n linkerd linkerd/linkerd-crds
	# deploy linkerd
	exp=$(date -d '+8760 hour' +"%Y-%m-%dT%H:%M:%SZ")
	helm install linkerd2 --set cniEnabled=true --set installNamespace=false --set-file identityTrustAnchorsPEM=linkerd-certs/ca.crt --set-file identity.issuer.tls.crtPEM=linkerd-certs/issuer.crt --set-file identity.issuer.tls.keyPEM=linkerd-certs/issuer.key --set identity.issuer.crtExpiry=$exp linkerd/linkerd2


deploy-istio:
	oc adm policy add-scc-to-group anyuid system:serviceaccounts:istio-system
	istioctl install --set profile=openshift
	oc -n istio-system expose svc/istio-ingressgateway --port=http2
	oc adm policy add-scc-to-group anyuid system:serviceaccounts:workload

http-test:
	sh test-scripts/fortio/run-http-test.sh

tls-test:
	sh test-scripts/fortio/run-tls-test.sh

mtls-test:
	sh test-scripts/fortio/run-mtls-test.sh
