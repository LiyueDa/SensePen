import Foundation
import UIKit
import CoreHaptics
import AVFoundation
import Alamofire

// MARK: - GPT Embedding Service (Moved here to resolve compilation issues)
class GPTEmbeddingService {
    static let shared = GPTEmbeddingService()
    
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/embeddings"
    private var lastRequestTime: Date = Date.distantPast
    private let requestInterval: TimeInterval = 1.0 // 1 second interval
    
    private init() {
        self.apiKey = OpenAIAPIKey.key
    }
    
    // MARK: - Embedding Models
    enum EmbeddingModel: String {
        case textEmbedding3Small = "text-embedding-3-small"
        case textEmbedding3Large = "text-embedding-3-large"
        case textEmbeddingAda002 = "text-embedding-ada-002"
        
        var dimensions: Int {
            switch self {
            case .textEmbedding3Small: return 1536
            case .textEmbedding3Large: return 3072
            case .textEmbeddingAda002: return 1536
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Get embedding for a single text
    func getEmbedding(for text: String, model: EmbeddingModel = .textEmbedding3Small) async throws -> [Float] {
        let request = EmbeddingRequest(input: text, model: model.rawValue)
        
        do {
            let response = try await sendEmbeddingRequest(request)
            return response.data.first?.embedding ?? []
        } catch {
            print("❌ Embedding API Error: \(error)")
            throw EmbeddingError.apiError(error.localizedDescription)
        }
    }
    
    /// Get embeddings for multiple texts
    func getEmbeddings(for texts: [String], model: EmbeddingModel = .textEmbedding3Small) async throws -> [[Float]] {
        let request = EmbeddingRequest(input: texts, model: model.rawValue)
        
        do {
            let response = try await sendEmbeddingRequest(request)
            return response.data.map { $0.embedding }
        } catch {
            print("❌ Batch Embedding API Error: \(error)")
            throw EmbeddingError.apiError(error.localizedDescription)
        }
    }
    
    /// Calculate cosine similarity between two vectors
    func cosineSimilarity(_ vector1: [Float], _ vector2: [Float]) -> Float {
        guard vector1.count == vector2.count && !vector1.isEmpty else { return 0.0 }
        
        let dotProduct = zip(vector1, vector2).map(*).reduce(0, +)
        let magnitude1 = sqrt(vector1.map { $0 * $0 }.reduce(0, +))
        let magnitude2 = sqrt(vector2.map { $0 * $0 }.reduce(0, +))
        
        guard magnitude1 > 0 && magnitude2 > 0 else { return 0.0 }
        
        return dotProduct / (magnitude1 * magnitude2)
    }
    
    /// Find best matching pattern for an emotion using embedding similarity
    func findBestMatchingPattern(
        for emotion: EmotionType,
        in patterns: [HapticPattern],
        model: EmbeddingModel = .textEmbedding3Small
    ) async throws -> (pattern: HapticPattern, similarity: Float) {
        
        // Get emotion embedding
        let emotionEmbedding = try await getEmbedding(for: emotion, model: model)
        
        var bestMatch: (pattern: HapticPattern, similarity: Float)?
        var bestSimilarity: Float = 0.0
        
        // Calculate similarity with each pattern
        for pattern in patterns {
            let patternEmbedding = try await getEmbedding(for: pattern.emotion ?? "", model: model)
            let similarity = cosineSimilarity(emotionEmbedding, patternEmbedding)
            
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestMatch = (pattern, similarity)
            }
        }
        
        guard let match = bestMatch else {
            throw EmbeddingError.noMatchFound("No matching pattern found for emotion: \(emotion)")
        }
        
        print("Best match for '\(emotion)': \(match.pattern.name) (similarity: \(String(format: "%.3f", match.similarity)))")
        return match
    }
    
    /// Batch match emotions to patterns using embeddings
    func batchMatchEmotionsToPatterns(
        emotions: [EmotionType],
        patterns: [HapticPattern],
        model: EmbeddingModel = .textEmbedding3Small
    ) async throws -> [EmotionType: (pattern: HapticPattern, similarity: Float)] {
        
        print("🚀 Starting batch emotion-pattern matching for \(emotions.count) emotions")
        
        var results: [EmotionType: (pattern: HapticPattern, similarity: Float)] = [:]
        
        for emotion in emotions {
            do {
                let match = try await findBestMatchingPattern(for: emotion, in: patterns, model: model)
                results[emotion] = match
            } catch {
                print("⚠️ Failed to match emotion '\(emotion)': \(error)")
                // Continue with other emotions
            }
        }
        
        print("✅ Batch matching completed: \(results.count) matches found")
        return results
    }
    
    /// Create emotion-pattern similarity cache for faster matching
    func createSimilarityCache(
        emotions: [EmotionType],
        patterns: [HapticPattern],
        model: EmbeddingModel = .textEmbedding3Small
    ) async throws -> EmotionPatternCache {
        
        print("📦 Creating similarity cache for \(emotions.count) emotions and \(patterns.count) patterns")
        
        let matches = try await batchMatchEmotionsToPatterns(
            emotions: emotions,
            patterns: patterns,
            model: model
        )
        
        let cache = EmotionPatternCache(
            emotions: emotions,
            patterns: patterns,
            matches: matches,
            model: model,
            createdAt: Date()
        )
        
        print("✅ Similarity cache created with \(matches.count) mappings")
        return cache
    }
    
    // MARK: - Private Methods
    
    private func sendEmbeddingRequest(_ request: EmbeddingRequest) async throws -> EmbeddingResponse {
        // Add request interval control to avoid 429 errors
        let timeSinceLastRequest = Date().timeIntervalSince(lastRequestTime)
        if timeSinceLastRequest < requestInterval {
            let waitTime = requestInterval - timeSinceLastRequest
            print("⏳ Rate limiting: waiting \(String(format: "%.1f", waitTime))s before next API request...")
            try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
        
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            AF.request(baseURL, method: .post, parameters: request, encoder: JSONParameterEncoder.default, headers: headers)
                .validate()
                .responseDecodable(of: EmbeddingResponse.self) { response in
                    // Update last request time
                    self.lastRequestTime = Date()
                    
                    switch response.result {
                    case .success(let embeddingResponse):
                        continuation.resume(returning: embeddingResponse)
                    case .failure(let error):
                        continuation.resume(throwing: EmbeddingError.apiError(error.localizedDescription))
                    }
                }
        }
    }
}

// MARK: - Embedding Request/Response Models
struct EmbeddingRequest: Codable {
    let input: [String]
    let model: String
    
    init(input: String, model: String) {
        self.input = [input]
        self.model = model
    }
    
    init(input: [String], model: String) {
        self.input = input
        self.model = model
    }
}

struct EmbeddingResponse: Codable {
    let data: [EmbeddingData]
    let model: String
    let usage: EmbeddingUsage
}

struct EmbeddingData: Codable {
    let embedding: [Float]
    let index: Int
    let object: String
}

struct EmbeddingUsage: Codable {
    let promptTokens: Int
    let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Emotion-Pattern Cache
struct EmotionPatternCache {
    let emotions: [EmotionType]
    let patterns: [HapticPattern]
    let matches: [EmotionType: (pattern: HapticPattern, similarity: Float)]
    let model: GPTEmbeddingService.EmbeddingModel
    let createdAt: Date
    
    /// Get cached match for emotion
    func getMatch(for emotion: EmotionType) -> (pattern: HapticPattern, similarity: Float)? {
        return matches[emotion]
    }
    
    /// Get all matches above similarity threshold
    func getMatches(aboveThreshold threshold: Float) -> [EmotionType: (pattern: HapticPattern, similarity: Float)] {
        return matches.filter { $0.value.similarity >= threshold }
    }
    
    /// Check if cache is still valid (e.g., not too old)
    func isValid(maxAge: TimeInterval = 3600) -> Bool {
        return Date().timeIntervalSince(createdAt) < maxAge
    }
}

// MARK: - Embedding Errors
enum EmbeddingError: Error, LocalizedError {
    case apiError(String)
    case noMatchFound(String)
    case invalidResponse(String)
    
    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "Embedding API Error: \(message)"
        case .noMatchFound(let message):
            return "No Match Found: \(message)"
        case .invalidResponse(let message):
            return "Invalid Response: \(message)"
        }
    }
}

// MARK: - Enhanced Haptic Types
enum HapticType {
    case vibration
    case forceFeedback
}

// MARK: - Force Feedback Types (from original library)
enum ForceFeedbackType {
    case navigationPath
    case wall
}

// MARK: - Detailed Haptic Parameters (from original library)
struct HapticParameters {
    // Vibration parameters
    var intensity: Float // 0.0 - 1.0
    var frequency: Float // Hz
    var duration: TimeInterval
    var sharpness: Float // 0.0 - 1.0
    
    // Force feedback parameters
    var forceMagnitude: Float // N
    var forceDirection: CGVector
    var forceDuration: TimeInterval
    
    // Audio haptic specific parameters
    var repeatCount: Int = 1
    var overallIntensity: Float = 1.0 // Overall vibration amplitude adjustment
    
    // Parameter limits
    var parameterLimits: HapticParameterLimits?
    
    init(intensity: Float, frequency: Float, duration: TimeInterval, sharpness: Float, 
         forceMagnitude: Float, forceDirection: CGVector, forceDuration: TimeInterval,
         repeatCount: Int = 1, overallIntensity: Float = 1.0, parameterLimits: HapticParameterLimits? = nil) {
        self.intensity = intensity
        self.frequency = frequency
        self.duration = duration
        self.sharpness = sharpness
        self.forceMagnitude = forceMagnitude
        self.forceDirection = forceDirection
        self.forceDuration = forceDuration
        self.repeatCount = repeatCount
        self.overallIntensity = overallIntensity
        self.parameterLimits = parameterLimits
    }
}

// MARK: - Parameter Limits (from original library)
struct HapticParameterLimits {
    // Vibration parameter limits
    var intensityRange: ClosedRange<Float>
    var frequencyRange: ClosedRange<Float>
    var durationRange: ClosedRange<TimeInterval>
    var sharpnessRange: ClosedRange<Float>
    
    // Force feedback parameter limits
    var forceMagnitudeRange: ClosedRange<Float>
    var forceDurationRange: ClosedRange<TimeInterval>
    
    // Default limits
    static let defaultLimits = HapticParameterLimits(
        intensityRange: 0.0...1.0,
        frequencyRange: 0.1...1000.0,
        durationRange: 0.01...5.0,
        sharpnessRange: 0.0...1.0,
        forceMagnitudeRange: 0.1...10.0,
        forceDurationRange: 0.01...5.0
    )
    
    // Audio haptic limits
    static let audioLimits = HapticParameterLimits(
        intensityRange: 0.0...1.0,
        frequencyRange: 0.1...Float.infinity,
        durationRange: 0.01...TimeInterval.infinity,
        sharpnessRange: 0.0...1.0,
        forceMagnitudeRange: 0.1...Float.infinity,
        forceDurationRange: 0.01...TimeInterval.infinity
    )
}

// MARK: - Legacy Haptic Preset (from original library)
struct HapticPreset: Hashable {
    let id: UUID
    let name: String
    let type: HapticType
    let parameters: HapticParameters
    let targetTypes: Set<HapticTargetType>
    var tags: Set<String>
    var audioFileURL: URL? // For audio-based haptics
    
    init(name: String, type: HapticType, parameters: HapticParameters, targetTypes: Set<HapticTargetType>, tags: Set<String> = [], audioFileURL: URL? = nil) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.parameters = parameters
        self.targetTypes = targetTypes
        self.tags = tags
        self.audioFileURL = audioFileURL
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: HapticPreset, rhs: HapticPreset) -> Bool {
        return lhs.id == rhs.id
    }
    
    // Validate parameters within limits
    func validateParameters() -> Bool {
        guard let limits = parameters.parameterLimits else { return true }
        
        // Check vibration parameters
        if !limits.intensityRange.contains(parameters.intensity) { return false }
        if !limits.frequencyRange.contains(parameters.frequency) { return false }
        if !limits.durationRange.contains(parameters.duration) { return false }
        if !limits.sharpnessRange.contains(parameters.sharpness) { return false }
        
        // Check force feedback parameters
        if !limits.forceMagnitudeRange.contains(parameters.forceMagnitude) { return false }
        if !limits.forceDurationRange.contains(parameters.forceDuration) { return false }
        
        return true
    }
}

// MARK: - Legacy Target Types (for backwards compatibility)
enum HapticTargetType {
    case text
    case image
    case gif
    
    // Convert to ContentType
    var contentType: ContentType {
        switch self {
        case .text: return .text
        case .image: return .image
        case .gif: return .gif
        }
    }
    
    // Convert from ContentType
    init(from contentType: ContentType) {
        switch contentType {
        case .text: self = .text
        case .image: self = .image
        case .gif: self = .gif
        }
    }
}

// MARK: - Audio to Haptic Converter (from original library)
class AudioToHapticConverter {
    private let audioURL: URL
    private var audioFile: AVAudioFile?
    
    init?(audioURL: URL) {
        self.audioURL = audioURL
        do {
            self.audioFile = try AVAudioFile(forReading: audioURL)
        } catch {
            print("Failed to load audio file: \(error)")
            return nil
        }
    }
    
    func analyzeAudio() -> HapticParameters {
        guard let audioFile = audioFile else {
            return defaultParameters()
        }
        
        // Simplified audio analysis - in a real implementation, this would analyze frequency content
        let duration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
        
        // Basic analysis based on file properties
        let intensity: Float = 0.7 // Default intensity
        let frequency: Float = 100.0 // Default frequency
        let sharpness: Float = 0.5 // Default sharpness
        
        return HapticParameters(
            intensity: intensity,
            frequency: frequency,
            duration: duration,
            sharpness: sharpness,
            forceMagnitude: 0,
            forceDirection: CGVector.zero,
            forceDuration: 0,
            parameterLimits: HapticParameterLimits.audioLimits
        )
    }
    
    private func defaultParameters() -> HapticParameters {
        return HapticParameters(
            intensity: 0.5,
            frequency: 100.0,
            duration: 1.0,
            sharpness: 0.5,
            forceMagnitude: 0,
            forceDirection: CGVector.zero,
            forceDuration: 0
        )
    }
}

// MARK: - Haptic Player (from original library)
class HapticPlayer {
    private weak var bleController: BLEController?
    private var hapticEngine: CHHapticEngine?
    
    init(bleController: BLEController? = nil) {
        self.bleController = bleController
        setupHapticEngine()
    }
    
    private func setupHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
            print("Failed to setup haptic engine: \(error)")
        }
    }
    
    func playVibrationOnDevice(parameters: HapticParameters) {
        guard let bleController = bleController else {
            playSystemHaptic(parameters: parameters)
            return
        }
        
        // Send to MagicPen
        bleController.sendVibration(intensity: UInt8(parameters.intensity * 255), duration: parameters.duration)
    }
    
    func playForceFeedback(parameters: HapticParameters) {
        guard let bleController = bleController else {
            print("Force feedback requires MagicPen device")
            return
        }
        
        let x = Double(parameters.forceDirection.dx) * Double(parameters.forceMagnitude)
        let y = Double(parameters.forceDirection.dy) * Double(parameters.forceMagnitude)
        
        bleController.sendForce(x: x, y: y, duration: parameters.forceDuration)
    }
    
    func playCombinedFeedback(forceParameters: HapticParameters, vibrationParameters: HapticParameters) {
        // Play force feedback
        playForceFeedback(parameters: forceParameters)
        
        // Play vibration simultaneously
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) {
            self.playVibrationOnDevice(parameters: vibrationParameters)
        }
    }
    
    func playNavigationPath(points: [CGPoint], duration: TimeInterval) {
        guard let bleController = bleController else {
            print("⚠️ BLE Controller not available for navigation path")
            return
        }
        
        // Execute all points immediately without delay
        for point in points {
                // Convert point to force direction
                let normalizedX = (point.x - 0.5) * 2.0 // Normalize to -1...1
                let normalizedY = (point.y - 0.5) * 2.0
                
            bleController.sendForce(x: Double(normalizedX), y: Double(normalizedY), duration: 0.1)
            }
        
        print("🗺️ Navigation path executed immediately with \(points.count) points")
    }
    
    func playVibration(parameters: HapticParameters) {
        playVibrationOnDevice(parameters: parameters)
    }
    
    private func playSystemHaptic(parameters: HapticParameters) {
        // Fallback to system haptics when MagicPen not available
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    func stop() {
        // Stop all haptic playback
        try? hapticEngine?.stop()
    }
}

// MARK: - Enhanced Haptic Library

/// Enum for vibration motor and force feedback types
enum FeedbackType {
    case vibration  // Vibration motor
    case force      // Force feedback motor
}

// MARK: - Comprehensive Haptic Library
class HapticLibrary {
    
    // MARK: - Properties
    private var patterns: [String: HapticPattern] = [:]
    private var customPatterns: [String: HapticPattern] = [:]
    // Note: Legacy presets removed - using enhanced HapticPattern system only
    private var hapticPlayer: HapticPlayer
    private let config: HapticLibraryConfig
    
    // GPT Embedding Service for intelligent matching
    private let embeddingService = GPTEmbeddingService.shared
    private var emotionPatternCache: EmotionPatternCache?
    private var lastCacheUpdate: Date?
    
    // 🚀 New: Vector cache system
    private var emotionVectorCache: [EmotionType: [Float]] = [:] // Emotion word vector cache
    private var patternVectorCache: [String: [Float]] = [:] // Haptic pattern vector cache
    private var isVectorCacheInitialized = false // Whether the vector cache is initialized
    
    // Prevent duplicate initialization
    private static var isSetupComplete = false
    
    // BLE Controller reference (from original library)
    weak var bleController: BLEController? {
        didSet {
            hapticPlayer = HapticPlayer(bleController: bleController)
        }
    }
    
    // Singleton support (from original library)
    static let shared = HapticLibrary()
    
    // MARK: - Initialization
    init(config: HapticLibraryConfig = .default) {
        self.config = config
        self.hapticPlayer = HapticPlayer()
        setupLibrary()
    }
    
    // Add a method to reconfigure the singleton (if needed)
    func reconfigure(with config: HapticLibraryConfig) {
        // Only reconfigure if the configuration is different
        if self.config.preloadPatterns != config.preloadPatterns ||
           self.config.enableCustomPatterns != config.enableCustomPatterns ||
           self.config.maxCustomPatterns != config.maxCustomPatterns {
            print("🔄 Reconfiguring HapticLibrary with new settings")
            // You can add reconfiguration logic here
        }
    }
    
    // MARK: - Setup Library
    private func setupLibrary() {
        guard !HapticLibrary.isSetupComplete else {
            return
        }
        setupBasicEmotionPatterns()
        Task {
            await initializeVectorCache()
        }
        HapticLibrary.isSetupComplete = true
    }
    
    // 🚀 New: Vector cache system
    private func initializeVectorCache() async {
        // Prevent duplicate initialization
        guard !isVectorCacheInitialized else {
            print("🔄 Vector cache already initialized, skipping...")
            return
        }
        
        print("🧠 Starting vector cache initialization...")
        
        do {
            // 1. Get all emotion words
            let allEmotions = getAllEmotionTypes()
            print("📝 Found \(allEmotions.count) emotion types to vectorize")
            
            // 2. Get all haptic patterns
            let allPatterns = getAllPatterns()
            print("📳 Found \(allPatterns.count) haptic patterns to vectorize")
            
            // 3. Batch compute emotion vectors (single API call)
            print("🔄 Computing emotion vectors in single batch...")
            let emotionVectors = try await embeddingService.getEmbeddings(for: allEmotions)
            for (index, emotion) in allEmotions.enumerated() {
                emotionVectorCache[emotion] = emotionVectors[index]
            }
            print("✅ Cached \(emotionVectors.count) emotion vectors")
            
            // 4. Batch compute pattern vectors (single API call)
            print("🔄 Computing pattern vectors in single batch...")
            let patternTexts = allPatterns.map { pattern in
                // Combine pattern name, emotion, tags as vectorized text
                let patternText = "\(pattern.name) \(pattern.emotion ?? "") \(pattern.tags.joined(separator: " "))"
                return patternText
            }
            let patternVectors = try await embeddingService.getEmbeddings(for: patternTexts)
            for (index, pattern) in allPatterns.enumerated() {
                patternVectorCache[pattern.id] = patternVectors[index]
            }
            print("✅ Cached \(patternVectors.count) pattern vectors")
            
            // 5. Mark cache as initialized
            isVectorCacheInitialized = true
            print("🎉 Vector cache initialization completed!")
            print("📊 Cache stats: \(emotionVectorCache.count) emotions, \(patternVectorCache.count) patterns")
            
        } catch {
            print("❌ Vector cache initialization failed: \(error)")
            print("💡 App will continue with fallback matching mechanism")
            // Even if vector cache fails, app can continue (use fallback matching)
        }
    }
    
    // 🚀 New: Vector cache system
    private func getAllEmotionTypes() -> [EmotionType] {
        let sampleEmotions = [
            "joyful", "melancholic", "thrilling", "serene", "nostalgic", 
            "tense", "uplifting", "contemplative", "energetic", "peaceful", 
            "mysterious", "romantic", "excited", "calm", "surprised", 
            "sad", "angry", "neutral", "positive", "negative"
        ]
        
        // Extract emotion words from all patterns
        let patternEmotions = getAllPatterns().compactMap { $0.emotion }
        let allEmotions = Set(sampleEmotions + patternEmotions)
        
        return Array(allEmotions)
    }
    
    // MARK: - Basic Emotion Patterns for Auto-Matching
    private func setupBasicEmotionPatterns() {
        let sampleEmotions = [
            "joyful", "melancholic", "thrilling", "serene", "nostalgic", 
            "tense", "uplifting", "contemplative", "energetic", "peaceful", 
            "mysterious", "romantic", "excited", "calm", "surprised", 
            "sad", "angry", "neutral", "positive", "negative"
        ]
        for emotion in sampleEmotions {
            let pattern = createBasicEmotionPattern(for: emotion)
            addPattern(pattern)
        }
    }
    
    private func createBasicEmotionPattern(for emotion: EmotionType) -> HapticPattern {
        let (intensity, duration, patternEvents) = getEmotionParameters(for: emotion)
        
        return HapticPattern(
            id: "basic_\(emotion)",
            name: "\(emotion.capitalized) Pattern",
            description: "Basic haptic pattern for \(emotion) emotion - auto-generated for GPT matching",
            category: .emotion,
            contentTypes: ContentType.allCases,
            emotion: emotion,
            scene: nil,
            intensity: intensity,
            duration: duration,
            pattern: patternEvents,
            tags: [emotion, "basic", "auto-generated", "gpt-matching"],
            isCustomizable: true,
            metadata: ["created_from": "basic_emotion_setup", "emotion": emotion]
        )
    }
    
    private func getEmotionParameters(for emotion: EmotionType) -> (UInt8, Double, [HapticEvent]) {
        switch emotion.lowercased() {
        case "positive", "joyful", "excited", "energetic":
            return (80, 0.3, [
                HapticEvent(timestamp: 0.0, intensity: 80, duration: 0.3, type: .vibration(frequency: nil))
            ])
            
        case "negative", "sad", "melancholic":
            return (60, 0.5, [
                HapticEvent(timestamp: 0.0, intensity: 60, duration: 0.5, type: .vibration(frequency: nil))
            ])
            
        case "angry", "thrilling":
            return (100, 0.2, [
                HapticEvent(timestamp: 0.0, intensity: 100, duration: 0.2, type: .vibration(frequency: nil))
            ])
            
        case "calm", "peaceful":
            return (40, 0.4, [
                HapticEvent(timestamp: 0.0, intensity: 40, duration: 0.4, type: .vibration(frequency: nil))
            ])
            
        case "surprised":
            return (90, 0.1, [
                HapticEvent(timestamp: 0.0, intensity: 90, duration: 0.1, type: .vibration(frequency: nil))
            ])
            
        case "romantic", "mysterious":
            return (50, 0.6, [
                HapticEvent(timestamp: 0.0, intensity: 50, duration: 0.3, type: .vibration(frequency: nil)),
                HapticEvent(timestamp: 0.4, intensity: 50, duration: 0.3, type: .vibration(frequency: nil))
            ])
            
        default: // neutral and others
            return (50, 0.2, [
                HapticEvent(timestamp: 0.0, intensity: 50, duration: 0.2, type: .vibration(frequency: nil))
            ])
        }
    }
    
    // MARK: - BLE Controller Configuration
    
    /// Configure BLE Controller
    func configureBleController(_ controller: BLEController) {
        self.bleController = controller
        self.hapticPlayer = HapticPlayer(bleController: controller)
        print("Haptic library configured with BleController, now using MagicPen device")
    }
    
    /// Audio to haptic conversion (from original library)
    func convertAudioToHaptic(from audioURL: URL, repeatCount: Int = 1, overallIntensity: Float = 1.0) throws -> HapticParameters {
        guard let converter = AudioToHapticConverter(audioURL: audioURL) else {
            throw NSError(domain: "HapticsLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create audio converter"])
        }
        
        var parameters = converter.analyzeAudio()
        parameters.repeatCount = repeatCount
        parameters.overallIntensity = overallIntensity
        parameters.parameterLimits = HapticParameterLimits.audioLimits
        return parameters
    }
    
    // MARK: - MagicPen Specific Controls (from original library)
    
    func playVibrationOnMagicPen(intensity: Float, duration: TimeInterval) {
        guard bleController != nil else {
            print("MagicPen not connected, cannot play vibration")
            return
        }
        
        let parameters = HapticParameters(
            intensity: intensity,
            frequency: 0, // MagicPen doesn't need frequency
            duration: duration,
            sharpness: 0,
            forceMagnitude: 0,
            forceDirection: CGVector.zero,
            forceDuration: 0
        )
        
        hapticPlayer.playVibrationOnDevice(parameters: parameters)
    }
    
    func playForceOnMagicPen(forceX: Float, forceY: Float, duration: TimeInterval) {
        guard bleController != nil else {
            print("MagicPen not connected, cannot play force feedback")
            return
        }
        
        let parameters = HapticParameters(
            intensity: 0,
            frequency: 0,
            duration: 0,
            sharpness: 0,
            forceMagnitude: sqrt(forceX*forceX + forceY*forceY),
            forceDirection: CGVector(dx: CGFloat(forceX), dy: CGFloat(forceY)),
            forceDuration: duration
        )
        
        hapticPlayer.playForceFeedback(parameters: parameters)
    }
    
    func playCombinedFeedbackOnMagicPen(forceX: Float, forceY: Float, vibrationIntensity: Float, duration: TimeInterval) {
        guard bleController != nil else {
            print("MagicPen not connected, cannot play combined feedback")
            return
        }
        
        let forceParameters = HapticParameters(
            intensity: 0,
            frequency: 0,
            duration: 0,
            sharpness: 0,
            forceMagnitude: sqrt(forceX*forceX + forceY*forceY),
            forceDirection: CGVector(dx: CGFloat(forceX), dy: CGFloat(forceY)),
            forceDuration: duration
        )
        
        let vibrationParameters = HapticParameters(
            intensity: vibrationIntensity,
            frequency: 0,
            duration: duration,
            sharpness: 0,
            forceMagnitude: 0,
            forceDirection: CGVector.zero,
            forceDuration: 0
        )
        
        hapticPlayer.playCombinedFeedback(forceParameters: forceParameters, vibrationParameters: vibrationParameters)
    }
    
    // Note: Legacy haptic preset playback removed - using enhanced HapticPattern system only
    
    /// Navigation path force feedback (from original library)
    func playNavigationPath(points: [CGPoint], duration: TimeInterval) {
        hapticPlayer.playNavigationPath(points: points, duration: duration)
    }
    
    /// Stop all haptic playback
    func stop() {
        hapticPlayer.stop()
    }
    
    /// Device status check (from original library)
    func isMagicPenConnected() -> Bool {
        return bleController?.isConnected ?? false
    }
    
    func getMagicPenBatteryStatus() -> String {
        return isMagicPenConnected() ? "Connected" : "Not Connected"
    }
    
    // MARK: - Enhanced Pattern Library (new functionality)
    
    /// Get haptic pattern by ID
    func getPattern(by id: String) -> HapticPattern? {
        return patterns[id] ?? customPatterns[id]
    }
    
    /// Get patterns by emotion
    func getPatterns(for emotion: EmotionType) -> [HapticPattern] {
        return getAllPatterns().filter { $0.emotion == emotion }
    }
    
    /// Get patterns by scene
    func getPatterns(for scene: SceneType) -> [HapticPattern] {
        return getAllPatterns().filter { $0.scene == scene }
    }
    
    /// Get patterns by category
    func getPatterns(for category: HapticCategory) -> [HapticPattern] {
        return getAllPatterns().filter { $0.category == category }
    }
    
    /// Get patterns by content type
    func getPatterns(for contentType: ContentType) -> [HapticPattern] {
        return getAllPatterns().filter { $0.contentTypes.contains(contentType) }
    }
    
    /// Get patterns by tag
    func getPatterns(withTag tag: String) -> [HapticPattern] {
        return getAllPatterns().filter { $0.tags.contains(tag) }
    }
    
    /// Get all patterns
    func getAllPatterns() -> [HapticPattern] {
        let allPatterns = Array(patterns.values) + Array(customPatterns.values)
        return allPatterns
    }
    
    /// Get recommended pattern
    func getRecommendedPattern(for contentType: ContentType, 
                              emotion: EmotionType? = nil, 
                              scene: SceneType? = nil) -> HapticPattern {
        // Priority: emotion + content type > scene + content type > default for content type
        if let emotion = emotion {
            let emotionPatterns = getPatterns(for: emotion).filter { $0.contentTypes.contains(contentType) }
            if let pattern = emotionPatterns.first {
                return pattern
            }
        }
        
        if let scene = scene {
            let scenePatterns = getPatterns(for: scene).filter { $0.contentTypes.contains(contentType) }
            if let pattern = scenePatterns.first {
                return pattern
            }
        }
        
        // Default pattern for content type
        let defaultPatterns = getPatterns(for: contentType)
        return defaultPatterns.first ?? getDefaultPattern()
    }
    
    /// Add custom pattern
    func addCustomPattern(_ pattern: HapticPattern) -> Bool {
        guard config.enableCustomPatterns else { return false }
        guard customPatterns.count < config.maxCustomPatterns else { return false }
        
        customPatterns[pattern.id] = pattern
        return true
    }
    
    /// Remove custom pattern
    func removeCustomPattern(id: String) -> Bool {
        guard customPatterns[id] != nil else { return false }
        customPatterns.removeValue(forKey: id)
        return true
    }
    
    // MARK: - Private Methods
    
    private func addPattern(_ pattern: HapticPattern) {
        patterns[pattern.id] = pattern
    }
    
    private func getDefaultPattern() -> HapticPattern {
        // The only default pattern - used when there are no presets or custom patterns
        return HapticPattern(
            id: "default",
            name: "Default Touch",
            description: "Basic haptic feedback - only default pattern available",
            category: .feedback,
            contentTypes: ContentType.allCases,
            intensity: 50, // Medium intensity
            duration: 0.2,
            pattern: [
                HapticEvent(timestamp: 0.0, intensity: 50, duration: 0.2, type: .vibration(frequency: nil))
            ],
            tags: ["default", "basic", "fallback"],
            isCustomizable: true,
            metadata: ["created_from": "default_fallback", "note": "Only pattern when library is empty"]
        )
    }
    
    private func playHapticEvents(_ events: [HapticEvent]) {
        guard let bleController = bleController else {
            print("⚠️ BLE Controller not available for haptic events")
            return
        }
        
        // Execute all events immediately without delay
        for event in events {
            switch event.type {
            case .vibration(let frequency):
                bleController.sendVibration(intensity: event.intensity, duration: event.duration)
                
            case .force(let x, let y):
                bleController.sendForce(x: x, y: y, duration: event.duration)
                
            case .pause:
                // Do nothing for pause - just continue to next event
                break
                
            case .ramp(let startIntensity, let endIntensity):
                // Use average intensity as fallback for ramp
                let avgIntensity = (startIntensity + endIntensity) / 2
                bleController.sendVibration(intensity: avgIntensity, duration: event.duration)
                
            case .pulse(let count, let interval):
                // Simplified pulse implementation - just use the event intensity
                bleController.sendVibration(intensity: event.intensity, duration: event.duration)
            }
        }
    }
    
    /// Get patterns by feedback type (vibration or force)
    func getPatterns(byFeedbackType feedbackType: FeedbackType) -> [HapticPattern] {
        switch feedbackType {
        case .vibration:
            return patterns.values.filter { pattern in
                pattern.tags.contains("vibration") || 
                pattern.pattern.allSatisfy { event in
                    switch event.type {
                    case .vibration, .ramp, .pulse, .pause:
                        return true
                    case .force:
                        return false
                    }
                }
            }
        case .force:
            return patterns.values.filter { pattern in
                pattern.tags.contains("force") ||
                pattern.pattern.contains { event in
                    switch event.type {
                    case .force:
                        return true
                    case .vibration, .ramp, .pulse, .pause:
                        return false
                    }
                }
            }
        }
    }
    
    /// Get vibration patterns only
    func getVibrationPatterns() -> [HapticPattern] {
        return getPatterns(byFeedbackType: .vibration)
    }
    
    /// Get force feedback patterns only  
    func getForcePatterns() -> [HapticPattern] {
        return getPatterns(byFeedbackType: .force)
    }
    
    /// Check if a pattern contains vibration events
    func containsVibration(_ pattern: HapticPattern) -> Bool {
        return pattern.pattern.contains { event in
            switch event.type {
            case .vibration, .ramp, .pulse:
                return true
            case .force, .pause:
                return false
            }
        }
    }
    
    /// Check if a pattern contains force events
    func containsForce(_ pattern: HapticPattern) -> Bool {
        return pattern.pattern.contains { event in
            switch event.type {
            case .force:
                return true
            case .vibration, .ramp, .pulse, .pause:
                return false
            }
        }
    }
    
    /// Get recommended pattern using GPT embedding similarity (optimized version: uses vector cache)
    // If vector cache is not initialized, use the original method
    // 1. Get emotion vector (from cache)
    // 2. Get available haptic patterns
    // 3. Use cached vectors for fast similarity calculation
    // Use cached vectors to calculate similarity
    /// Batch match emotions to patterns using embeddings (optimized version: uses vector cache)
    // If vector cache is not initialized, use the original method
    func getRecommendedPatternWithEmbedding(
        for contentType: ContentType, 
        emotion: EmotionType? = nil, 
        scene: SceneType? = nil,
        forceRefresh: Bool = false
    ) async throws -> (pattern: HapticPattern, similarity: Float) {
        
        guard let emotion = emotion else {
            // Fallback to basic recommendation if no emotion
            let pattern = getRecommendedPattern(for: contentType, emotion: nil, scene: scene)
            return (pattern, 0.0)
        }
        
        // 🚀 New: Vector cache system
        if isVectorCacheInitialized {
            return try await getRecommendedPatternWithCachedVectors(
                for: contentType,
                emotion: emotion,
                scene: scene
            )
        }
        
        // If vector cache is not initialized, use the original method
        print("Vector cache not initialized, using fallback matching")
        return try await getRecommendedPatternWithFallback(
            for: contentType,
            emotion: emotion,
            scene: scene,
            forceRefresh: forceRefresh
        )
    }
    
    // 🚀 New: Vector cache system
    private func getRecommendedPatternWithCachedVectors(
        for contentType: ContentType,
        emotion: EmotionType,
        scene: SceneType?
    ) async throws -> (pattern: HapticPattern, similarity: Float) {
        
        print("Using cached vectors for fast matching: '\(emotion)'")
        
        // 1. Get emotion vector (from cache)
        guard let emotionVector = emotionVectorCache[emotion] else {
            print("Emotion vector not found in cache for '\(emotion)'")
            throw EmbeddingError.noMatchFound("Emotion vector not cached: \(emotion)")
        }
        
        // 2. Get available haptic patterns
        let availablePatterns = getAllPatterns().filter { $0.contentTypes.contains(contentType) }
        guard !availablePatterns.isEmpty else {
            throw EmbeddingError.noMatchFound("No patterns available for content type: \(contentType.displayName)")
        }
        
        // 3. Use cached vectors for fast similarity calculation
        var bestMatch: (pattern: HapticPattern, similarity: Float)?
        var bestSimilarity: Float = 0.0
        
        for pattern in availablePatterns {
            guard let patternVector = patternVectorCache[pattern.id] else {
                print("Pattern vector not found for '\(pattern.name)', skipping")
                continue
            }
            
            // Calculate similarity using cached vectors
            let similarity = embeddingService.cosineSimilarity(emotionVector, patternVector)
            
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestMatch = (pattern, similarity)
            }
        }
        
        guard let match = bestMatch else {
            throw EmbeddingError.noMatchFound("No matching pattern found for emotion: \(emotion)")
        }
        
        print("Cached vector match for '\(emotion)': \(match.pattern.name) (similarity: \(String(format: "%.3f", match.similarity)))")
        return match
    }
    
    private func getRecommendedPatternWithFallback(
        for contentType: ContentType,
        emotion: EmotionType,
        scene: SceneType?,
        forceRefresh: Bool
    ) async throws -> (pattern: HapticPattern, similarity: Float) {
        
        // Check if we need to update cache
        if forceRefresh || shouldUpdateCache() {
            try await updateEmotionPatternCache()
        }
        
        // Try to get match from cache first
        if let cache = emotionPatternCache,
           let cachedMatch = cache.getMatch(for: emotion) {
            print("🎯 Cache hit for '\(emotion)': \(cachedMatch.pattern.name) (similarity: \(String(format: "%.3f", cachedMatch.similarity)))")
            return cachedMatch
        }
        
        // If no cache or no match in cache, do real-time matching
        print("🔄 No cache match for '\(emotion)', performing real-time embedding matching")
        let availablePatterns = getAllPatterns().filter { $0.contentTypes.contains(contentType) }
        
        guard !availablePatterns.isEmpty else {
            throw EmbeddingError.noMatchFound("No patterns available for content type: \(contentType.displayName)")
        }
        
        let match = try await embeddingService.findBestMatchingPattern(
            for: emotion,
            in: availablePatterns
        )
        
        print("✅ Real-time match for '\(emotion)': \(match.pattern.name) (similarity: \(String(format: "%.3f", match.similarity)))")
        return match
    }
    
    /// Batch match emotions to patterns using embeddings (optimized version: uses vector cache)
    func batchMatchEmotionsToPatterns(
        emotions: [EmotionType],
        contentType: ContentType? = nil
    ) async throws -> [EmotionType: (pattern: HapticPattern, similarity: Float)] {
        
        // 🚀 New: Vector cache system
        if isVectorCacheInitialized {
            return try await batchMatchEmotionsToPatternsWithCachedVectors(
                emotions: emotions,
                contentType: contentType
            )
        }
        
        // If vector cache is not initialized, use the original method
        print("⚠️ Vector cache not initialized, using fallback batch matching")
        return try await batchMatchEmotionsToPatternsWithFallback(
            emotions: emotions,
            contentType: contentType
        )
    }
    
    // 🚀 New: Vector cache system
    private func batchMatchEmotionsToPatternsWithCachedVectors(
        emotions: [EmotionType],
        contentType: ContentType?
    ) async throws -> [EmotionType: (pattern: HapticPattern, similarity: Float)] {
        
        print("⚡ Using cached vectors for fast batch matching of \(emotions.count) emotions")
        
        let availablePatterns: [HapticPattern]
        if let contentType = contentType {
            availablePatterns = getAllPatterns().filter { $0.contentTypes.contains(contentType) }
        } else {
            availablePatterns = getAllPatterns()
        }
        
        guard !availablePatterns.isEmpty else {
            throw EmbeddingError.noMatchFound("No patterns available for matching")
        }
        
        var results: [EmotionType: (pattern: HapticPattern, similarity: Float)] = [:]
        
        // Fast matching for each emotion
        for emotion in emotions {
            do {
                let match = try await getRecommendedPatternWithCachedVectors(
                    for: contentType ?? .text,
                    emotion: emotion,
                    scene: nil
                )
                results[emotion] = match
            } catch {
                print("⚠️ Failed to match emotion '\(emotion)': \(error)")
                // 继续处理其他情感
            }
        }
        
        print("✅ Cached vector batch matching completed: \(results.count) matches found")
        return results
    }
    
    // 🚀 New: Vector cache system
    private func batchMatchEmotionsToPatternsWithFallback(
        emotions: [EmotionType],
        contentType: ContentType?
    ) async throws -> [EmotionType: (pattern: HapticPattern, similarity: Float)] {
        
        let availablePatterns: [HapticPattern]
        if let contentType = contentType {
            availablePatterns = getAllPatterns().filter { $0.contentTypes.contains(contentType) }
        } else {
            availablePatterns = getAllPatterns()
        }
        
        guard !availablePatterns.isEmpty else {
            throw EmbeddingError.noMatchFound("No patterns available for matching")
        }
        
        print("🚀 Starting batch emotion-pattern matching for \(emotions.count) emotions")
        
        let matches = try await embeddingService.batchMatchEmotionsToPatterns(
            emotions: emotions,
            patterns: availablePatterns
        )
        
        print("✅ Batch matching completed: \(matches.count) matches found")
        return matches
    }
    
    /// Update emotion-pattern similarity cache
    func updateEmotionPatternCache() async throws {
        print("🔄 Updating emotion-pattern similarity cache...")
        
        let allPatterns = getAllPatterns()
        guard !allPatterns.isEmpty else {
            print("⚠️ No patterns available for cache update")
            return
        }
        
        // Extract unique emotions from patterns
        let emotions = Set(allPatterns.compactMap { $0.emotion }).map { $0 }
        
        guard !emotions.isEmpty else {
            print("⚠️ No emotions found in patterns for cache update")
            return
        }
        
        let cache = try await embeddingService.createSimilarityCache(
            emotions: emotions,
            patterns: allPatterns
        )
        
        self.emotionPatternCache = cache
        self.lastCacheUpdate = Date()
        
        print("✅ Emotion-pattern cache updated with \(cache.matches.count) mappings")
    }
    
    /// Check if cache should be updated
    private func shouldUpdateCache() -> Bool {
        guard let lastUpdate = lastCacheUpdate else { return true }
        
        // Update cache if it's older than 1 hour or if we have new patterns
        let cacheAge = Date().timeIntervalSince(lastUpdate)
        let hasNewPatterns = emotionPatternCache?.patterns.count != getAllPatterns().count
        
        return cacheAge > 3600 || hasNewPatterns
    }
    
    /// Get cache statistics
    func getCacheStats() -> (isValid: Bool, patternCount: Int, matchCount: Int, lastUpdate: Date?) {
        guard let cache = emotionPatternCache else {
            return (false, 0, 0, nil)
        }
        
        return (
            isValid: cache.isValid(),
            patternCount: cache.patterns.count,
            matchCount: cache.matches.count,
            lastUpdate: lastCacheUpdate
        )
    }
    
    /// Clear emotion-pattern cache
    func clearEmotionPatternCache() {
        emotionPatternCache = nil
        lastCacheUpdate = nil
    }
    
    // 🚀 New: Vector cache system
    
    /// Get vector cache status
    func getVectorCacheStatus() -> (isInitialized: Bool, emotionCount: Int, patternCount: Int) {
        return (
            isInitialized: isVectorCacheInitialized,
            emotionCount: emotionVectorCache.count,
            patternCount: patternVectorCache.count
        )
    }
    
    /// Manually reinitialize vector cache
    func reinitializeVectorCache() async {
        print("🔄 Manually reinitializing vector cache...")
        isVectorCacheInitialized = false
        emotionVectorCache.removeAll()
        patternVectorCache.removeAll()
        
        await initializeVectorCache()
    }
    
    /// Clear vector cache
    func clearVectorCache() {
        emotionVectorCache.removeAll()
        patternVectorCache.removeAll()
        isVectorCacheInitialized = false
    }
    
    /// Check if a specific emotion has cached vectors
    func hasCachedEmotionVector(for emotion: EmotionType) -> Bool {
        return emotionVectorCache[emotion] != nil
    }
    
    /// Check if a specific pattern has cached vectors
    func hasCachedPatternVector(for patternId: String) -> Bool {
        return patternVectorCache[patternId] != nil
    }
    
    /// Get vector cache statistics
    func getVectorCacheStats() -> String {
        let status = getVectorCacheStatus()
        return """
        Vector Cache Status:
        • Initialized: \(status.isInitialized ? "✅ Yes" : "❌ No")
        • Emotion Vectors: \(status.emotionCount)
        • Pattern Vectors: \(status.patternCount)
        • Total Vectors: \(status.emotionCount + status.patternCount)
        """
    }
} 