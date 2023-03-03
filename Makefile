
PROJECT_NAME ?= "" # GCP Project name
DEPLOYMENT_NAME ?= "sm-perf-testbed" # Deployment name in GCP Deployment Manager
DEPLOYMENT_CONFIG_FILE ?= "gke.yaml"
ZONE ?= "us-central1-c"
SVC_PATCH = '{"spec":{"type":"ClusterIP"}}'

login:
	gcloud auth login
	gcloud config set project $(PROJECT_NAME)

create-cluster:
	gcloud deployment-manager deployments create $(DEPLOYMENT_NAME) --config $(DEPLOYMENT_CONFIG_FILE)

kubectx:
	gcloud container clusters get-credentials $(DEPLOYMENT_NAME) --zone $(ZONE)

meshery:
	mesheryctl system start
	sleep 45
	kubectl patch svc/meshery -n meshery -p $(SVC_PATCH)
	kubectl patch svc/meshery-broker -n meshery -p $(SVC_PATCH)
	kubectl patch deployment/meshery-cilium -n meshery -p '{ "spec": { "template": { "spec": { "serviceAccountName": "meshery-custom" } } } }'
	oc adm policy add-scc-to-user privileged  -z meshery-custom -n meshery
	oc adm policy add-scc-to-user privileged  -z meshery-operator -n meshery


monitoring:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm install sm -f ./monitoring-values.yaml prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
	kubectl apply -f dashboards/


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

deploy-cilium:
    cilium install --kube-proxy-replacement=strict --helm-set-string extraConfig.enable-envoy-config=true

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
	#oc adm policy add-scc-to-group privileged system:serviceaccounts:istio-system
	#oc adm policy add-scc-to-group privileged system:serviceaccounts:istio-cni
	# To disable protocol sniffing add the following --set values.pilot.enableProtocolSniffingForOutbound=false --set values.pilot.enableProtocolSniffingForInbound=false
	# Remember to also explicitly use the named Service port (Set tcpOnlyService=true on the simulated server)
	istioctl install --set profile=openshift --set values.pilot.enableProtocolSniffingForOutbound=false --set values.pilot.enableProtocolSniffingForInbound=false
	kubectl patch svc/istio-ingressgateway -n istio-system -p $(SVC_PATCH)
	#kubectl patch svc/istio-ingressgateway -n istio-system -p '{"spec":{"type":"ClusterIP"}}'
	oc -n istio-system expose svc/istio-ingressgateway --port=http2
	oc adm policy add-scc-to-group anyuid system:serviceaccounts:workload
