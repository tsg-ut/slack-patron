package main
import (
	"github.com/rwynn/monstache/v6/monstachemap"
	"net/http"
	"encoding/json"
	"bytes"
	"log"
	"io"
)

type TextEmbeddingRequest struct {
	Text string `json:"text"`
}

type TextEmbedding struct {
	Vector [768]float64
}

func Map(input *monstachemap.MapperPluginInput) (*monstachemap.MapperPluginOutput, error) {
	doc := input.Document
	msg, ok := doc["text"]
	if !ok {
		return &monstachemap.MapperPluginOutput{Document: doc}, nil
	}
	switch msg.(type) {
	case string:
		req := TextEmbeddingRequest{Text: msg.(string)}
		reqJson, err := json.Marshal(req)
		if err != nil {
			log.Print(err)
			return &monstachemap.MapperPluginOutput{Document: doc}, nil
		}
		resp, err := http.Post("http://feature_extractor:9294/text", "application/json", bytes.NewBuffer(reqJson))
		if err != nil {
			log.Print(err)
			return &monstachemap.MapperPluginOutput{Document: doc}, nil
		}
		if resp.StatusCode >= 400 {
			log.Print("Bad status code: ", resp.StatusCode)
			return &monstachemap.MapperPluginOutput{Document: doc}, nil
		}
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			log.Print(err)
			return &monstachemap.MapperPluginOutput{Document: doc}, nil
		}
		var data TextEmbedding
		if err := json.Unmarshal(body, &data); err != nil {
			log.Print(err)
			return &monstachemap.MapperPluginOutput{Document: doc}, nil
		}
		doc["text_vector"] = data.Vector
	}
	return &monstachemap.MapperPluginOutput{Document: doc}, nil
}