import { useState, useEffect } from "react";
import Login from "./Components/Login";
import CaretakerView from "./Components/CaretakerView";
import PatientView from "./Components/PatientView";

export default function App() {
  const [user, setUser] = useState(null);
  const [mode, setMode] = useState("caretaker");
  const [mediaList, setMediaList] = useState([]);

  useEffect(() => {
    if (user) {
      const url = mode === "patient"
        ? "http://localhost:8000/random_memories"
        : "http://localhost:8000/media_list";

      fetch(url)
        .then((res) => res.json())
        .then(setMediaList)
        .catch((e) => console.error("Failed to fetch media list:", e));
    }
  }, [user, mode]);

  const handleUploadSuccess = (newMedia) => {
    // After successful upload, add new media to list to update carousel in caretaker view
    setMediaList((prevList) => [...prevList, newMedia]);
  };

  if (!user) return <Login onLogin={setUser} />;

  return (
    <div style={{ maxWidth: 600, margin: "auto", padding: 20 }}>
      <h1>Welcome, {user}</h1>
      <button onClick={() => setMode(mode === "caretaker" ? "patient" : "caretaker")}>
        Switch to {mode === "caretaker" ? "Patient" : "Caretaker"} View
      </button>

      {mode === "caretaker" ? (
        <CaretakerView mediaList={mediaList} onUpload={handleUploadSuccess} />
      ) : (
        <PatientView mediaList={mediaList} />
      )}
    </div>
  );
}
