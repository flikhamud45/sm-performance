
# Test parameters (default values are defined after the colons
TEST_DURATION="${test_duration:-300s}"
CONNECTIONS="${connections:-10}"
QUITE_TIME_SECONDS="${quiet_time_seconds:-120}"
ITERATIONS="${iterations:-1}"
RPS="${rps:-10}"

# light test
echo "starting HTTP test"
for ((i=1; i <= ITERATIONS; i++)); do
   echo "starting iteration number ${i} of the test"
   kubectl exec $(kubectl get pods -n workload -l app=fortio-workload -o custom-columns=:.metadata.name --no-headers) -n workload -c workload -- fortio load -a -timeout 10000ms -qps "$RPS" -c "$CONNECTIONS" -t "$TEST_DURATION"  http://simulated-server.workload.svc.cluster.local:8080/
   echo "sleeping ${QUITE_TIME_SECONDS} second"
   sleep "$QUITE_TIME_SECONDS"
done
