from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import firebase_admin
from firebase_admin import credentials, firestore, storage
import traceback
from fastapi.responses import JSONResponse

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   
    allow_methods=["*"],
    allow_headers=["*"],
)

cred = credentials.Certificate("healthhacks2025-71347-firebase-adminsdk-fbsvc-f2fcdb36d1.json")
firebase_admin.initialize_app(cred, {
    "storageBucket": "healthhacks2025-71347.firebasestorage.app"
})

db = firestore.client()
bucket = storage.bucket()

class LoginRequest(BaseModel):
    username: str
    password: str

@app.post("/login")
def login(data: LoginRequest):
    if data.username == "caretaker" and data.password == "password":
        return {"message": "Login successful", "user": data.username}
    else:
        raise HTTPException(status_code=401, detail="Invalid username or password")

@app.post("/upload_media")
async def upload_media(
    file: UploadFile = File(...),
    x: float = Form(...),
    y: float = Form(...)
):
    try:
        contents = await file.read()

        import uuid
        unique_filename = f"{uuid.uuid4()}_{file.filename}"

        blob = bucket.blob(unique_filename)
        blob.upload_from_string(contents, content_type=file.content_type)

        media_url = blob.generate_signed_url(version="v4", expiration=3600)

        from datetime import datetime
        media_data = {
            "filename": unique_filename,
            "url": media_url,   # Use the signed URL here
            "x": x,
            "y": y,
            "uploaded_at": datetime.utcnow().isoformat() + "Z",
        }
        db.collection("media").add(media_data)
        return media_data

    except Exception as e:
        print("Upload error:", e)
        traceback.print_exc()
        return JSONResponse(status_code=500, content={"detail": "Upload failed due to server error"})

@app.get("/media_list")
def media_list():
    media_ref = db.collection("media")
    docs = media_ref.stream()
    media_items = []
    for doc in docs:
        data = doc.to_dict()
        media_items.append({
            "id": doc.id,
            "filename": data.get("filename"),
            "url": data.get("url"),
            "x": data.get("x"),
            "y": data.get("y"),
            "uploaded_at": data.get("uploaded_at"),
        })
    return media_items
