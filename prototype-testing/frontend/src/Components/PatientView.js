import { useState, useEffect } from "react";

function getRandomPosition() {
  // Generate random coordinates between 0.05 and 0.95 to keep flowers well inside container bounds
  return {
    x: Math.random() * 0.9 + 0.05,
    y: Math.random() * 0.9 + 0.05,
  };
}

export default function PatientView({ mediaList }) {
  const [mediaWithPositions, setMediaWithPositions] = useState([]);
  const [selectedMedia, setSelectedMedia] = useState(null);

  useEffect(() => {
    // Assign a random position to each media item whenever mediaList changes
    const positioned = mediaList.map((media) => ({
      ...media,
      ...getRandomPosition(),
    }));
    setMediaWithPositions(positioned);
  }, [mediaList]);

  return (
    <div
      style={{
        position: "relative",
        width: "100%",
        height: 400,
        border: "1px solid #ccc",
      }}
    >
      <h2>Patient View - Tap a flower to view memory</h2>
      {mediaWithPositions.length === 0 && <p>No memories uploaded yet.</p>}

      {mediaWithPositions.map(({ id, filename, url, x, y }) => (
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
