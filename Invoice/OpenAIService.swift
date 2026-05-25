import Foundation
import UIKit
import FirebaseFunctions

enum OpenAIError: Error {
    case invalidURL
    case invalidResponse
    case noData
    case decodingError
    case apiError(String)
}

extension OpenAIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL for the analysis service."
        case .invalidResponse:
            return "The analysis service returned an unexpected response. Try again."
        case .noData:
            return "No data came back from the analysis service. Try again."
        case .decodingError:
            return "Could not read the analysis response. Try again."
        case .apiError(let message):
            return message
        }
    }
}

class OpenAIService {
    static let shared = OpenAIService()
    private static let firebaseCallableName = "openaiChatCompletion"

    private init() {}

    private func invokeFirebaseProxy(_ payload: [String: Any]) async throws -> String {
        let callable = Functions.functions().httpsCallable(Self.firebaseCallableName)
        callable.timeoutInterval = 240
        let result = try await callable.call(payload)
        guard let dict = result.data as? [String: Any],
              let text = dict["text"] as? String else {
            throw OpenAIError.apiError("Invalid response from analysis service.")
        }
        return text
    }

    func generateCompletion(prompt: String, model: String = Config.defaultModel, maxTokens: Int = Config.defaultMaxTokens, temperature: Double = Config.defaultTemperature, retryCount: Int = 0) async throws -> String {
        do {
            return try await invokeFirebaseProxy([
                "kind": "text",
                "prompt": prompt,
                "model": model,
                "maxTokens": maxTokens,
                "temperature": temperature,
            ])
        } catch {
            if retryCount < 2, let urlError = error as? URLError, urlError.code == .networkConnectionLost {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return try await generateCompletion(prompt: prompt, model: model, maxTokens: maxTokens, temperature: temperature, retryCount: retryCount + 1)
            }
            throw mapFirebaseFunctionsError(error)
        }
    }
    
    private func mapFirebaseFunctionsError(_ error: Error) -> Error {
        OpenAIError.apiError(error.localizedDescription)
    }

    /// Multimodal or custom `messages` array via Cloud Function (e.g. food image analysis with inline base64 images).
    func firebaseMessagesCompletion(messages: [[String: Any]], model: String, maxTokens: Int, temperature: Double) async throws -> String {
        try await invokeFirebaseProxy([
            "kind": "messages",
            "messages": messages,
            "model": model,
            "maxTokens": maxTokens,
            "temperature": temperature,
        ])
    }

    func generateVisionCompletion(prompt: String, images: [UIImage], maxTokens: Int = 500, temperature: Double = 0.3, retryCount: Int = 0) async throws -> String {
        var contentArray: [[String: Any]] = [
            ["type": "text", "text": prompt]
        ]
        var uploadedPaths: [String] = []
        var imageURLs: [String] = []

        for (index, image) in images.enumerated() {
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                do {
                    let imagePath = "serp-api/vision_\(UUID().uuidString).jpg"
                    let publicURL = try await FirebaseStorageService.shared.uploadImageForSerpAPI(image: image, path: imagePath)

                    uploadedPaths.append(imagePath)
                    imageURLs.append(publicURL)

                    contentArray.append([
                        "type": "image_url",
                        "image_url": ["url": publicURL]
                    ])

                    print("🔗 Added image \(index + 1) to vision request: \(publicURL)")
                } catch {
                    print("❌ Failed to upload image \(index + 1) for vision: \(error)")
                }
            }
        }

        guard !imageURLs.isEmpty else {
            throw OpenAIError.apiError("Could not upload images for analysis. Check your connection and try again.")
        }

        do {
            let text = try await invokeFirebaseProxy([
                "kind": "vision",
                "prompt": prompt,
                "imageURLs": imageURLs,
                "model": "gpt-4o",
                "maxTokens": maxTokens,
                "temperature": temperature,
            ])
            for path in uploadedPaths {
                FirebaseStorageService.shared.deleteImage(at: path) { error in
                    if let error = error {
                        print("⚠️ Failed to clean up temporary vision image at \(path): \(error)")
                    } else {
                        print("🧹 Cleaned up temporary vision image: \(path)")
                    }
                }
            }
            return text
        } catch {
            for path in uploadedPaths {
                FirebaseStorageService.shared.deleteImage(at: path) { _ in
                    print("🧹 Cleaned up temporary vision image after error: \(path)")
                }
            }
            if retryCount < 2, let urlError = error as? URLError, urlError.code == .networkConnectionLost {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                return try await generateVisionCompletion(prompt: prompt, images: images, maxTokens: maxTokens, temperature: temperature, retryCount: retryCount + 1)
            }
            throw mapFirebaseFunctionsError(error)
        }
    }
}
