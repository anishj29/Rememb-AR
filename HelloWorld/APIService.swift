import Foundation
import UIKit

struct MediaItem: Codable, Identifiable {
    let id: String
    let filename: String
    let url: String
    let caption: String
    let uploaded_at: String
}

class APIService {
    static let shared = APIService()
    private init() {}

    // TODO: Replace with your actual backend URL
    let baseURL = "http://10.28.223.103:8000" // or ngrok/Render URL
    
    

    func login(username: String, password: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/login") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["username": username, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data,
               let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               result["message"] as? String == "Login successful" {
                completion(true, result["user"] as? String)
            } else {
                completion(false, nil)
            }
        }.resume()
    }
    
    func uploadMedia(data: Data, type: String, caption: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/upload_media") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Construct multipart/form-data request
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n")
        body.append(caption.data(using: .utf8)!)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"media.\(type == "video" ? "mp4" : "jpg")\"\r\n")
        body.append("Content-Type: \(type == "video" ? "video/mp4" : "image/jpeg")\r\n\r\n")
        body.append(data)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(true)
            } else {
                print("Upload error:", error?.localizedDescription ?? "Unknown error")
                completion(false)
            }
        }.resume()
    }

    func fetchRandomMemories(completion: @escaping ([MediaItem]) -> Void) {
        print("🌐 Attempting to contact backend at \(baseURL)/random_memories")
        guard let url = URL(string: "\(baseURL)/random_memories") else { return }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    print("❌ Network error:", error.localizedDescription)
                }
                completion([])
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Response code:", httpResponse.statusCode)
            }

            guard let data = data else {
                print("⚠️ No data returned.")
                completion([])
                return
            }

            do {
                let items = try JSONDecoder().decode([MediaItem].self, from: data)
                DispatchQueue.main.async { completion(items) }
            } catch {
                print("💥 Decode error:", error)
                if let str = String(data: data, encoding: .utf8) {
                    print("Response body:", str)
                }
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }

    func uploadMedia(image: UIImage, caption: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/upload_media") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let data = createMultipartData(image: image, caption: caption, boundary: boundary)
        URLSession.shared.uploadTask(with: request, from: data) { data, response, error in
            completion(error == nil)
        }.resume()
    }

    private func createMultipartData(image: UIImage, caption: String, boundary: String) -> Data {
        var body = Data()
        let filename = "upload.jpg"
        let fieldName = "file"
        let mimeType = "image/jpeg"
        let imageData = image.jpegData(compressionQuality: 0.8)!

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(imageData)
        body.append("\r\n")
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n")
        body.append(caption.data(using: .utf8)!)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        return body
    }
    
}

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
