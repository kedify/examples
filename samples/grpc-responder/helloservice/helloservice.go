package helloservice

import (
    "context"
    "time"

    pb "github.com/kedify/examples/samples/grpc-responder/proto"
)

// Server implements the HelloServiceServer interface
type Server struct {
    pb.UnimplementedHelloServiceServer
    Delay   time.Duration
    Message string
}

// SayHello implements the SayHello method of the HelloServiceServer interface
func (s *Server) SayHello(ctx context.Context, req *pb.HelloRequest) (*pb.HelloResponse, error) {
    if s.Delay > 0 {
        time.Sleep(s.Delay)
    }
    return &pb.HelloResponse{Message: s.Message}, nil
}
