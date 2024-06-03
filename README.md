# Service Mesh Performance

## Introduction
This repository contains scripts and resources for running performance tests on service meshes on top of a Kubernetes cluster.  
The tests focus on pod-to-pod communication with or without TLS/mTLS protocol.  
This file contains instructions for installing Istio, Linkerd, or Cilium service meshes. However, the tests themselves can run on any other service mesh.  

## Prerequisites
To run the scripts of this repository, ensure the following tools are installed on your local computer: 
* make - for Mac users, run the following commnad in the terminal `brew install make`. For Windows users, visit [make for windows](https://gnuwin32.sourceforge.net/packages/make.htm) page.   
* [kubectl](https://kubernetes.io/docs/tasks/tools/).
* [oc](https://docs.openshift.com/container-platform/4.8/cli_reference/openshift_cli/getting-started-cli.html).  
* [helm](https://helm.sh/docs/intro/install/).  
* [istioctl](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl/#install-hahahugoshortcode784s2hbhb) (only relevant for installing Istio service mesh).  
* [linkerd](https://linkerd.io/2.15/getting-started/#step-1-install-the-cli) (only relevant for installing Linkerd service mesh).  

## Setup the Testing Environment
### Create the Kubernetes Cluster
The tests in this repository should be run on a Kubernetes cluster, which can be hosted on your local machine or in the cloud.  
To create a Kubernetes cluster on your local machine, you can use [KIND](https://kind.sigs.k8s.io/) or [MiniKube](https://minikube.sigs.k8s.io/docs/).  
To create a Kubernetes cluster in the cloud, you can use one of the following:
* [OKD](https://docs.okd.io/latest/installing/index.html).
* [Google Kubernetes Engine](https://cloud.google.com/kubernetes-engine).
* [Amazon EKS](https://docs.aws.amazon.com/eks/).
* [Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/aks/).  

#### Creating a GKE cluster
This guide provides instructions on how to create a GKE cluster suitable for the performance tests. For other cloud providers, follow the documentation mentioned above.  
To perform this step, you will need an active GCP account with enabled billing and the [gcloud](https://cloud.google.com/sdk/docs/install) command line installed on your computer.
Note: creating a GKE cluster has financial costs billed to your GCP account. For more details on GKE pricing, visit [here](https://cloud.google.com/kubernetes-engine/pricing).  
**Important**: Before running the command below make sure to adjust the following parameters in the [Makefile](https://github.com/yanivNaor92/sm-performance/blob/main/Makefile):  
1. PROJECT_NAME -  The name of your GCP Project.  
2. DEPLOYMENT_NAME - The name of the Deployment in GCP Deployment Manager (it can be any name of your choice).  
3. ZONE - The GCP zone you would like your cluster to be deployed at (If you change this parameter make sure to change all the occurrences of the zone in the `gke.yaml` file).  

To create the GKE cluster, run the following script:  
```shell script
make deploy-gke
```
The above command should open your browser and log in to your GCP account, make sure you choose the correct account.  
Then, it will create the cluster using the GCP deployment manager and set your kube context to point to your new cluster.  

Note: the script uses the [gke.yaml](https://github.com/yanivNaor92/sm-performance/blob/main/gke.yaml) file that contains the cluster's specifications, including the Kubernetes version. Sometimes GCP decalres some versions as deprecated, which might cause the installation to fail. If you get such an error, adjust the K8S version in this file to a supported version. Check GKE [release notes](https://cloud.google.com/kubernetes-engine/docs/release-notes) for a list of the supported versions.  
Feel free to adjust other fields of this file to your needs.  
 
#### Deleteing a GKE cluster
After you are done performing your tests, it's recommended to delete the GKE cluster to prevent unnecessary costs. To delete the cluster you created in the previous step, run the following command. 
```shell script
make destroy-gke
```

### Deploy the Service Mesh
In this section you will install the service mesh you want to test. If you want to run a baseline test, you can skip this part.  
Before running the installation scripts, ensure you configure the access to your cluster by setting the `KUBECONFIG` environment variable with the path to the cluster's config file.  
```shell script
export KUBECONFIG=/path/to/your/cluster/config/file
```
**Note: install one service mesh at a time and ensure you uninstall a service mesh before you install the next one.**
#### Istio
To install Istio, run the following command in your terminal:
for OKD clusters:
```shell script
make deploy-istio-okd
```
for any other cluster:
```shell script
make deploy-istio
```
After the installation is complete, ensure all the pods in the `istio-system` namespace are up and running.
```shell script
kubectl get pods -n istio-system
```
To configure Istio to inject its sidecar proxies into the workload Pods run the following command:
for OKD clusters:
```shell script
make prepare-fortio-istio-okd
```
for any other cluster:
```shell script
make prepare-fortio-istio
```
The above command creates the `workload` namespace and labels it with the `istio-injection:enabled` label.

#### Linkerd
To install Linkerd, run the following command in your terminal:
for OKD clusters:
```shell script
make deploy-linkerd-okd
```
for any other cluster:
```shell script
make deploy-linkerd
```
After the installation is complete, ensure all the pods in the `linkerd` namespace are up and running.
```shell script
kubectl get pods -n linkerd
```
To configure Linkerd to inject its sidecar proxies into the workload Pods run the following command:
```shell script
make prepare-fortio-linkerd
```
The above command creates the `workload` namespace and labels it with the `linkerd.io/inject=enabled` label.

#### Cilium
For instructions on how to install Cilium on an OKD cluster visit [here](https://docs.cilium.io/en/latest/installation/k8s-install-openshift-okd/#k8s-install-openshift-okd).  
For instructions on how to install Cilium on an any other cluster cluster visit [here](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/).  

### Deploy the Monitoring Tools
If you created an OKD cluster, you can skip this part because OKD installation already includes monitoring tools. For any other cluster, run the following command in your terminal (make sure your working directory is at the root of this project):  
```shell script
make monitoring
```
The above command will install the monitoring tools required to monitor the containers' CPU/Memory consumption. See the [access Grafana](#access-grafana) section for instructions on how to access Grafana and relevant Dashboards.

### Deploy the Workloads
To run the tests you need to deploy the load-generator and simulated-server in the Kubernetes cluster.  
Notes:
1. The load generator and the server are dependent on each other resources. Ensure you deploy both for them to run properly (deploy the load-generator first).  
2. To ensure separation from other components deployed in the cluster such as the monitoring tools, you should define at least one Node with appropriate `taints`. The load generator and the server are already configured to tolerate those taints. For more information about taints and tolerations click [here](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/).  
To taint your Node run the following command (make sure to replace \<node-name\> with one of your Nodes' name)
```shell
kubectl taint nodes \<node-name\> node-role.kubernetes.io/workload=true:NoSchedule
```
3. The load generator and the server's Deployment resources are defined with a `nodeSelector` that ensures their Pods will be scheduled only on the designated Nodes (labeled as `group: workload`). Make sure your at least one of your Nodes is labeled with `group: workload` label.
To label your Node run the following command (make sure to replace \<node-name\> with one of your Node's name)
```shell
kubectl label nodes \<node-name\> group=workload
```

#### Load Generator
To deploy the load generator, run the following script:
for OKD clusters:
```shell script
make deploy-fortio-okd
```
for any other cluster:
```shell script
make deploy-fortio
```
The above script creates the `workload` namespace (if it was not already created in the previous steps) and a `Deployment` resource named `fortio-workload`.  
The `Deployment` should create a `fortio-workload` Pod that contains the [Fortio](https://fortio.org/) load generator.  

#### Simulated Server
Before you deploy the simulated-server, you can adjust its default values to your needs. The values file is located at the following path `tls_server/charts/simulated-server/values.yaml`.  
Make sure to change **only** the following values:  
* servertlsMode: Configure the TLS configuration of the server. Possible values: TLS, MTLS, NO_AUTH.  
* serverDelayDuration: Configure the delay of the server before returning the response. The value should be in a [Duration](https://pkg.go.dev/maze.io/x/duration#Duration) format (i.e. 100ms, 1s, etc.).   
* tcpOnlyService: A boolean (true/false) flag that determines whether to create a TCP  or HTTP Kubernetes service respectively.  

Then, to deploy the simulated server, run the following script:  
```shell script
make deploy-server
```
The above script should create three resources: `Deployment`, which creates a Pod that runs the simulated server, a `Service`, and a `Secret` that stores the client and server certificates (for TLS/mTLS tests).  

The source code of the simulated server can be found in the `tls_server` folder of this repository.  

## Run the Tests
This repository provides three kinds of tests:
1. HTTP test: client-to-server communication with no TLS configurations on the client/server side. Deploy the server with `servertlsMode: NO_AUTH` before running this test.  
2. TLS test: client-to-server communication with TLS configurations on the server side. Deploy the server with `servertlsMode: TLS` before running this test.  
3. mTLS test: client-to-server communication with mTLS configurations on the client/server side. Deploy the server with `servertlsMode: MTLS` before running this test.  

To run each of the tests run the following script:
1. HTTP test: `make http-test`.  
2. TLS test: `make tls-test`.  
3. mTLS test: `make mtls-test`.  
Make sure to adjust the `servertlsMode` to match the test you want to run. Otherwise, requests might fail.  

### Test parameters
The test scripts can receive parameters that configure the test's behavior. Provide the test parameters when you run the test in the following way:  
```shell script
make <test-name> <parameter-name>=<parameter-value>
``` 
The available parameters are described in the following table.  

| No. | Parameter          | Type     | Description                                                                    | Default Value |
|-----|--------------------|----------|--------------------------------------------------------------------------------|---------------|
| 1   | test_duration      | Duration | The duration of the test                                                       | 300s          |
| 2   | connections        | int      | The number of concurrent connections between the load-generator and the server | 10            |
| 3   | quiet_time_seconds | int      | The number of seconds to wait between each test iteration                      | 120           |
| 4   | iterations         | int      | The number of test iterations                                                  | 1             |
| 5   | rps                | int      | The number of requests per second the load generator executes during the tests | 10            |

All the parameters are optional. In case a parameter is omitted, its default value will apply.  

For example, the following command executes an HTTP test with 5 concurrent connections and 50 requests per second. The test runs 3 iterations of 300 seconds each.  
Note that the `quiet_time_seconds` parameter is omitted so its default value (120) will be used.  
```shell script
make http-test test_duration=300s iterations=3 connections=5 rps=50
```
## Collect the Results
### Access the Load Generator Results
After the test is finished, the Fortio load-generator creates an output file in a JSON format for each iteration of the test.  
The file contains the results of the test including requests' duration histogram, response codes, actual RPS, and more.  

To access these files you should `exec` into the load-generator Pod. Follow the below steps:  
* Get the load-generator pod name by running the following command:
```shell script
kubectl get pods -n workload -l app=fortio-workload
```
* Exec into the load-generator container (make sure to replace `<load-generator-pod-name>` with the name you got from step 1):
```shell script
kubectl exec -i -t -n workload  <load-generator-pod-name> -c workload "--" sh -c "clear; (bash || ash || sh)"
```
The above command should open a terminal inside the load-generator container.  

* run the `ls` command to view the files in the home directory. If the tests finished successfully, you should see a JSON file for each of the test iterations. 
You can view their content by using the `cat` command (`cat <file-name>`).  

### Monitoring Tools
#### Access OpenShift Monitoring
In case you created an OKD cluster, OpenShift's [monitoring stack](https://docs.openshift.com/container-platform/4.9/monitoring/monitoring-overview.html) provides, among other features, monitoring capabilities on the workloads running in the cluster and built-in dashboards that display the CPU and memory usage over time.  
The monitoring dashboards can be accessed via the OpenShift's console.    
Access the Pods monitoring dashboards to view the server and load-generator CPU/memory usage during the test.

#### Access Grafana
If you installed Prometheus and Grafana in your cluster as mentione in this [secion](#deploy-the-monitoring-tools), you can access the Grafana dashboards with the following steps:  
1. Run the following command: 
```shell script
kubectl port-forward -n monitoring svc/sm-grafana 3000:80
```
2. Open your browser at the following address: http://localhost:3000
3. user: `admin` , password: `prom-operator`. (The credentials are stored in a Secret named `sm-grafana`).  
3. In Grafana's home page, click on the dashboards icon in the left panel.  
4. If you ran the script mentioned in the previous [section](#deploy-the-monitoring-tools) you should already have three dashboards in addition to Grafana's default dashboards. You can access them by searching their names in the search bar:
    4.1. **Nodes Monitoring** - Provides usage statistics at the Node level. 
    4.1. **Pods Monitoring** - Provides usage statistics at the Pod level. 
    4.1. **Container Monitoring** - Provides usage statistics at the Container level. 
