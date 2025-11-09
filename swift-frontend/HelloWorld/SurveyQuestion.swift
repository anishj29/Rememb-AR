import Foundation

struct SurveyQuestion: Codable, Identifiable {
    let id = UUID()  // For SwiftUI's ForEach
    let question: String
    let type: String
    let options: [String]?
    let correct_answer: String
    let related_memory_ids: [String]
    let difficulty: String
    let category: String
}

struct Survey: Codable {
    let survey: [SurveyQuestion]
    let total_questions: Int
    let memories_used: Int
    let total_memories_available: Int
    let memories_without_descriptions: Int
}
