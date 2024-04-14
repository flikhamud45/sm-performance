# Service Mesh Performance

## Introduction
This repository contains scripts and resources that allows running performance tests on service meshes on top of OKD Kubernetes cluster.   
The tests focus on a pod-to-pod communication with or without TLS/mTLS protocol.  
This file contains instructions for installing Istio, Linkerd or Cilium service meshes. However, the tests themselves can run on any other service mesh.  

## Prerequisites
To run the scripts of this repository, ensure the following tools are installed on your local computer: 
* make - for Mac, run the following commnad in the terminal `brew install make`. For windows, visit [make for windows](https://gnuwin32.sourceforge.net/packages/make.htm) page.   
* [kubectl](https://kubernetes.io/docs/tasks/tools/).
* [oc](https://docs.openshift.com/container-platform/4.8/cli_reference/openshift_cli/getting-started-cli.html).  
* [helm](https://helm.sh/docs/intro/install/).  
* [istioctl](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl/#install-hahahugoshortcode784s2hbhb).  

## Setup the Testing Environment
### Create the Kubernetes Cluster
The tests in this repository should be run on an [OKD](https://docs.okd.io/) Kubernetes cluster.  
For detailed instructions on how to create and install an OKD cluster visit [OKD documentation](https://docs.okd.io/latest/installing/index.html).  

### Deploy the Service Mesh
In this section you will install the service mesh you want to test. If you want to run a baseline test, you can skip this part.  
Before running the installation scripts, ensure you configure the access to your cluster by setting the `KUBECONFIG` environment variable with the path to the cluster's config file.  
```shell script
export KUBECONFIG=/path/to/your/cluster/config/file
```
**Note: install one service mesh at a time and ensure you uninstall a service mesh before you install the next one.**
#### Istio
To install Istio, run the following command in your terminal:
```shell script
make deploy-istio
```
After the installation completes, ensure all the pods in the `istio-system` namespace are up and running.
```shell script
kubectl get pods -n istio-system
```
To configure Istio to inject its sidecar proxies into the workload Pods run the following commnad:
```shell script
make prepare-fortio-istio
```
The above command creates the `workload` namespace and label it with the `istio-injection:enabled` label.

#### Linkerd
To install Linkerd, run the following command in your terminal:
```shell script
make deploy-linkerd
```
After the installation completes, ensure all the pods in the `linkerd` namespace are up and running.
```shell script
kubectl get pods -n linkerd
```
To configure Linkerd to inject its sidecar proxies into the workload Pods run the following commnad:
```shell script
make prepare-fortio-linkerd
```
The above command creates the `workload` namespace and label it with the `linkerd.io/inject=enabled` label.

#### Cilium
For instructions on how to install Cilium on an OKD cluster visit [here](https://docs.cilium.io/en/latest/installation/k8s-install-openshift-okd/#k8s-install-openshift-okd).  

### Deploy the Workloads
To run the tests you need to deploy the load-generator and simulated-server in the Kubernetes cluster.  
Note: the load generator and the server are dependent on each other resources. Ensure you deploy both in order for them to run properly (deploy the load-generator first).  

#### Load Generator
To deploy the load generator, run the following script:
```shell script
make deploy-fortio
```
The above script creates the `workload` namespace (if not already created in the previous steps). Then, creates a `Deployment` resource named `fortio-workload`.  
The `Deployment` should create a `fortio-workload` Pod that contains the [Fortio](https://fortio.org/) load generator.  

#### Simulated Server
Before you deploy the simulated-server you can adjust its default values to your needs. The values file is located at the following path `tls_server/charts/simulated-server/values.yaml`.  
Make sure to change **only** the following values:  
* servertlsMode: Configure the TLS configuration of the server. Possible values: TLS, MTLS, NO_AUTH.  
* serverDelayDuration: Configure the delay of the server before returning the response. The value should be in a [Duration](https://pkg.go.dev/maze.io/x/duration#Duration) format (i.e. 100ms, 1s, etc.).   
* tcpOnlyService: A boolean (true/false) flag that determine whether to create a TCP  or HTTP Kubernetes service respectively.  

Then, to deploy the simulated server run the following script:  
```shell script
make deploy-server
```
The above script should create three resources `Deployment` that creates a Pod tha runs the simulated server, a Service and a Secret that stores the client and server certificates (for TLS/mTLS tests).  

## Run the Tests
This repository provides three kinds of tests:
1. HTTP test: client to server communication with no TLS configurations on the client/server side. Deploy the server with `servertlsMode: NO_AUTH` before running this test.  
2. TLS test: client to server communication with TLS configurations on the server side. Deploy the server with `servertlsMode: TLS` before running this test.  
3. mTLS test: client to server communication with mTLS configurations on the client/server side. Deploy the server with `servertlsMode: MTLS` before running this test.  

To run each of the tests run the following script:
1. HTTP test: `make http-test`.  
2. TLS test: `make tls-test`.  
3. mTLS test: `make mtls-test`.  

### Test parameters
The test scripts can recieve parameters that configure the tests behavior. Provide the test parameters when you run the test in the following way:  
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

For example, the following command execute an HTTP test with 5 concurrent connections and 50 requests per second. The test run 3 iterations of 300 seconds each.  
Note that the `quiet_time_seconds` parameter is omitted so its default value (120) will be used.  
```shell script
make http-test test_duration=300s iterations=3 connections=5 rps=50
```

## Collect the Results
### Access the Load Generator Results
After the test is finished, the Fortio load-genearor creates an output file in a JSON format for each iteration of the test.  
The file contains the results of the test including: requests' duration histogram, response codes, actual RPS and more.  

To access these files you should `exec` into the load-generator Pod. Follow the below steps:  
* Get the load-generator pod name by running the following command:
```shell script
kubectl get pods -n workload -l app=workload
```
* Exec into the load-generator container (make sure to replace <load-generator-pod-name> with the name you got from step 1):
```shell script
kubectl exec -i -t -n workload  <load-generator-pod-name> -c workload "--" sh -c "clear; (bash || ash || sh)"
```
The above command should open a terminal inside the load-generator container.  

* run the `ls` command to view the files in the home directory. If the tests finished successfully, you should see a JSON file for each of the test iternations. 
You can view their content by using the `cat` command (`cat <file-name>`).  

### Access OpenShift Monitoring
OpenShift's [monitoring stack](https://docs.openshift.com/container-platform/4.9/monitoring/monitoring-overview.html) provides, among other features, monitoring capabilities on the workloads running in the cluster and built-in dashboards that display the CPU and memory usage over time.  
The monitoring dashboards can be accessed via the OpenShift's console.    
Access the Pods monitoring dashboards to view the server and load-generator CPU/memory usage during the test.  
