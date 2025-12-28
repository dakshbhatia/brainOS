import os
import sys
import torch
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional
import io
import wave

# Assuming chatterbox-tts is installed
try:
    from chatterbox import Chatterbox
except ImportError:
    print("Error: chatterbox-tts not found. Please install it.")
    sys.exit(1)

app = FastAPI(title="BrainOS Voice Sidecar")

# Global model instance
model = None

class TTSRequest(BaseModel):
    text: str
    voice_id: Optional[str] = "default"
    speed: Optional[float] = 1.0

def load_model():
    global model
    if model is None:
        print("Loading Chatterbox model...")
        # Use GPU if available (Apple Silicon)
        device = "mps" if torch.backends.mps.is_available() else "cpu"
        model = Chatterbox.from_pretrained("resemble-ai/chatterbox-turbo-v1").to(device)
        print(f"Model loaded on {device}")

@app.on_event("startup")
async def startup_event():
    load_model()

@app.post("/v1/audio/speech")
async def text_to_speech(request: TTSRequest):
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    
    print(f"Generating speech for: {request.text[:50]}...")
    
    try:
        # In a real implementation, we'd handle voice_id by loading a reference clip
        # For now, we use the default zero-shot capability
        audio_data = model.generate(
            text=request.text,
            speed=request.speed
        )
        
        # Convert to WAV for streaming
        byte_io = io.BytesIO()
        with wave.open(byte_io, 'wb') as wav_file:
            wav_file.setnchannels(1)
            wav_file.setsampwidth(2)
            wav_file.setframerate(24000)
            wav_file.writeframes(audio_data)
        
        byte_io.seek(0)
        return StreamingResponse(byte_io, media_type="audio/wav")
        
    except Exception as e:
        print(f"Error generating speech: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health():
    return {"status": "ok", "model_loaded": model is not None}

if __name__ == "__main__":
    port = int(os.getenv("VOICE_PORT", 8001))
    uvicorn.run(app, host="127.0.0.1", port=port)
