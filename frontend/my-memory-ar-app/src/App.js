import { useState, useEffect } from "react";
import Login from "./Components/Login";
import CaretakerView from "./Components/CaretakerView";

function PatientView({ mediaList }) {
  const [selectedMedia, setSelectedMedia] = useState(null);

  return (
    <div style={{ position: "relative", width: "100%", height: 400, border: "1px solid #ccc" }}>
      <h2>Patient View - Click flowers to watch memories</h2>
      {mediaList.length === 0 && <p>No memories uploaded yet.</p>}
      {mediaList.map(({ id, filename, url, x, y }) => (
        <div
          key={id}
          title={filename}
          style={{
            position: "absolute",
            top: `${y * 100}%`,
            left: `${x * 100}%`,
            width: 30,
            height: 30,
            backgroundColor: "pink",
            borderRadius: "50%",
            transform: "translate(-50%, -50%)",
            cursor: "pointer",
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
            fontSize: "20px",
          }}
          onClick={() => setSelectedMedia(url)}
        >
          🌸
        </div>
      ))}

      {selectedMedia && (
        <div
          onClick={() => setSelectedMedia(null)}
          style={{
            position: "fixed",
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: "rgba(0,0,0,0.7)",
            display: "flex",
            justifyContent: "center",
            alignItems: "center",
            zIndex: 1000,
          }}
        >
          {selectedMedia.match(/\.(mp4|webm|ogg)$/) ? (
            <video src={selectedMedia} controls style={{ maxHeight: "80%", maxWidth: "80%" }} />
          ) : (
            <img src={selectedMedia} alt="Memory" style={{ maxHeight: "80%", maxWidth: "80%" }} />
          )}
        </div>
      )}
    </div>
  );
}

export default function App() {
  const [user, setUser] = useState(null);
  const [mode, setMode] = useState("caretaker");
  const [mediaList, setMediaList] = useState([]);

  useEffect(() => {
    if (user) {
      fetch("http://localhost:8000/media_list")
        .then((res) => res.json())
        .then(setMediaList)
        .catch((e) => console.error("Failed to fetch media list:", e));
    }
  }, [user]);

  const handleUploadSuccess = (newMedia) => {
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
