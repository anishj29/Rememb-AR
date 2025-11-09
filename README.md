# Rememb-AR 🌸

**An Augmented Reality Memory Enhancement System for Dementia Patients**

Rememb-AR leverages the Memory Palace (Method of Loci) technique through immersive AR experiences to help dementia patients strengthen memory recall and slow cognitive decline.

## 🌍 The Challenge

- **Over 55 million people** worldwide live with dementia
- Projected to **more than double by 2050**
- Dementia causes loss of important personal memories and cognitive function

## 💡 The Solution

Rememb-AR applies the scientifically-proven **Memory Palace technique** through immersive AR experiences. Research shows that brain and memory exercises, including visualization and associating memories with familiar locations, can slow progression and improve recollection.

> **Reference:** [Routes to remembering: the brains behind superior memory](https://pubmed.ncbi.nlm.nih.gov/12483214/)

## ✨ Key Features

### 🏛️ AR Memory Palace
- **Immersive AR Experience**: ARKit places memory "flowers" throughout physical spaces
- **Spatial Memory Association**: Memories are visually represented as interactive 3D flowers that users can tap to recall
- **Room-Based Placement**: Flowers are strategically placed in rooms, avoiding duplicates and creating spatial associations

### 🧠 Intelligent Memory Management
- **Gemini Vision Analysis**: Automatically analyzes uploaded images to generate detailed memory descriptions
- **Combined Context**: Merges user-provided captions with AI-generated visual analysis for richer memory context
- **Adaptive Weighting System**: Dynamically adjusts memory weights based on:
  - Survey responses (incorrect answers increase weights)
  - Manual text queries (semantic similarity detection)
  - Gemini's semantic analysis of forgotten topics or people

### 📊 Memory Recall Surveys
- **AI-Generated Surveys**: Gemini creates personalized memory recall surveys based on uploaded memories
- **Adaptive Learning**: Incorrectly answered survey questions automatically increase weights for related memories
- **Multiple Choice Questions**: Focuses on general knowledge about the patient's life, possessions, relationships, and experiences

### 🎯 Weighted Random Selection
- **A-ES Algorithm**: Uses weighted random sampling (Efraimidis-Spirakis algorithm) to select memories
- **Prevents Duplicates**: Ensures diverse memory recall by avoiding recently shown items
- **Proportional Weighting**: Higher-weighted memories (forgotten topics) appear more frequently

## 🛠️ Tech Stack

### Backend
- **Python** with **FastAPI** for RESTful API
- **Firebase** (Firestore + Storage) for data persistence
- **Google Gemini 2.5 Flash** for:
  - Image analysis and description generation
  - Semantic similarity matching
  - Survey question generation
- **PIL (Pillow)** for image processing

### Frontend
- **Swift** with **SwiftUI** for iOS interface
- **ARKit** + **RealityKit** for AR experiences
- **PhotosUI** for media selection
- **Image Caching** for optimized performance

## 📁 Project Structure

```
Rememb-AR/
├── backend/
│   └── backend/
│       ├── main.py              # FastAPI server with all endpoints
│       └── requirements.txt     # Python dependencies
├── swift-frontend/
│   └── HelloWorld/
│       ├── ContentView.swift    # Main AR view and UI
│       ├── APIService.swift     # Backend API integration
│       ├── SurveyQuestion.swift # Survey data models
│       └── ImageCache.swift    # Image caching system
└── README.md
```

## 🚀 Getting Started

### Prerequisites
- Python 3.10+
- iOS 14+ with ARKit support
- Firebase project with Firestore and Storage enabled
- Google Gemini API key

### Backend Setup

1. Navigate to the backend directory:
```bash
cd backend/backend
```

2. Create a virtual environment:
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

3. Install dependencies:
```bash
pip install -r requirements.txt
```

4. Set up environment variables:
```bash
# Create a .env file with:
FIREBASE_KEY=path/to/firebase-adminsdk.json
GEMINI_KEY=your_gemini_api_key
```

5. Run the server:
```bash
uvicorn main:app --reload
```

### Frontend Setup

1. Open `swift-frontend/HelloWorld.xcodeproj` in Xcode
2. Configure your Firebase and API endpoints in `APIService.swift`
3. Build and run on an iOS device with ARKit support (iPhone/iPad)

## 📡 API Endpoints

### Authentication
- `POST /login` - User authentication

### Media Management
- `POST /upload_media` - Upload images/videos with captions
- `GET /media_list` - Retrieve all uploaded memories
- `GET /random_memories?k={count}` - Get weighted random memories

### Memory Enhancement
- `POST /update_weights_by_similarity` - Update memory weights based on semantic similarity
- `PUT /reset_weights` - Reset all memory weights to default

### Surveys
- `GET /generate_survey?limit={n}&min_memories={m}` - Generate AI-powered memory recall survey

## 🎮 How It Works

1. **Memory Upload**: Caretakers upload photos with captions describing the memory
2. **AI Analysis**: Gemini Vision analyzes images and combines with user context
3. **Weight Assignment**: Memories start with equal weights (1.0)
4. **AR Visualization**: ARKit places memory flowers in the user's physical space
5. **Interaction**: Users tap flowers to view memories, strengthening spatial associations
6. **Adaptive Learning**: 
   - Survey responses identify forgotten topics
   - Semantic queries detect memory gaps
   - Weights increase for forgotten memories
7. **Weighted Selection**: Higher-weighted memories appear more frequently in AR

## 🔬 Algorithm Details

### Weighted Random Selection (A-ES)
The system uses the **Efraimidis-Spirakis algorithm** for weighted random sampling:

- For each memory with weight `w_i`, calculate: `key = random()^(1/w_i)`
- Select memories with the highest keys
- After selection, weights are reduced to prevent immediate re-selection
- Ensures proportional representation while maintaining diversity

### Semantic Similarity Matching
- Uses Gemini to compare user queries against combined memory descriptions
- Prioritizes user-provided context over visual analysis
- Updates weights: `new_weight = old_weight + similarity_score`

## 🎯 Use Cases

- **Dementia Care**: Help patients recall important personal memories
- **Memory Therapy**: Structured memory exercises through AR interaction
- **Family Engagement**: Caretakers can track memory recall progress
- **Cognitive Training**: Regular AR sessions to maintain cognitive function

## 📝 License

This project was developed for HealthHacks 2025.

## 🤝 Contributing

This is a research project focused on dementia care. Contributions that improve memory recall effectiveness, accessibility, or user experience are welcome.

## 📚 References

- [Routes to remembering: the brains behind superior memory](https://pubmed.ncbi.nlm.nih.gov/12483214/)
- [Method of Loci (Memory Palace)](https://en.wikipedia.org/wiki/Method_of_loci)
- [Efraimidis-Spirakis Weighted Random Sampling](https://en.wikipedia.org/wiki/Reservoir_sampling#Weighted_random_sampling)

---

**Built with ❤️ for dementia patients and their families**
