import { useState, useRef } from "react";

export default function CaretakerView({ onUpload, mediaList }) {
  const [marker, setMarker] = useState(null);
  const [file, setFile] = useState(null);
  const [uploading, setUploading] = useState(false);
  const containerRef = useRef(null);
  const threshold = 0.05; // Distance threshold for duplicates (5% of container)

  const handleContainerClick = (e) => {
    const rect = containerRef.current.getBoundingClientRect();
    const x = (e.clientX - rect.left) / rect.width;
    const y = (e.clientY - rect.top) / rect.height;

    // Check for existing flower close to this point
    const duplicate = mediaList.some(
      (item) => Math.hypot(item.x - x, item.y - y) < threshold
    );
    if (duplicate) {
      alert("There is already a flower close to this position. Please choose another spot.");
      return;
    }
    setMarker({ x, y });
    setFile(null);
  };

  const handleFileChange = (e) => {
    if (e.target.files.length > 0) setFile(e.target.files[0]);
  };

  const handleUpload = async () => {
    if (!file || !marker) return alert("Place marker and select a file first.");
    setUploading(true);

    const formData = new FormData();
    formData.append("file", file);
    formData.append("x", marker.x);
    formData.append("y", marker.y);

    try {
      const res = await fetch("http://localhost:8000/upload_media", {
        method: "POST",
        body: formData,
      });
      if (!res.ok) throw new Error("Upload failed");
      const data = await res.json();
      onUpload(data);
      setMarker(null);
      setFile(null);
      alert("Upload successful!");
    } catch (err) {
      alert("Upload error: " + err.message);
    }
    setUploading(false);
  };

  return (
    <div>
      <h2>Caretaker View - Place Marker and Upload Media</h2>
      <div
        ref={containerRef}
        onClick={handleContainerClick}
        style={{
          width: "100%",
          height: 400,
          border: "2px solid black",
          position: "relative",
          marginBottom: 20,
          userSelect: "none",
          cursor: "crosshair",
        }}
      >
        {/* Render existing flower markers */}
        {mediaList.map((item) => (
          <div
            key={item.id}
            style={{
              position: "absolute",
              top: `${item.y * 100}%`,
              left: `${item.x * 100}%`,
              width: 24,
              height: 24,
              backgroundColor: "purple",
              borderRadius: "50%",
              transform: "translate(-50%, -50%)",
              pointerEvents: "none",
              opacity: 0.7,
            }}
            title={item.filename}
          />
        ))}

        {/* New marker */}
        {marker && (
          <div
            style={{
              position: "absolute",
              top: `${marker.y * 100}%`,
              left: `${marker.x * 100}%`,
              width: 24,
              height: 24,
              backgroundColor: "red",
              borderRadius: "50%",
              transform: "translate(-50%, -50%)",
              pointerEvents: "none",
              opacity: 1,
            }}
          />
        )}
      </div>

      {marker && (
        <div>
          <input type="file" accept="image/*,video/*" onChange={handleFileChange} />
          <button onClick={handleUpload} disabled={uploading || !file}>
            {uploading ? "Uploading…" : "Upload Media"}
          </button>
        </div>
      )}
      {!marker && <p>Click inside the box above to place a flower marker.</p>}
    </div>
  );
}
