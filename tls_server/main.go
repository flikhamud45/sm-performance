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
const path10kb = "/data10kb"
const path1mb = "/data1mb"
const path1gb = "/data1gb"

var filePaths = map[string]string{
	path10kb: "./www/data/10kb.dat",
	path1mb:  "./www/data/1mb.dat",
	path1gb:  "./www/data/1gb.dat",
}
var DelayDuration = 0 * time.Second

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

func bulkDataHandler(w http.ResponseWriter, r *http.Request) {
	time.Sleep(DelayDuration)
	path := filePaths[r.URL.Path]
	var fileBytes []byte
	var err error

	if path == "" {
		log.Printf("could not find relevant file for path %s\n", r.URL.Path)
	} else {
		fileBytes, err = os.ReadFile(path)
		if err != nil {
			log.Printf("failed to read file %v\n", err)
		}
	}
	_, err = w.Write(fileBytes)
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
	http.HandleFunc(path10kb, bulkDataHandler)
	http.HandleFunc(path1mb, bulkDataHandler)
	http.HandleFunc(path1gb, bulkDataHandler)

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
