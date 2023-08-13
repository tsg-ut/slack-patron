from typing import List

import uvicorn
from sentence_transformers import SentenceTransformer
from fastapi import FastAPI
from pydantic import BaseModel

class TextEmbeddingRequest(BaseModel):
    text: str

class TextEmbeddingResponse(BaseModel):
    vector: List[float]


app = FastAPI()

@app.on_event("startup")
async def startup():
    app.text_model= SentenceTransformer('stsb-xlm-r-multilingual')

@app.post("/text", response_model=TextEmbeddingResponse)
def predict_text(request: TextEmbeddingRequest):
    emb = app.text_model.encode(request.text, convert_to_numpy=True)
    return {"vector": emb.tolist()}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=9294)