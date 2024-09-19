package main

import (
	"fmt"
	"log"
	"net/http"

	"github.com/gorilla/websocket"
)

type webSocketHandler struct {
	upgrader websocket.Upgrader
}

func (h *webSocketHandler) echo(w http.ResponseWriter, r *http.Request) {
	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("Error while upgrading connection: %v", err)
		return
	}
	defer func() {
		log.Println("Closing connection")
		conn.Close()
	}()
	for {
		messageType, message, err := conn.ReadMessage()
		if err != nil {
			log.Printf("Error while reading message: %v", err)
			break
		}
		resp := fmt.Sprintf("Received: %s", message)
		if err := conn.WriteMessage(messageType, []byte(resp)); err != nil {
			log.Printf("Error while writing message: %v", err)
			break
		}
	}
}

func (h *webSocketHandler) home(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, "/var/www/html/index.html")
}

func main() {
	h := &webSocketHandler{
		upgrader: websocket.Upgrader{},
	}
	http.HandleFunc("/echo", h.echo)
	http.HandleFunc("/", h.home)

	fmt.Println("Server is running on port 8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
