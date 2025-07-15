import UIKit
import Foundation
import NaturalLanguage

// MARK: - Text Granularity Level
enum TextGranularityLevel: String, CaseIterable {
    case word = "word"
    case sentence = "sentence"
    case paragraph = "paragraph"
    
    var displayName: String {
        switch self {
        case .word: return "Word Level"
        case .sentence: return "Sentence Level"
        case .paragraph: return "Paragraph Level"
        }
    }
    
    var icon: String {
        switch self {
        case .word: return "🔤"
        case .sentence: return "📝"
        case .paragraph: return "📄"
        }
    }
    
    var description: String {
        switch self {
        case .word: return "Analyze individual words for emotion"
        case .sentence: return "Analyze complete sentences for emotion"
        case .paragraph: return "Analyze entire paragraphs for emotion"
        }
    }
}

// MARK: - PDF Analysis Modes
enum PDFAnalysisMode: String, CaseIterable {
    case textOnly = "text_only"
    case imageOnly = "image_only"
    case textAndImage = "text_and_image"
    
    var displayName: String {
        switch self {
        case .textOnly: return "Text Only"
        case .imageOnly: return "Image Only"
        case .textAndImage: return "Text & Image"
        }
    }
    
    var icon: String {
        switch self {
        case .textOnly: return "📄"
        case .imageOnly: return "🖼️"
        case .textAndImage: return "📄🖼️"
        }
    }
}

// MARK: - Analysis Results
struct PDFAnalysisResult {
    let mode: PDFAnalysisMode
    let textRegions: [TextEmotionRegion]
    let imageRegions: [ImageEmotionRegion]
    let analysisTimestamp: Date
    let processingTime: TimeInterval
    
    var totalRegions: Int {
        return textRegions.count + imageRegions.count
    }
}

// MARK: - Text Emotion Regions (Enhanced)
struct TextEmotionRegion {
    let id: UUID
    let text: String
    let boundingBox: CGRect
    let emotion: EmotionType
    let confidence: Float
    let keywords: [String]
    let reasoning: String
    let pageIndex: Int
    let granularityLevel: TextGranularityLevel
    let textRange: NSRange?
    
    init(text: String, boundingBox: CGRect, emotion: EmotionType, confidence: Float, keywords: [String] = [], reasoning: String = "", pageIndex: Int = 0, granularityLevel: TextGranularityLevel = .sentence, textRange: NSRange? = nil) {
        self.id = UUID()
        self.text = text
        self.boundingBox = boundingBox
        self.emotion = emotion
        self.confidence = confidence
        self.keywords = keywords
        self.reasoning = reasoning
        self.pageIndex = pageIndex
        self.granularityLevel = granularityLevel
        self.textRange = textRange
    }
}

// MARK: - Image Emotion Regions
struct ImageEmotionRegion {
    let id: UUID
    let imageData: Data?
    let boundingBox: CGRect
    let emotion: EmotionType
    let confidence: Float
    let description: String
    let visualElements: [String]
    let pageIndex: Int
    
    init(imageData: Data? = nil, boundingBox: CGRect, emotion: EmotionType, confidence: Float, description: String = "", visualElements: [String] = [], pageIndex: Int = 0) {
        self.id = UUID()
        self.imageData = imageData
        self.boundingBox = boundingBox
        self.emotion = emotion
        self.confidence = confidence
        self.description = description
        self.visualElements = visualElements
        self.pageIndex = pageIndex
    }
}

// MARK: - Enhanced GPT Analysis Request
struct GPTAnalysisRequest {
    let mode: PDFAnalysisMode
    let textContent: [String]
    let imageDescriptions: [String]
    let pageCount: Int
    let textGranularity: TextGranularityLevel?
    
    init(mode: PDFAnalysisMode, 
         textContent: [String], 
         imageDescriptions: [String], 
         pageCount: Int,
         textGranularity: TextGranularityLevel? = nil) {
        self.mode = mode
        self.textContent = textContent
        self.imageDescriptions = imageDescriptions
        self.pageCount = pageCount
        self.textGranularity = textGranularity
    }
    
    var prompt: String {
        var prompt = """
        Please analyze the emotional content of the following PDF and return results in JSON format.
        
        Analysis Mode: \(mode.displayName)
        Page Count: \(pageCount)
        """
        
        if let granularity = textGranularity {
            prompt += "\nText Granularity: \(granularity.displayName)"
            prompt += "\nGranularity Description: \(granularity.description)"
        }
        
        if mode == .textOnly || mode == .textAndImage {
            prompt += "\nText Content:\n"
            for (index, text) in textContent.enumerated() {
                prompt += "Page \(index + 1): \(text)\n"
            }
        }
        
        if mode == .imageOnly || mode == .textAndImage {
            prompt += "\nImage Descriptions:\n"
            for (index, description) in imageDescriptions.enumerated() {
                prompt += "Image \(index + 1): \(description)\n"
            }
        }
        
        prompt += """
        
        Please return the analysis results in the following JSON format:
        {
          "text_regions": [
            {
              "text": "text content",
              "bounding_box": {"x": 100, "y": 200, "width": 300, "height": 50},
              "emotion": "any emotion word or phrase",
              "confidence": 0.85,
              "keywords": ["keyword1", "keyword2"],
              "reasoning": "analysis reasoning",
              "page_index": 0,
              "granularity_level": "\(textGranularity?.rawValue ?? "sentence")",
              "text_range": {"location": 0, "length": 10}
            }
          ],
          "image_regions": [
            {
              "bounding_box": {"x": 150, "y": 250, "width": 200, "height": 150},
              "emotion": "any emotion word or phrase",
              "confidence": 0.92,
              "description": "image description",
              "visual_elements": ["element1", "element2"],
              "page_index": 0
            }
          ]
        }
        
        Notes:
        1. Coordinate system uses PDF page top-left as origin (0,0)
        2. Emotion can be any descriptive word or phrase (e.g., "joyful", "melancholic", "thrilling", "serene", "nostalgic", "tense", "uplifting", etc.)
        3. Confidence range: 0.0-1.0
        4. Only return regions with clear emotional content
        5. text_range indicates the position of the analyzed text within the original page text
        6. Be creative and specific with emotion descriptions
        """
        
        return prompt
    }
}

// MARK: - GPT Analysis Response (Enhanced)
struct GPTAnalysisResponse: Codable {
    let textRegions: [GPTTextRegion]?
    let imageRegions: [GPTImageRegion]?
    
    enum CodingKeys: String, CodingKey {
        case textRegions = "text_regions"
        case imageRegions = "image_regions"
    }
}

struct GPTTextRegion: Codable {
    let text: String
    let boundingBox: GPTBoundingBox
    let emotion: String
    let confidence: Float
    let keywords: [String]?
    let reasoning: String?
    let pageIndex: Int
    let granularityLevel: String?
    let textRange: GPTTextRange?
    
    enum CodingKeys: String, CodingKey {
        case text, emotion, confidence, keywords, reasoning
        case boundingBox = "bounding_box"
        case pageIndex = "page_index"
        case granularityLevel = "granularity_level"
        case textRange = "text_range"
    }
}

struct GPTTextRange: Codable {
    let location: Int
    let length: Int
}

struct GPTImageRegion: Codable {
    let boundingBox: GPTBoundingBox
    let emotion: String
    let confidence: Float
    let description: String?
    let visualElements: [String]?
    let pageIndex: Int
    
    enum CodingKeys: String, CodingKey {
        case emotion, confidence, description
        case boundingBox = "bounding_box"
        case visualElements = "visual_elements"
        case pageIndex = "page_index"
    }
}

struct GPTBoundingBox: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - PDF Text Layout (Placeholder)
struct PDFTextLayout {
    let characterPositions: [Int: CGPoint] // Character index to position mapping
    let lineBreaks: [Int] // Character indices where lines break
    let fontSize: CGFloat
    let fontName: String
    
    init() {
        self.characterPositions = [:]
        self.lineBreaks = []
        self.fontSize = 12.0
        self.fontName = "Helvetica"
    }
} 