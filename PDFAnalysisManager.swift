import UIKit
import PDFKit
import Foundation

// MARK: - PDF Analysis Manager
class PDFAnalysisManager {
    static let shared = PDFAnalysisManager()
    
    private let contentExtractor = PDFContentExtractor()
    private let emotionAnalyzer = GPTEmotionAnalyzer.shared
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Analyze PDF with granularity support using the correct logic
    func analyzePDFWithGranularity(
        from url: URL,
        mode: PDFAnalysisMode,
        granularity: TextGranularityLevel,
        progressHandler: ((String) -> Void)? = nil
    ) async throws -> PDFAnalysisResult {
        
        progressHandler?("Starting PDF analysis with \(granularity.displayName) granularity")
        
        // Step 1: Extract content from PDF
        progressHandler?("Extracting content from PDF")
        guard let content = try await contentExtractor.extractContent(from: url) else {
            throw PDFAnalysisError.contentExtractionFailed("Failed to extract content from PDF")
        }
        
        // Step 2: Validate content for the selected mode
        try validateContent(content, for: mode)
        
        // Step 3: Analyze content based on mode
        var analysisResult: PDFAnalysisResult
        
        switch mode {
        case .textOnly:
            // Analyze text with granularity using the new logic
            progressHandler?("Analyzing text content with \(granularity.displayName) granularity")
            
            let textRequest = GPTAnalysisRequest(
                mode: .textOnly,
                textContent: content.textContent,
                imageDescriptions: [],
                pageCount: content.pageCount,
                textGranularity: granularity
            )
            
            analysisResult = try await emotionAnalyzer.analyzePDFContentWithGranularity(
                request: textRequest,
                granularity: granularity,
                textPositions: content.textPositions
            )
            
        case .imageOnly:
            // Analyze images with GPT-4 Vision (no granularity needed)
            progressHandler?("Analyzing image content")
            let imageRegions = try await emotionAnalyzer.analyzeImagesWithGPT4Vision(imageRegions: content.imageRegions)
            analysisResult = PDFAnalysisResult(
                mode: mode,
                textRegions: [],
                imageRegions: imageRegions,
                analysisTimestamp: Date(),
                processingTime: 0.0
            )
            
        case .textAndImage:
            // Analyze both text (with granularity) and images
            progressHandler?("Analyzing text and image content")
            
            var textRegions: [TextEmotionRegion] = []
            var imageRegions: [ImageEmotionRegion] = []
            
            // Analyze text with granularity using the new logic
            if !content.textContent.isEmpty {
                progressHandler?("Analyzing text with \(granularity.displayName) granularity")
                let textRequest = GPTAnalysisRequest(
                    mode: .textOnly,
                    textContent: content.textContent,
                    imageDescriptions: [],
                    pageCount: content.pageCount,
                    textGranularity: granularity
                )
                let textResult = try await emotionAnalyzer.analyzePDFContentWithGranularity(
                    request: textRequest,
                    granularity: granularity,
                    textPositions: content.textPositions
                )
                textRegions = textResult.textRegions
            }
            
            // Analyze images
            if !content.imageRegions.isEmpty {
                progressHandler?("Analyzing image content")
                imageRegions = try await emotionAnalyzer.analyzeImagesWithGPT4Vision(imageRegions: content.imageRegions)
            }
            
            analysisResult = PDFAnalysisResult(
                mode: mode,
                textRegions: textRegions,
                imageRegions: imageRegions,
                analysisTimestamp: Date(),
                processingTime: 0.0
            )
        }
        
        progressHandler?("Analysis completed successfully")
        
        print("PDF analysis with granularity completed")
        print("Results:")
        print("   - Text regions: \(analysisResult.textRegions.count)")
        print("   - Image regions: \(analysisResult.imageRegions.count)")
        print("   - Processing time: \(String(format: "%.2f", analysisResult.processingTime))s")
        
        return analysisResult
    }
    
    /// Analyze PDF content for emotional patterns (legacy method)
    /// - Parameters:
    ///   - pdfURL: URL of the PDF file
    ///   - mode: Analysis mode (text only, image only, or both)
    ///   - progressHandler: Optional progress callback
    /// - Returns: Analysis result with emotion regions
    func analyzePDF(
        from pdfURL: URL,
        mode: PDFAnalysisMode,
        progressHandler: ((String) -> Void)? = nil
    ) async throws -> PDFAnalysisResult {
        
        print("Starting PDF analysis")
        print("File: \(pdfURL.lastPathComponent)")
        print("Mode: \(mode.displayName)")
        
        progressHandler?("Extracting PDF content...")
        
        // Step 1: Extract content from PDF
        guard let content = try await contentExtractor.extractContent(from: pdfURL) else {
            throw PDFAnalysisError.contentExtractionFailed("Failed to extract content from PDF")
        }
        
        progressHandler?("Content extracted successfully")
        print("Content extraction completed")
        print("Extracted content:")
        print("   - Text pages: \(content.textContent.count)")
        print("   - Images: \(content.imageRegions.count)")
        print("   - Total pages: \(content.pageCount)")
        
        // Step 2: Validate content based on mode
        try validateContent(content, for: mode)
        
        progressHandler?("Analyzing emotional content...")
        
        // Step 3: Perform analysis based on mode
        let analysisResult: PDFAnalysisResult
        
        switch mode {
        case .textOnly:
            // Analyze text content only - now supports granularity
            let request = GPTAnalysisRequest(
                mode: mode,
                textContent: content.textContent,
                imageDescriptions: [],
                pageCount: content.pageCount,
                textGranularity: .sentence // Default to sentence level for legacy method
            )
            analysisResult = try await emotionAnalyzer.analyzePDFContent(
                request: request,
                textPositions: content.textPositions
            )
            
        case .imageOnly:
            // Analyze images with GPT-4 Vision
            let imageRegions = try await emotionAnalyzer.analyzeImagesWithGPT4Vision(imageRegions: content.imageRegions)
            analysisResult = PDFAnalysisResult(
                mode: mode,
                textRegions: [],
                imageRegions: imageRegions,
                analysisTimestamp: Date(),
                processingTime: 0.0 // Will be calculated below
            )
            
        case .textAndImage:
            // Analyze both text and images using the new unified method
            analysisResult = try await emotionAnalyzer.analyzeTextAndImagesWithVision(
                textContent: content.textContent,
                imageRegions: content.imageRegions
            )
        }
        
        progressHandler?("Analysis completed successfully")
        
        print("PDF analysis completed")
        print("Analysis results:")
        print("   - Text regions: \(analysisResult.textRegions.count)")
        print("   - Image regions: \(analysisResult.imageRegions.count)")
        
        return analysisResult
    }
    
    /// Generate haptic patterns for analysis results
    func generateHapticPatterns(for analysisResult: PDFAnalysisResult) -> [UUID: HapticPattern] {
        var patterns: [UUID: HapticPattern] = [:]
        
        // Generate patterns for text regions
        for textRegion in analysisResult.textRegions {
            let pattern = createFlexibleHapticPattern(
                for: textRegion.emotion, 
                confidence: textRegion.confidence,
                regionType: "text",
                regionId: textRegion.id,
                granularity: textRegion.granularityLevel
            )
            patterns[textRegion.id] = pattern
        }
        
        // Generate patterns for image regions
        for imageRegion in analysisResult.imageRegions {
            let pattern = createFlexibleHapticPattern(
                for: imageRegion.emotion, 
                confidence: imageRegion.confidence,
                regionType: "image",
                regionId: imageRegion.id
            )
            patterns[imageRegion.id] = pattern
        }
        
        print("Generated \(patterns.count) flexible haptic patterns")
        return patterns
    }
    
    /// Create a flexible haptic pattern that can be customized
    private func createFlexibleHapticPattern(
        for emotion: EmotionType, 
        confidence: Float,
        regionType: String,
        regionId: UUID,
        granularity: TextGranularityLevel? = nil
    ) -> HapticPattern {
        // Convert confidence to UInt8 intensity (0-255)
        let intensity = UInt8(confidence * 255.0)
        
        // Create a simple base pattern that can be customized
        let baseEvents = createBaseHapticEvents(for: emotion, intensity: intensity)
        
        // Calculate total duration
        let totalDuration = baseEvents.reduce(0.0) { $0 + $1.duration }
        
        // Create flexible tags based on emotion, region type, and granularity
        var baseTags = [emotion, regionType, "pdf-analysis", "auto-generated"]
        if let granularity = granularity {
            baseTags.append(granularity.rawValue)
        }
        
        // Create pattern name with granularity info
        let patternName: String
        if let granularity = granularity {
            patternName = "\(emotion.capitalized) \(granularity.displayName) Pattern"
        } else {
            patternName = "\(emotion.capitalized) \(regionType.capitalized) Pattern"
        }
        
        // Create description with granularity info
        let description: String
        if let granularity = granularity {
            description = "Flexible haptic pattern for \(emotion) \(granularity.displayName) content (confidence: \(String(format: "%.2f", confidence)))"
        } else {
            description = "Flexible haptic pattern for \(emotion) \(regionType) content (confidence: \(String(format: "%.2f", confidence)))"
        }
        
        return HapticPattern(
            id: UUID().uuidString,
            name: patternName,
            description: description,
            category: .emotion,
            contentTypes: [.text, .image],
            emotion: emotion,
            scene: nil,
            intensity: intensity,
            duration: totalDuration,
            pattern: baseEvents,
            tags: baseTags,
            isCustomizable: true,
            customizableParameters: [
                HapticParameter(
                    name: "Intensity",
                    type: .intensity,
                    defaultValue: Float(intensity) / 255.0,
                    minValue: 0.0,
                    maxValue: 1.0,
                    description: "Overall pattern intensity"
                ),
                HapticParameter(
                    name: "Duration",
                    type: .duration,
                    defaultValue: Float(totalDuration),
                    minValue: 0.1,
                    maxValue: 5.0,
                    description: "Pattern duration in seconds"
                ),
                HapticParameter(
                    name: "Frequency",
                    type: .frequency,
                    defaultValue: 0.2,
                    minValue: 0.01,
                    maxValue: 1.0,
                    description: "Vibration frequency"
                ),
                HapticParameter(
                    name: "Pattern Type",
                    type: .patternType,
                    defaultValue: 0.0, // 0 = simple, 1 = complex
                    minValue: 0.0,
                    maxValue: 1.0,
                    description: "Pattern complexity"
                )
            ],
            metadata: [
                "region_id": regionId.uuidString,
                "region_type": regionType,
                "confidence": confidence,
                "emotion": emotion,
                "created_from": "pdf_analysis",
                "granularity": granularity?.rawValue ?? "unknown"
            ]
        )
    }
    
    /// Create base haptic events that are simple and customizable
    private func createBaseHapticEvents(for emotion: EmotionType, intensity: UInt8) -> [HapticEvent] {
        // Create simple, customizable base patterns instead of fixed complex patterns
        let baseFrequency: Float = 0.2
        let baseDuration: Double = 0.2
        
        // Use string comparison instead of enum cases
        let emotionLower = emotion.lowercased()
        
        switch emotionLower {
        case "positive", "excited", "energetic", "joyful", "happy", "thrilling":
            // Simple positive pattern: two short pulses
            return [
                HapticEvent(timestamp: 0.0, intensity: intensity, duration: baseDuration, type: .vibration(frequency: baseFrequency)),
                HapticEvent(timestamp: baseDuration + 0.1, intensity: intensity, duration: baseDuration, type: .vibration(frequency: baseFrequency))
            ]
            
        case "negative", "sad", "angry", "melancholic", "furious", "depressed":
            // Simple negative pattern: one longer pulse
            return [
                HapticEvent(timestamp: 0.0, intensity: intensity, duration: baseDuration * 1.5, type: .vibration(frequency: baseFrequency * 0.8))
            ]
            
        case "calm", "peaceful", "serene", "tranquil", "relaxed":
            // Simple calm pattern: one gentle pulse
            return [
                HapticEvent(timestamp: 0.0, intensity: intensity, duration: baseDuration * 2.0, type: .vibration(frequency: baseFrequency * 1.5))
            ]
            
        case "surprised", "shocked", "amazed", "astonished":
            // Simple surprise pattern: one quick pulse
            return [
                HapticEvent(timestamp: 0.0, intensity: intensity, duration: baseDuration * 0.5, type: .vibration(frequency: baseFrequency * 2.0))
            ]
            
        case "romantic", "mysterious", "nostalgic", "dreamy", "enchanting":
            // Simple romantic/mysterious pattern: two gentle pulses with gap
            return [
                HapticEvent(timestamp: 0.0, intensity: intensity, duration: baseDuration, type: .vibration(frequency: baseFrequency * 1.2)),
                HapticEvent(timestamp: baseDuration + 0.2, intensity: intensity, duration: baseDuration, type: .vibration(frequency: baseFrequency * 1.2))
            ]
            
        case "neutral", "balanced", "moderate", "stable":
            // Simple neutral pattern: one standard pulse
            return [
                HapticEvent(timestamp: 0.0, intensity: intensity, duration: baseDuration, type: .vibration(frequency: baseFrequency))
            ]
            
        default:
            // Default pattern for unknown emotions
            return [
                HapticEvent(timestamp: 0.0, intensity: intensity, duration: baseDuration, type: .vibration(frequency: baseFrequency))
            ]
        }
    }
    
    /// Generate haptic patterns with custom mapping
    func generateHapticPatternsWithCustomMapping(
        for analysisResult: PDFAnalysisResult,
        customMapping: [EmotionType: HapticPattern]? = nil
    ) -> [UUID: HapticPattern] {
        var patterns: [UUID: HapticPattern] = [:]
        
        // If custom mapping is provided, use it; otherwise use default patterns
        let emotionPatterns = customMapping ?? createDefaultEmotionPatterns()
        
        // Generate patterns for text regions
        for textRegion in analysisResult.textRegions {
            if let customPattern = emotionPatterns[textRegion.emotion] {
                // Use custom pattern but adjust intensity based on confidence
                let adjustedPattern = adjustPatternIntensity(customPattern, confidence: textRegion.confidence)
                patterns[textRegion.id] = adjustedPattern
            } else {
                // Fallback to flexible pattern
                let pattern = createFlexibleHapticPattern(
                    for: textRegion.emotion,
                    confidence: textRegion.confidence,
                    regionType: "text",
                    regionId: textRegion.id,
                    granularity: textRegion.granularityLevel
                )
                patterns[textRegion.id] = pattern
            }
        }
        
        // Generate patterns for image regions
        for imageRegion in analysisResult.imageRegions {
            if let customPattern = emotionPatterns[imageRegion.emotion] {
                // Use custom pattern but adjust intensity based on confidence
                let adjustedPattern = adjustPatternIntensity(customPattern, confidence: imageRegion.confidence)
                patterns[imageRegion.id] = adjustedPattern
            } else {
                // Fallback to flexible pattern
                let pattern = createFlexibleHapticPattern(
                    for: imageRegion.emotion,
                    confidence: imageRegion.confidence,
                    regionType: "image",
                    regionId: imageRegion.id
                )
                patterns[imageRegion.id] = pattern
            }
        }
        
        return patterns
    }
    
    /// Create default emotion patterns that users can customize
    private func createDefaultEmotionPatterns() -> [EmotionType: HapticPattern] {
        var patterns: [EmotionType: HapticPattern] = [:]
        
        // Create patterns for flexible emotion descriptions
        // No longer using fixed emotion categories - let GPT and users define emotions freely
        let sampleEmotions = ["joyful", "melancholic", "thrilling", "serene", "nostalgic", "tense", "uplifting", "contemplative", "energetic", "peaceful", "mysterious", "romantic", "excited", "calm", "surprised", "sad", "angry", "neutral"]
        
        for emotion in sampleEmotions {
            let pattern = createFlexibleHapticPattern(
                for: emotion,
                confidence: 0.8, // Default confidence
                regionType: "default",
                regionId: UUID()
            )
            patterns[emotion] = pattern
        }
        
        return patterns
    }
    
    /// Adjust pattern intensity based on confidence
    private func adjustPatternIntensity(_ pattern: HapticPattern, confidence: Float) -> HapticPattern {
        let adjustedIntensity = UInt8(Float(pattern.intensity) * confidence)
        
        // Create adjusted events
        let adjustedEvents = pattern.pattern.map { event in
            HapticEvent(
                timestamp: event.timestamp,
                intensity: adjustedIntensity,
                duration: event.duration,
                type: event.type
            )
        }
        
        return HapticPattern(
            id: pattern.id,
            name: pattern.name,
            description: pattern.description,
            category: pattern.category,
            contentTypes: pattern.contentTypes,
            emotion: pattern.emotion,
            scene: pattern.scene,
            intensity: adjustedIntensity,
            duration: pattern.duration,
            pattern: adjustedEvents,
            tags: pattern.tags,
            isCustomizable: pattern.isCustomizable,
            customizableParameters: pattern.customizableParameters,
            metadata: pattern.metadata
        )
    }
    
    /// Export analysis results to JSON
    /// - Parameter result: Analysis result to export
    /// - Returns: JSON data
    func exportAnalysisResult(_ result: PDFAnalysisResult) throws -> Data {
        let exportData = AnalysisExportData(
            timestamp: result.analysisTimestamp,
            mode: result.mode.rawValue,
            processingTime: result.processingTime,
            textRegions: result.textRegions.map { region in
                ExportTextRegion(
                    id: region.id.uuidString,
                    text: region.text,
                    boundingBox: ExportBoundingBox(
                        x: region.boundingBox.origin.x,
                        y: region.boundingBox.origin.y,
                        width: region.boundingBox.size.width,
                        height: region.boundingBox.size.height
                    ),
                    emotion: region.emotion,
                    confidence: region.confidence,
                    keywords: region.keywords,
                    reasoning: region.reasoning,
                    pageIndex: region.pageIndex,
                    granularityLevel: region.granularityLevel.rawValue,
                    textRange: region.textRange.map { ExportTextRange(location: $0.location, length: $0.length) }
                )
            },
            imageRegions: result.imageRegions.map { region in
                ExportImageRegion(
                    id: region.id.uuidString,
                    boundingBox: ExportBoundingBox(
                        x: region.boundingBox.origin.x,
                        y: region.boundingBox.origin.y,
                        width: region.boundingBox.size.width,
                        height: region.boundingBox.size.height
                    ),
                    emotion: region.emotion,
                    confidence: region.confidence,
                    description: region.description,
                    visualElements: region.visualElements,
                    pageIndex: region.pageIndex
                )
            }
        )
        
        return try JSONEncoder().encode(exportData)
    }
    
    /// Extract content from PDF for testing purposes
    func extractContentForTesting(from url: URL) async throws -> PDFContent {
        guard let content = try await contentExtractor.extractContent(from: url) else {
            throw PDFAnalysisError.contentExtractionFailed("Failed to extract content from PDF for testing")
        }
        return content
    }
    
    // MARK: - Private Methods
    
    private func validateContent(_ content: PDFContent, for mode: PDFAnalysisMode) throws {
        switch mode {
        case .textOnly:
            guard content.hasText else {
                throw PDFAnalysisError.noTextContent("PDF contains no extractable text content")
            }
            
        case .imageOnly:
            guard content.hasImages else {
                throw PDFAnalysisError.noImageContent("PDF contains no extractable images")
            }
            
        case .textAndImage:
            guard content.hasText || content.hasImages else {
                throw PDFAnalysisError.noContent("PDF contains no extractable text or image content")
            }
        }
    }
}

// MARK: - Export Data Models
struct AnalysisExportData: Codable {
    let timestamp: Date
    let mode: String
    let processingTime: TimeInterval
    let textRegions: [ExportTextRegion]
    let imageRegions: [ExportImageRegion]
}

struct ExportTextRegion: Codable {
    let id: String
    let text: String
    let boundingBox: ExportBoundingBox
    let emotion: String
    let confidence: Float
    let keywords: [String]
    let reasoning: String
    let pageIndex: Int
    let granularityLevel: String
    let textRange: ExportTextRange?
    
    init(id: String, text: String, boundingBox: ExportBoundingBox, emotion: String, confidence: Float, keywords: [String], reasoning: String, pageIndex: Int, granularityLevel: String, textRange: ExportTextRange?) {
        self.id = id
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

struct ExportTextRange: Codable {
    let location: Int
    let length: Int
}

struct ExportImageRegion: Codable {
    let id: String
    let boundingBox: ExportBoundingBox
    let emotion: String
    let confidence: Float
    let description: String
    let visualElements: [String]
    let pageIndex: Int
}

struct ExportBoundingBox: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

// MARK: - Errors
enum PDFAnalysisError: Error, LocalizedError {
    case noTextContent(String)
    case noImageContent(String)
    case noContent(String)
    case contentExtractionFailed(String)
    case analysisFailed(String)
    case exportFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noTextContent(let message):
            return "No Text Content: \(message)"
        case .noImageContent(let message):
            return "No Image Content: \(message)"
        case .noContent(let message):
            return "No Content: \(message)"
        case .contentExtractionFailed(let message):
            return "Content Extraction Failed: \(message)"
        case .analysisFailed(let message):
            return "Analysis Failed: \(message)"
        case .exportFailed(let message):
            return "Export Failed: \(message)"
        }
    }
} 