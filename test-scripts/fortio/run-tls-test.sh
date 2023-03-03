
test_duration=300s
connections=160
quiet_time_seconds=120
test_iterations=( {1..3} )

light_rps=320

# light test
echo "starting TLS test"
for i in "${test_iterations[@]}"; do
   echo "starting iteration number ${i} of the test"
   kubectl exec $(kubectl get pods -n workload -l app=fortio-workload -o custom-columns=:.metadata.name --no-headers) -n workload -c workload -- fortio load -a -timeout 10000ms -cacert //mnt/tls/ca.crt -qps $light_rps -c $connections -t $test_duration  https://simulated-server.workload.svc.cluster.local:8080/
   echo "sleeping ${quiet_time_seconds} second"
   sleep $quiet_time_seconds
done
