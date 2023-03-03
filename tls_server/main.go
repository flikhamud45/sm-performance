package main

import (
	"crypto/tls"
	"crypto/x509"
	"log"
	"net/http"
	"os"
	"time"
)

const caPath = "/mnt/tls/ca.crt"   // path to a file that stores the CA certificate who signed the client certificate (for mtls)
const crtPath = "/mnt/tls/tls.crt" // path to a file that stores the server certificate
const keyPath = "/mnt/tls/tls.key" // path to a file that stores the server private key
const listenOn = ":8080"

var DelayDuration = 0 * time.Second

//const healthListenOn = ":9000"
//const healthPath = "/healthz"

func createServerConfigWithTls(serverCrtPath, serverKeyPath string) (*tls.Config, error) {
	cert, err := tls.LoadX509KeyPair(serverCrtPath, serverKeyPath)
	if err != nil {
		log.Println("Failed to load x509 key pair", err)
		os.Exit(1)
	}
	return &tls.Config{
		Certificates: []tls.Certificate{cert},
		ClientAuth:   tls.NoClientCert,
	}, nil
}

func createServerConfigWithMtls(caPath, serverCrtPath, serverKeyPath string) (*tls.Config, error) {
	caCertificate, err := os.ReadFile(caPath)
	if err != nil {
		log.Println("Failed to read root CA  file", err)
		os.Exit(1)
	}

	roots := x509.NewCertPool()
	ok := roots.AppendCertsFromPEM(caCertificate)
	if !ok {
		log.Println("Failed adding CA to trusted root CA")
		os.Exit(1)
	}

	cert, err := tls.LoadX509KeyPair(serverCrtPath, serverKeyPath)
	if err != nil {
		return nil, err
	}
	return &tls.Config{
		Certificates: []tls.Certificate{cert},
		ClientAuth:   tls.RequireAndVerifyClientCert,
		ClientCAs:    roots,
	}, nil
}

func defaultHandler(w http.ResponseWriter, r *http.Request) {
	time.Sleep(DelayDuration)
	_, err := w.Write([]byte("Service Mesh Performance Tests"))
	if err != nil {
		log.Print("fail to write response body", err)
	}
}

func getDelayDuration(delay string) time.Duration {
	result := 0 * time.Second
	if delay != "" {
		delayDuration, err := time.ParseDuration(delay)
		if err != nil {
			log.Printf("Invalid delay input")
		} else {
			result = delayDuration
		}
	}
	return result
}

func main() {
	http.HandleFunc("/", defaultHandler)

	delay := os.Getenv("SERVER_DELAY")
	if delay != "" {
		DelayDuration = getDelayDuration(delay)
	}

	mode := os.Getenv("TLS_MODE") // possible values: TLS, MTLS, NO_AUTH
	var err error
	var config *tls.Config
	switch mode {
	case "MTLS":
		log.Printf("activate server with mTLS")
		config, err = createServerConfigWithMtls(caPath, crtPath, keyPath)
	case "TLS":
		log.Printf("activate server with TLS")
		config, err = createServerConfigWithTls(crtPath, keyPath)
	case "NO_AUTH":
		log.Printf("activate server without TLS")
	default:
		log.Printf("unknown TLS_MODE, activate server without TLS")
	}
	if err != nil {
		log.Println(err)
		os.Exit(1)
	}
	var server *http.Server
	if config != nil {
		server = &http.Server{
			Addr:      listenOn,
			TLSConfig: config,
		}
		err = server.ListenAndServeTLS("", "")
	} else {
		server = &http.Server{
			Addr: listenOn,
		}
		err = server.ListenAndServe()
	}
	if err != nil {
		log.Fatalf("failed to activate server on port %s", listenOn)
	}
}

//func activateHealthServer() {
//	http.HandleFunc(healthPath, func(w http.ResponseWriter, r *http.Request) {
//		w.WriteHeader(http.StatusOK)
//		_, err := w.Write([]byte("ok"))
//		if err != nil {
//			log.Printf("error occurred when writing response to /healthz call : %s", err.Error())
//		}
//	})
//	go func() {
//		log.Printf("health server listineing on port %s and path %s", healthListenOn, healthPath)
//		err := http.ListenAndServe(healthListenOn, nil)
//		if err != nil {
//			log.Fatalf("failed to activate health server on port %s", healthListenOn)
//		}
//	}()
//}
