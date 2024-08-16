package main

import (
	"crypto/tls"
	"crypto/x509"
	"log"
	"net"
	"os"
	"strconv"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/reflection"

	"github.com/kedify/examples/samples/grpc-responder/helloservice"
	pb "github.com/kedify/examples/samples/grpc-responder/proto"
)

func main() {
	port, delay, message := readEnvVariables()
	startGRPCServer(port, delay, message)
}

func readEnvVariables() (string, time.Duration, string) {
	port := os.Getenv("PORT")
	if port == "" {
		port = "50051"
	}

	delayEnv := os.Getenv("RESPONSE_DELAY")
	delaySeconds := 0.0
	if delayEnv != "" {
		parsedDelay, err := strconv.ParseFloat(delayEnv, 64)
		if err == nil && parsedDelay >= 0 {
			delaySeconds = parsedDelay
		} else {
			log.Printf("Invalid delay value '%s', using 0 seconds", delayEnv)
		}
	}
	delay := time.Duration(delaySeconds * float64(time.Second))

	message := os.Getenv("RESPONSE_MESSAGE")
	if message == "" {
		message = "Hello from Kedify"
	}

	return port, delay, message
}

func startGRPCServer(port string, delay time.Duration, message string) {
	lis, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	var opts []grpc.ServerOption

	if os.Getenv("TLS_ENABLED") == "true" {
		certFile := os.Getenv("TLS_CERT_FILE")
		keyFile := os.Getenv("TLS_KEY_FILE")

		if certFile == "" || keyFile == "" {
			log.Fatalf("TLS is enabled, but TLS_CERT_FILE or TLS_KEY_FILE is not set")
		}

		creds, err := loadTLSCredentials(certFile, keyFile)
		if err != nil {
			log.Fatalf("failed to load TLS credentials: %v", err)
		}

		opts = append(opts, grpc.Creds(creds))
	}

	grpcServer := grpc.NewServer(opts...)
	pb.RegisterHelloServiceServer(grpcServer, &helloservice.Server{
		Delay:   delay,
		Message: message,
	})
	reflection.Register(grpcServer)

	log.Printf("Server is listening on port %s with delay %.2f seconds and message '%s'", port, delay.Seconds(), message)
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}

func loadTLSCredentials(certFile, keyFile string) (credentials.TransportCredentials, error) {
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return nil, err
	}

	certPool := x509.NewCertPool()
	pemCert, err := os.ReadFile(certFile) // Updated to use os.ReadFile
	if err != nil {
		return nil, err
	}

	if !certPool.AppendCertsFromPEM(pemCert) {
		return nil, err
	}

	config := &tls.Config{
		Certificates: []tls.Certificate{cert},
		ClientAuth:   tls.NoClientCert,
		ClientCAs:    certPool,
	}

	return credentials.NewTLS(config), nil
}