PROJECT_NAME ?= "" # GCP Project name
DEPLOYMENT_NAME ?= "sm-perf-testbed" # Deployment name in GCP Deployment Manager
DEPLOYMENT_CONFIG_FILE ?= "gke.yaml"
ZONE ?= "us-central1-c"

monitoring:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm install sm -f ./monitoring-values.yaml prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
	kubectl apply -f dashboards/


deploy-gke: gke-login create-gke-cluster kubectx

destroy-gke:
	gcloud deployment-manager deployments delete $(DEPLOYMENT_NAME) --delete-policy=DELETE

gke-login:
	gcloud auth login
	gcloud config set project $(PROJECT_NAME)

create-gke-cluster:
	gcloud deployment-manager deployments create $(DEPLOYMENT_NAME) --config $(DEPLOYMENT_CONFIG_FILE)

kubectx:
	gcloud container clusters get-credentials $(DEPLOYMENT_NAME) --zone $(ZONE)

deploy-fortio-okd:
	kubectl create ns workload --dry-run=client -o yaml | kubectl apply -f -
	oc adm policy add-scc-to-group anyuid system:serviceaccounts:workload
	kubectl apply -f fortio/loadGenerator.yaml
	kubectl apply -f fortio/rbac.yaml

deploy-fortio:
	kubectl create ns workload --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f fortio/loadGenerator.yaml

prepare-fortio-istio-okd:
	kubectl create ns workload --dry-run=client -o yaml | kubectl apply -f -
	kubectl label ns workload istio-injection=enabled
	oc -n workload create -f istio-resources/NetworkAttachmentDefinition.yaml

prepare-fortio-istio:
	kubectl create ns workload --dry-run=client -o yaml | kubectl apply -f -
	kubectl label ns workload istio-injection=enabled
	
prepare-fortio-linkerd:
	kubectl create ns workload --dry-run=client -o yaml | kubectl apply -f -
	kubectl annotate ns workload linkerd.io/inject=enabled

deploy-server:
	helm template tls_server/charts/simulated-server/ | kubectl apply -f -

deploy-linkerd-okd:
	helm repo add linkerd https://helm.linkerd.io/stable
	helm repo add linkerd-edge https://helm.linkerd.io/edge
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

deploy-linkerd:
	linkerd install-cni | kubectl apply -f -
	linkerd install --crds | kubectl apply -f -
	echo "Waiting for linkerd to be ready..."
	sleep 120 # TODO: find a better way to wait for linkerd to be ready
	linkerd install --linkerd-cni-enabled | kubectl apply -f -

deploy-istio-okd:
	oc adm policy add-scc-to-group anyuid system:serviceaccounts:istio-system
	istioctl install --set profile=openshift
	oc -n istio-system expose svc/istio-ingressgateway --port=http2
	oc adm policy add-scc-to-group anyuid system:serviceaccounts:workload

deploy-istio:
	istioctl install

http-test:
	bash test-scripts/fortio/run-http-test.sh

tls-test:
	bash test-scripts/fortio/run-tls-test.sh

mtls-test:
	bash test-scripts/fortio/run-mtls-test.sh
