import os
import sys
import torch
import uvicorn
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional
import io
import wave
import tempfile

# Assuming chatterbox-tts is installed
try:
    from chatterbox import Chatterbox
except ImportError:
    print("Warning: chatterbox-tts not found. Will use native 'say' fallback.")
    Chatterbox = None
import subprocess

# Whisper for STT
try:
    import whisper
except ImportError:
    print("Warning: whisper not found. STT will be unavailable.")
    whisper = None

app = FastAPI(title="BrainOS Voice Sidecar")

# Global model instances
tts_model = None
stt_model = None

class TTSRequest(BaseModel):
    text: str
    voice_id: Optional[str] = "default"
    speed: Optional[float] = 1.0

class STTResponse(BaseModel):
    text: str
    language: Optional[str] = None
    confidence: Optional[float] = None

def load_tts_model():
    global tts_model
    if tts_model is None and Chatterbox is not None:
        print("Loading Chatterbox TTS model...")
        device = "mps" if torch.backends.mps.is_available() else "cpu"
        tts_model = Chatterbox.from_pretrained("resemble-ai/chatterbox-turbo-v1").to(device)
        print(f"TTS model loaded on {device}")

def load_stt_model():
    global stt_model
    if stt_model is None and whisper is not None:
        print("Loading Whisper STT model (base)...")
        # Use base model for balance of speed and accuracy
        stt_model = whisper.load_model("base")
        print("STT model loaded")

@app.on_event("startup")
async def startup_event():
    load_tts_model()
    load_stt_model()

@app.post("/v1/audio/speech")
async def text_to_speech(request: TTSRequest):
    if tts_model is None:
        print(f"TTS Model not loaded, using native 'say' for: {request.text[:50]}...")
        return await native_say_tts(request.text)
    
    print(f"Generating speech with Chatterbox for: {request.text[:50]}...")
    
    try:
        audio_data = tts_model.generate(
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
        print(f"Error generating speech with model: {e}. Falling back to 'say'.")
        return await native_say_tts(request.text)

async def native_say_tts(text: str):
    """Fallback to macOS native 'say' command, piping to a WAV file."""
    try:
        # Create temp file for the AIFF output from 'say'
        with tempfile.NamedTemporaryFile(suffix=".aiff", delete=False) as tmp_aiff:
            tmp_aiff_path = tmp_aiff.name
        
        # Run 'say' to generate AIFF
        subprocess.run(["say", "-o", tmp_aiff_path, text], check=True)
        
        # Convert AIFF to WAV using soundfile or subprocess/ffmpeg if needed
        # For simplicity in this environment, we'll try to use a conversion or just return AIFF
        # But standard response should be WAV. Let's use soundfile if available.
        try:
            import soundfile as sf
            data, samplerate = sf.read(tmp_aiff_path)
            byte_io = io.BytesIO()
            sf.write(byte_io, data, samplerate, format='WAV')
            byte_io.seek(0)
            os.unlink(tmp_aiff_path)
            return StreamingResponse(byte_io, media_type="audio/wav")
        except ImportError:
            # If soundfile not available, just stream AIFF (most players handle it)
            with open(tmp_aiff_path, "rb") as f:
                content = f.read()
            os.unlink(tmp_aiff_path)
            return Response(content=content, media_type="audio/x-aiff")
            
    except Exception as e:
        print(f"Native 'say' failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/v1/audio/transcriptions", response_model=STTResponse)
async def speech_to_text(file: UploadFile = File(...), language: Optional[str] = None):
    """
    Transcribe audio to text using Whisper.
    Accepts WAV, MP3, M4A, WEBM, MP4, MPGA, MPEG audio files.
    """
    if stt_model is None:
        raise HTTPException(status_code=503, detail="STT model not loaded. Install whisper: pip install openai-whisper")
    
    print(f"Transcribing audio: {file.filename}")
    
    try:
        # Save uploaded file to temp location
        with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(file.filename or ".wav")[1]) as tmp:
            content = await file.read()
            tmp.write(content)
            tmp_path = tmp.name
        
        # Transcribe with Whisper
        options = {}
        if language:
            options["language"] = language
        
        result = stt_model.transcribe(tmp_path, **options)
        
        # Clean up temp file
        os.unlink(tmp_path)
        
        return STTResponse(
            text=result["text"].strip(),
            language=result.get("language"),
            confidence=None  # Whisper doesn't provide overall confidence
        )
        
    except Exception as e:
        print(f"Error transcribing audio: {e}")
        # Clean up temp file on error
        if 'tmp_path' in locals():
            try:
                os.unlink(tmp_path)
            except:
                pass
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health():
    return {
        "status": "ok", 
        "tts_loaded": tts_model is not None,
        "stt_loaded": stt_model is not None
    }

@app.get("/capabilities")
async def capabilities():
    """Return available voice capabilities"""
    return {
        "tts": tts_model is not None,
        "stt": stt_model is not None,
        "voices": ["default"],  # Future: list available voice clones
        "stt_languages": ["en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr", "pl", "ca", "nl", "ar", "sv", "it", "id", "hi", "fi", "vi", "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no", "th", "ur", "hr", "bg", "lt", "la", "mi", "ml", "cy", "sk", "te", "fa", "lv", "bn", "sr", "az", "sl", "kn", "et", "mk", "br", "eu", "is", "hy", "ne", "mn", "bs", "kk", "sq", "sw", "gl", "mr", "pa", "si", "km", "sn", "yo", "so", "af", "oc", "ka", "be", "tg", "sd", "gu", "am", "yi", "lo", "uz", "fo", "ht", "ps", "tk", "nn", "mt", "sa", "lb", "my", "bo", "tl", "mg", "as", "tt", "haw", "ln", "ha", "ba", "jw", "su"]
    }

if __name__ == "__main__":
    port = int(os.getenv("VOICE_PORT", 8001))
    uvicorn.run(app, host="127.0.0.1", port=port)
