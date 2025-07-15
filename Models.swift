import UIKit
import Foundation

// MARK: - Content Types
enum ContentType: String, CaseIterable {
    case text = "text"
    case image = "image" 
    case gif = "gif"
    
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .gif: return "GIF"
        }
    }
    
    var icon: String {
        switch self {
        case .text: return "📄"
        case .image: return "🖼️"
        case .gif: return "🎬"
        }
    }
}

// MARK: - Flexible Emotion System (No Hard-coded Types)
// Instead of enum, we use String for flexible emotion types
typealias EmotionType = String

// MARK: - Haptic Pattern Categories
enum HapticCategory: String, CaseIterable {
    case emotion = "emotion"
    case scene = "scene"
    case interaction = "interaction"
    case feedback = "feedback"
    
    var displayName: String {
        switch self {
        case .emotion: return "Emotion"
        case .scene: return "Scene"
        case .interaction: return "Interaction"
        case .feedback: return "Feedback"
        }
    }
}

// MARK: - Scene Types
enum SceneType: String, CaseIterable {
    case reading = "reading"
    case action = "action"
    case nature = "nature"
    case urban = "urban"
    case fantasy = "fantasy"
    case scientific = "scientific"
    case historical = "historical"
    case romantic = "romantic"
    
    var displayName: String {
        switch self {
        case .reading: return "Reading"
        case .action: return "Action"
        case .nature: return "Nature"
        case .urban: return "Urban"
        case .fantasy: return "Fantasy"
        case .scientific: return "Scientific"
        case .historical: return "Historical"
        case .romantic: return "Romantic"
        }
    }
}

// MARK: - Haptic Pattern (Enhanced)
struct HapticPattern {
    let id: String
    let name: String
    let description: String
    let category: HapticCategory
    let contentTypes: [ContentType]
    let emotion: EmotionType?
    let scene: SceneType?
    let intensity: UInt8
    let duration: Double
    let pattern: [HapticEvent]
    let tags: [String]
    let isCustomizable: Bool
    let customizableParameters: [HapticParameter]
    let metadata: [String: Any]
    
    init(id: String, 
         name: String, 
         description: String = "",
         category: HapticCategory,
         contentTypes: [ContentType],
         emotion: EmotionType? = nil,
         scene: SceneType? = nil,
         intensity: UInt8, 
         duration: Double, 
         pattern: [HapticEvent], 
         tags: [String] = [],
         isCustomizable: Bool = false,
         customizableParameters: [HapticParameter] = [],
         metadata: [String: Any] = [:]) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.contentTypes = contentTypes
        self.emotion = emotion
        self.scene = scene
        self.intensity = intensity
        self.duration = duration
        self.pattern = pattern
        self.tags = tags
        self.isCustomizable = isCustomizable
        self.customizableParameters = customizableParameters
        self.metadata = metadata
    }
}

// MARK: - Haptic Parameter (for customization)
struct HapticParameter {
    let name: String
    let type: ParameterType
    let defaultValue: Float
    let minValue: Float
    let maxValue: Float
    let description: String
    
    enum ParameterType {
        case intensity
        case duration
        case frequency
        case force
        case direction
        case patternType
    }
}

// MARK: - Haptic Event (Enhanced)
struct HapticEvent {
    let timestamp: Double
    let intensity: UInt8
    let duration: Double
    let type: HapticEventType
    let metadata: [String: Any]?
    
    init(timestamp: Double, intensity: UInt8, duration: Double, type: HapticEventType, metadata: [String: Any]? = nil) {
        self.timestamp = timestamp
        self.intensity = intensity
        self.duration = duration
        self.type = type
        self.metadata = metadata
    }
}

enum HapticEventType {
    case vibration(frequency: Float?)
    case force(x: Double, y: Double)
    case pause
    case ramp(startIntensity: UInt8, endIntensity: UInt8)
    case pulse(count: Int, interval: Double)
}

// MARK: - Content Segment (Enhanced)
class ContentSegment {
    let id: UUID
    let content: String
    let contentType: ContentType
    let rect: CGRect
    let emotion: EmotionType?
    let scene: SceneType?
    var hapticPattern: HapticPattern?
    let timestamp: Date
    let metadata: [String: Any]
    var isActive: Bool
    var customParameters: [String: Float]
    
    init(content: String, 
         contentType: ContentType,
         rect: CGRect, 
         emotion: EmotionType? = nil,
         scene: SceneType? = nil,
         hapticPattern: HapticPattern? = nil,
         metadata: [String: Any] = [:]) {
        self.id = UUID()
        self.content = content
        self.contentType = contentType
        self.rect = rect
        self.emotion = emotion
        self.scene = scene
        self.hapticPattern = hapticPattern
        self.timestamp = Date()
        self.metadata = metadata
        self.isActive = false
        self.customParameters = [:]
    }
}

// MARK: - Pen Input Data (Enhanced)
struct PenInputData {
    let position: CGPoint
    let force: Float
    let azimuth: Float
    let altitude: Float
    let timestamp: Date
    let inputType: PenInputType
    
    enum PenInputType {
        case hover
        case touch
        case press
        case drag
    }
    
    init(position: CGPoint, force: Float, azimuth: Float, altitude: Float, inputType: PenInputType = .hover) {
        self.position = position
        self.force = force
        self.azimuth = azimuth
        self.altitude = altitude
        self.timestamp = Date()
        self.inputType = inputType
    }
}

// MARK: - Haptic Library Configuration
struct HapticLibraryConfig {
    let preloadPatterns: Bool
    let enableCustomPatterns: Bool
    let maxCustomPatterns: Int
    let supportedContentTypes: [ContentType]
    let defaultIntensityMultiplier: Float
    
    static let `default` = HapticLibraryConfig(
        preloadPatterns: true,
        enableCustomPatterns: true,
        maxCustomPatterns: 50,
        supportedContentTypes: ContentType.allCases,
        defaultIntensityMultiplier: 1.0
    )
} 