from fastapi import FastAPI, File, UploadFile, HTTPException, Form, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import firebase_admin
from firebase_admin import credentials, firestore, storage
import traceback
from fastapi.responses import JSONResponse
from random import random
from typing import List
import os
import re
import requests
import google.generativeai as genai
from dotenv import load_dotenv
from PIL import Image
import io

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
        
        # Comment fixed: This is a 24-hour signed URL
        media_url = blob.generate_signed_url(version="v4", expiration=86400)  # 24 hour signed URL
        
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

# --- MODIFIED ENDPOINT ---

@app.get("/random_memories")
def random_memories(k: int = Query(default=1, ge=1, description="Number of random memories to return")):
    """
    Get 'k' random memories using A-ES weighted random sampling without replacement.
    
    This algorithm ensures that:
    1. Items with higher weights are proportionally more likely to be selected.
    2. 'k' distinct items are returned (sampling without replacement).
    3. It is stateless (no 'shown_memory_ids') and robust for a server.
       
    Algorithm (A-ES by Efraimidis and Spirakis):
    - For each item 'i' with weight 'w_i', calculate a key = random()^(1/w_i).
    - Select the 'k' items with the largest keys.
    """
    try:
        media_ref = db.collection("media")
        docs = media_ref.stream()
        
        weighted_items = []
        
        for doc in docs:
            mem = doc.to_dict()
            if not mem:
                continue

            # Ensure weight is positive (minimum 0.1)
            weight = max(mem.get("weight", 1.0), 0.1)  
            rand_val = random()  # Generates a float in [0.0, 1.0)
            
            # Handle the edge case of rand_val = 0.0 to avoid math domain error
            if rand_val == 0.0:
                 key = float('inf') # Assign a very large key
            else:
                 # This is the core of the algorithm
                 key = rand_val ** (1.0 / weight)
            
            item_data = {
                "id": doc.id,
                "filename": mem.get("filename"),
                "url": mem.get("url"),
                "caption": mem.get("caption", ""),
                "weight": mem.get("weight", 1.0),
                "uploaded_at": mem.get("uploaded_at"),
            }
            weighted_items.append((key, item_data))

        if not weighted_items:
            return []
            
        # Sort by the calculated key in descending order
        weighted_items.sort(key=lambda x: x[0], reverse=True)
        
        # Get the number of items to return, capped by the total available
        num_to_return = min(k, len(weighted_items))
        
        # Extract the 'item_data' from the top 'k' tuples
        selected_memories = [item for key, item in weighted_items[:num_to_return]]
        
        return selected_memories

    except Exception as e:
        print("Random memories error:", e)
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Failed to retrieve random memories")

# --- END OF MODIFIED ENDPOINT ---

class SimilarityRequest(BaseModel):
    query: str

async def get_llm_image_analysis(image_url: str, filename: str = None) -> str:
    """
    Get quick LLM analysis of an image using Gemini Vision API.
    Optimized for speed and generalization.
    If image_url is expired, tries to generate a new signed URL from Firebase Storage.
    """
    try:
        print(f"Analyzing image from URL: {image_url}")
        
        if not image_url or not image_url.strip():
            print("Empty image URL provided")
            return ""
        
        # Download the image
        print("Downloading image...")
        try:
            response = requests.get(image_url, timeout=30)
            response.raise_for_status()
            print(f"Image downloaded successfully, size: {len(response.content)} bytes")
        except requests.exceptions.HTTPError as e:
            # If URL is expired (403/404), try to generate a new signed URL
            if e.response.status_code in [403, 404] and filename:
                print(f"URL expired (status {e.response.status_code}), generating new signed URL for {filename}")
                try:
                    blob = bucket.blob(filename)
                    new_url = blob.generate_signed_url(version="v4", expiration=3600)
                    print(f"Generated new signed URL, retrying download...")
                    response = requests.get(new_url, timeout=30)
                    response.raise_for_status()
                    print(f"Image downloaded successfully with new URL, size: {len(response.content)} bytes")
                except Exception as retry_error:
                    print(f"Failed to generate new URL or download: {retry_error}")
                    raise e
            else:
                raise e
        
        # Open image with PIL
        image = Image.open(io.BytesIO(response.content))
        print(f"Image opened: {image.format}, size: {image.size}")
        
        # Use Gemini Vision model to analyze the image (simplified for speed)
        vision_model = genai.GenerativeModel('gemini-2.5-flash')
        
        # Simplified prompt for faster, less intensive analysis
        vision_prompt = """Briefly describe what you see in this image. Focus on:
        - Main subjects (people, objects)
        - Key relationships or connections visible
        - Notable details that stand out
        
        Keep it concise (2-3 sentences maximum)."""
        
        print("Calling Gemini Vision API...")
        vision_response = vision_model.generate_content([vision_prompt, image])
        description = vision_response.text.strip()
        print(f"Gemini Vision response: '{description}'")
        
        if not description:
            print("Warning: Gemini Vision returned empty description")
        
        return description
        
    except Exception as e:
        print(f"ERROR analyzing image: {e}")
        print(f"Error type: {type(e).__name__}")
        print(f"Full traceback:")
        traceback.print_exc()
        return ""  # Return empty string if image analysis fails

async def combine_descriptions_with_llm(user_context: str, visual_analysis: str) -> str:
    """
    Use LLM to intelligently combine user context and visual analysis.
    Prioritizes user context while incorporating relevant visual details.
    """
    try:
        model = genai.GenerativeModel('gemini-2.5-flash')
        
        prompt = f"""Combine these two descriptions into a single, coherent description for memory recall purposes.

User Context (PRIMARY - prioritize this):
{user_context}

Visual Analysis (SECONDARY - use to supplement and clarify):
{visual_analysis}

Instructions:
- The user context is the PRIMARY source of information and should be the foundation
- Use the visual analysis to add relevant details, clarify ambiguities, or provide context
- If the visual analysis contradicts the user context, prioritize the user context
- Create a natural, flowing description that feels like a single cohesive narrative
- Keep it concise but informative (2-4 sentences)
- Focus on information that would help with memory recall

Respond with ONLY the combined description, nothing else."""

        response = model.generate_content(prompt)
        combined = response.text.strip()
        
        if not combined:
            # Fallback to simple combination if LLM fails
            return f"{user_context}. Visual context: {visual_analysis}"
        
        return combined
        
    except Exception as e:
        print(f"Error combining descriptions with LLM: {e}")
        traceback.print_exc()
        # Fallback to simple combination if LLM fails
        return f"{user_context}. Visual context: {visual_analysis}"

async def get_combined_description(caption: str, image_url: str, doc_id: str, doc_ref, filename: str = None) -> str:
    """
    Get or create a combined description that merges user context (caption) with LLM image analysis.
    Prioritizes user context. Caches the combined description in Firestore.
    """
    try:
        # Check if we already have a cached combined description
        doc_data = doc_ref.get().to_dict()
        cached_combined = doc_data.get("combined_description", "")
        
        # Only use cached if it exists and is different from just the caption
        # If cached description is just the caption, regenerate it to include LLM analysis
        if cached_combined and cached_combined != caption and len(cached_combined) > len(caption) + 10:
            # Check if it's likely a combined description (longer than just caption)
            print(f"Using cached combined description for document {doc_id}")
            return cached_combined
        elif cached_combined:
            print(f"Cached description exists but may lack visual context, regenerating for document {doc_id}")
        
        print(f"Creating combined description for document {doc_id}...")
        print(f"Image URL: {image_url}")
        print(f"Caption: {caption}")
        
        # Get LLM image analysis (if image URL is available)
        llm_analysis = ""
        if image_url:
            print(f"Attempting to get LLM image analysis for document {doc_id}...")
            llm_analysis = await get_llm_image_analysis(image_url, filename)
            print(f"LLM analysis result for {doc_id}: '{llm_analysis}'")
            if not llm_analysis:
                print(f"WARNING: LLM analysis returned empty for {doc_id}. Check logs above for errors.")
        else:
            print(f"No image URL provided for document {doc_id}")
        
        # Create combined description using LLM to intelligently merge, prioritizing user context
        if llm_analysis and llm_analysis.strip():
            # Use LLM to combine the descriptions with priority on user context
            combined_description = await combine_descriptions_with_llm(caption, llm_analysis)
            print(f"Created combined description with LLM analysis for {doc_id}")
        else:
            # If no image analysis available, just use caption
            combined_description = caption
            print(f"Using caption only for {doc_id} (no LLM analysis available)")
        
        # Cache the combined description in Firestore
        doc_ref.update({"combined_description": combined_description})
        print(f"Cached combined description for document {doc_id}")
        
        return combined_description
        
    except Exception as e:
        print(f"Error creating combined description for document {doc_id}: {e}")
        traceback.print_exc()
        return caption  # Fallback to just caption if there's an error

@app.post("/update_weights_by_similarity")
async def update_weights_by_similarity(data: SimilarityRequest):
    """
    Compare the query string with all image contexts using Gemini API.
    For each image:
    1. Creates a combined description (user context + LLM image analysis, prioritizing user context)
    2. Caches the combined description in Firestore
    3. Compares the query against this combined context for semantic similarity
    4. Updates weights for all images based on their similarity scores.
    
    Combined descriptions are cached in Firestore to avoid re-analyzing the same image.
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
            image_url = data_dict.get("url", "")
            
            print(f"Processing document {doc.id}: caption='{caption}', weight={current_weight}")
            print(f"Full document data: {data_dict}")
            
            if not caption:
                print(f"Skipping document {doc.id} - no caption or context field")
                skipped_no_caption += 1
                continue
            
            # Get or create combined description (user context + LLM analysis, prioritized to user context)
            # This is done BEFORE similarity matching
            filename = data_dict.get("filename", "")
            combined_context = await get_combined_description(caption, image_url, doc.id, doc.reference, filename)
            
            # Create improved prompt for similarity comparison
            # This prompt emphasizes semantic and contextual understanding over word matching
            # Uses the combined description which already prioritizes user context
            prompt = f"""You are analyzing memory-related queries. Determine how semantically and contextually relevant an image is to a memory query.

Query: {query}

Image Context (Combined Description - User Context Prioritized):
{combined_context}

IMPORTANT: The combined description prioritizes the user-provided context. Use this full context to determine semantic similarity.

CRITICAL: Focus on SEMANTIC MEANING and CONTEXTUAL RELATIONSHIPS, NOT just word matching.
PRIORITIZE the caption/API context. Use the visual description only as supplementary information to clarify or enhance the caption when needed.

Key principles:
1. **Contextual Understanding**: Understand the full meaning and relationships in the query, not just individual words.
   - Example: Query "woman with an American husband" should match images showing marriages/relationships with Americans, NOT just any image with a woman
   - If the LLM description mentions "married to an American Actor" or similar relationships, this is highly relevant (0.9-1.0)
   - If the image only shows "Woman sitting on table" without relationship context, this is NOT relevant (0.0-0.3) even though it contains "woman"

2. **Compound Concepts**: When the query combines multiple concepts (e.g., "woman" + "American husband"), prioritize images where BOTH concepts appear in the caption (primary) or are clearly visible in the image (secondary).
   - Higher score if the caption contains the full relationship/context
   - If caption is partial, visual details can supplement, but caption takes priority
   - Lower score if only one part of the concept is mentioned in the caption

3. **Semantic Relationships**: Understand synonyms, related terms, and contextual connections:
   - "husband" relates to "married", "spouse", "partner", "actor" (if mentioned as spouse)
   - "American" relates to "US", "United States", nationality contexts
   - Don't just match keywords - understand the semantic meaning

4. **Relevance Levels** (Caption is PRIMARY, Visual is SECONDARY):
   - 0.9-1.0: The caption contains the EXACT semantic relationship/context from the query (e.g., query about "woman with American husband" matches caption "actress married to American Actor")
   - 0.7-0.89: The caption contains most of the key concepts and relationships, with strong semantic similarity
   - 0.4-0.69: The caption shares some concepts but missing key relationships or context (visual details may help but don't override caption)
   - 0.0-0.39: Only superficial keyword matches in caption without the meaningful context/relationships

5. **Avoid Word Matching Bias**: A caption that matches keywords but lacks the semantic relationship should score LOW, even if it contains matching words.

Rate the relevance on a scale of 0 to 1 based on SEMANTIC and CONTEXTUAL similarity, not word overlap.

Respond in the following format:
Score: [number between 0 and 1]
Reasoning: [brief explanation focusing on semantic/contextual relationships, not just word matching]"""
            
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
                    "combined_description": combined_context,
                    "similarity_score": similarity_score,
                    "reasoning": reasoning
                })
                
                results.append({
                    "id": doc.id,
                    "caption": caption,
                    "combined_description": combined_context,
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

@app.put("/reset_weights")
def reset_weights():
    """
    Reset all weight fields to 1.0 for all documents in the media collection.
    """
    try:
        media_ref = db.collection("media")
        docs = list(media_ref.stream())
        
        if len(docs) == 0:
            return {
                "message": "No documents found in the media collection",
                "updated_count": 0
            }
        
        updated_count = 0
        for doc in docs:
            doc.reference.update({"weight": 1.0})
            updated_count += 1
        
        return {
            "message": f"Successfully reset weights to 1.0 for {updated_count} documents",
            "updated_count": updated_count
        }
        
    except Exception as e:
        print("Reset weights error:", e)
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Failed to reset weights: {str(e)}")