from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import firebase_admin
from firebase_admin import credentials, firestore, storage
import traceback
from fastapi.responses import JSONResponse
from random import sample, choices
from typing import List
import os
import re
import google.generativeai as genai
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Firebase Admin SDK
cred = credentials.Certificate("healthhacks2025-71347-firebase-adminsdk-fbsvc-f2fcdb36d1.json")
firebase_admin.initialize_app(cred, {
    "storageBucket": "healthhacks2025-71347.firebasestorage.app"
})

db = firestore.client()
bucket = storage.bucket()

# Initialize Gemini API
GEMINI_KEY = os.getenv("GEMINI_KEY")
if GEMINI_KEY:
    genai.configure(api_key=GEMINI_KEY)

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
    caption: str = Form(...)
):
    try:
        contents = await file.read()
        
        import uuid
        unique_filename = f"{uuid.uuid4()}_{file.filename}"
        
        blob = bucket.blob(unique_filename)
        blob.upload_from_string(contents, content_type=file.content_type)
        
        media_url = blob.generate_signed_url(version="v4", expiration=3600)  # 1 hour signed URL
        
        from datetime import datetime
        media_data = {
            "filename": unique_filename,
            "url": media_url,
            "caption": caption,
            "weight": 1.0,
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
            "caption": data.get("caption", ""),
            "weight": data.get("weight", 1.0),
            "uploaded_at": data.get("uploaded_at"),
        })
    return media_items

# In-memory store of shown memory IDs - resets on backend restart
shown_memory_ids = set()

@app.get("/random_memories")
def random_memories():
    media_ref = db.collection("media")
    docs = media_ref.stream()
    all_memories = [(doc.id, doc.to_dict()) for doc in docs]

    unseen = [(id, mem) for id, mem in all_memories if id not in shown_memory_ids]
    if not unseen:
        shown_memory_ids.clear()
        unseen = all_memories
    
    count = min(len(unseen), 3)
    
    # Weighted random selection: higher weights = higher probability
    # Extract weights for unseen memories
    weights = [mem.get("weight", 1.0) for _, mem in unseen]
    
    # Use weighted random selection (with replacement, then deduplicate)
    # We'll select more than needed and deduplicate to avoid repeats
    selected_with_duplicates = choices(unseen, weights=weights, k=count * 2)
    
    # Deduplicate while preserving order
    seen_ids = set()
    selected = []
    for item in selected_with_duplicates:
        id, mem = item
        if id not in seen_ids and len(selected) < count:
            selected.append(item)
            seen_ids.add(id)
    
    # If we still don't have enough after deduplication, fill with remaining items
    if len(selected) < count:
        remaining = [(id, mem) for id, mem in unseen if id not in seen_ids]
        if remaining:
            # Use weighted selection for remaining items
            remaining_weights = [mem.get("weight", 1.0) for _, mem in remaining]
            additional = choices(remaining, weights=remaining_weights, k=count - len(selected))
            # Deduplicate again
            for item in additional:
                id, mem = item
                if id not in seen_ids:
                    selected.append(item)
                    seen_ids.add(id)
                    if len(selected) >= count:
                        break

    for id, _ in selected:
        shown_memory_ids.add(id)

    return [
        {
            "id": id,
            "filename": mem.get("filename"),
            "url": mem.get("url"),
            "caption": mem.get("caption", ""),
            "weight": mem.get("weight", 1.0),
            "uploaded_at": mem.get("uploaded_at"),
        }
        for id, mem in selected
    ]

class SimilarityRequest(BaseModel):
    query: str

@app.post("/update_weights_by_similarity")
async def update_weights_by_similarity(data: SimilarityRequest):
    """
    Compare the query string with all image contexts using Gemini API.
    Update weights for all images based on their similarity scores.
    Formula: new_weight = old_weight + similarity_score
    """
    if not GEMINI_KEY:
        raise HTTPException(status_code=500, detail="GEMINI_KEY not configured")
    
    try:
        # Get all media items from Firestore
        media_ref = db.collection("media")
        docs = list(media_ref.stream())  # Convert to list to check if empty
        
        print(f"Found {len(docs)} documents in media collection")
        
        if len(docs) == 0:
            return {
                "message": "No images found in the database",
                "query": data.query,
                "updated_images": [],
                "all_scores": []
            }
        
        model = genai.GenerativeModel('gemini-2.5-flash')
        query = data.query
        
        updated_count = 0
        results = []
        all_scores = []  # Track all scores for debugging
        skipped_no_caption = 0
        
        for doc in docs:
            data_dict = doc.to_dict()
            # Check for both "caption" and "context" field names
            caption = data_dict.get("caption", "") or data_dict.get("context", "")
            print(caption)
            current_weight = data_dict.get("weight", 1.0)
            
            print(f"Processing document {doc.id}: caption='{caption}', weight={current_weight}")
            print(f"Full document data: {data_dict}")
            
            if not caption:
                print(f"Skipping document {doc.id} - no caption or context field")
                skipped_no_caption += 1
                continue
            
            # Create improved prompt for similarity comparison
            # This prompt better understands memory-related queries and semantic relationships
            prompt = f"""You are analyzing memory-related queries. Determine how relevant an image caption is to a memory query.

Query: {query}
Image Caption: {caption}

Consider that:
- If the query mentions forgetting something (e.g., "forgetting women"), images related to that topic should have HIGH similarity
- Semantic relationships matter: "women" relates to "woman", "female", etc.
- The goal is to find images that help with memory recall for the query topic

Rate the relevance on a scale of 0 to 1:
- 0.9-1.0: Directly related (e.g., query mentions "women" and caption contains "woman")
- 0.7-0.89: Strongly related (semantically similar concepts)
- 0.5-0.69: Moderately related
- 0.0-0.49: Not related

Respond in the following format:
Score: [number between 0 and 1]
Reasoning: [brief explanation of why you chose this score]"""
            
            try:
                print(f"Calling Gemini API for document {doc.id}...")
                response = model.generate_content(prompt)
                similarity_text = response.text.strip()
                print(f"Gemini response for {doc.id}: '{similarity_text}'")
                
                # Extract score and reasoning from response
                reasoning = ""
                similarity_score = 0.0
                
                # Try to extract score from "Score: X" format
                score_match = re.search(r'Score:\s*([0-9]*\.?[0-9]+)', similarity_text, re.IGNORECASE)
                if score_match:
                    similarity_score = float(score_match.group(1))
                else:
                    # Fallback: try to find the first float in the response
                    match = re.search(r'0?\.\d+|1\.0|1|0', similarity_text)
                    if match:
                        similarity_score = float(match.group())
                    else:
                        similarity_score = float(similarity_text.split()[0])
                
                # Extract reasoning from "Reasoning: X" format
                reasoning_match = re.search(r'Reasoning:\s*(.+?)(?:\n|$)', similarity_text, re.IGNORECASE | re.DOTALL)
                if reasoning_match:
                    reasoning = reasoning_match.group(1).strip()
                else:
                    # If no explicit reasoning section, use the rest of the text after the score
                    reasoning = similarity_text.split('\n', 1)[-1].strip() if '\n' in similarity_text else "No reasoning provided"
                
                # Clamp to 0-1 range
                similarity_score = max(0.0, min(1.0, similarity_score))
                
                print(f"Extracted similarity score for {doc.id}: {similarity_score}")
                print(f"Reasoning for {doc.id}: {reasoning}")
                
                # Update weight for all images based on similarity score
                # Formula: new_weight = old_weight + similarity_score
                new_weight = current_weight + similarity_score
                
                print(f"Updating document {doc.id}: weight {current_weight} -> {new_weight}")
                
                # Update in Firestore
                doc.reference.update({"weight": new_weight})
                updated_count += 1
                print(f"Successfully updated document {doc.id}")
                
                # Track all scores and updates
                all_scores.append({
                    "id": doc.id,
                    "caption": caption,
                    "similarity_score": similarity_score,
                    "reasoning": reasoning
                })
                
                results.append({
                    "id": doc.id,
                    "caption": caption,
                    "similarity_score": similarity_score,
                    "reasoning": reasoning,
                    "old_weight": current_weight,
                    "new_weight": new_weight
                })
            except Exception as e:
                print(f"Error processing document {doc.id}: {e}")
                print(f"Response text: {similarity_text if 'similarity_text' in locals() else 'N/A'}")
                traceback.print_exc()
                continue
        
        return {
            "message": f"Updated {updated_count} image weights",
            "query": query,
            "total_documents": len(docs),
            "skipped_no_caption": skipped_no_caption,
            "updated_images": results,
            "all_scores": all_scores  # Include all scores for debugging
        }
        
    except Exception as e:
        print("Similarity update error:", e)
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to update weights: {str(e)}")
