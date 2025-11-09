import { useState } from "react";

export default function CaretakerView({ mediaList, onUpload }) {
  const [file, setFile] = useState(null);
  const [caption, setCaption] = useState("");
  const [uploading, setUploading] = useState(false);
  const [selectedMediaId, setSelectedMediaId] = useState(null);

  const handleFileChange = (e) => {
    if (e.target.files.length > 0) setFile(e.target.files[0]);
  };

  const handleUpload = async () => {
    if (!file) return alert("Please select a file before uploading.");
    if (!caption.trim()) return alert("Please enter a caption.");
    setUploading(true);

    const formData = new FormData();
    formData.append("file", file);
    formData.append("caption", caption);

    try {
      const res = await fetch("http://localhost:8000/upload_media", {
        method: "POST",
        body: formData,
      });
      if (!res.ok) throw new Error("Upload failed");
      const data = await res.json();
      onUpload(data); // Notify parent of new media
      setFile(null);
      setCaption("");
      alert("Upload successful!");
    } catch (err) {
      alert("Upload error: " + err.message);
    }
    setUploading(false);
  };

  return (
    <div>
      <h2>Caretaker Upload & Memories</h2>
      <div style={{ marginBottom: 16 }}>
        <input
          type="text"
          placeholder="Enter caption"
          value={caption}
          onChange={(e) => setCaption(e.target.value)}
          style={{ marginBottom: 8, width: "100%", padding: 8 }}
        />
        <input type="file" accept="image/*,video/*" onChange={handleFileChange} />
        <button onClick={handleUpload} disabled={uploading || !file}>
          {uploading ? "Uploading…" : "Upload"}
        </button>
      </div>

      <h3>Uploaded Memories</h3>
      <div style={{ display: "flex", overflowX: "auto", paddingBottom: 10 }}>
        {mediaList.length === 0 && <p>No memories uploaded yet.</p>}
        {mediaList.map((media) => (
          <div
            key={media.id}
            style={{
              marginRight: 10,
              cursor: "pointer",
              border: media.id === selectedMediaId ? "3px solid #007bff" : "2px solid #ccc",
              borderRadius: 6,
              boxShadow: media.id === selectedMediaId ? "0 0 8px #007bff" : "none",
              padding: 4,
              maxWidth: 110,
              userSelect: "none",
            }}
            onClick={() => setSelectedMediaId(media.id)}
            title={media.caption || media.filename}
          >
            <img
              src={media.url}
              alt={media.filename}
              style={{ width: 100, height: 100, objectFit: "cover", borderRadius: 4 }}
            />
            <div
              style={{
                whiteSpace: "normal",
                wordWrap: "break-word",
                fontSize: 12,
                marginTop: 4,
                height: 36,
                overflow: "hidden",
                textOverflow: "ellipsis",
              }}
            >
              {media.caption || "No caption"}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
