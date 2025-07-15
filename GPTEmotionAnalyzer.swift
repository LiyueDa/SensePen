import Foundation
import Alamofire
import UIKit

// MARK: - GPT Emotion Analyzer
class GPTEmotionAnalyzer {
    static let shared = GPTEmotionAnalyzer()
    
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    private init() {
        self.apiKey = OpenAIAPIKey.key
    }
    
    // MARK: - Analysis Methods
    
    /// Analyze PDF content with granularity support using the correct logic
    func analyzePDFContentWithGranularity(
        request: GPTAnalysisRequest,
        granularity: TextGranularityLevel,
        textPositions: [[TextPosition]] = []
    ) async throws -> PDFAnalysisResult {
        let startTime = Date()
        
        print("Starting PDF analysis with granularity")
        print("Analysis mode: \(request.mode.displayName)")
        print("Granularity: \(granularity.displayName)")
        print("Pages: \(request.pageCount)")
        print("Text content pages: \(request.textContent.count)")
        print("Text positions available: \(textPositions.count) pages")
        
        do {
            // Step 1: Combine all page text into one analysis request
            let allText = request.textContent.joined(separator: "\n\n--- PAGE BREAK ---\n\n")
            print("Analyzing all \(request.textContent.count) pages with \(granularity.displayName) granularity")
            print("Total text length: \(allText.count) characters")
            
            // Step 2: Split text into chunks if it's too long
            let maxTokensPerChunk = 6000 // Leave some buffer for prompt and response
            let chunks = splitTextIntoChunks(allText, maxTokens: maxTokensPerChunk)
            print("Split text into \(chunks.count) chunks for processing")
            
            // Step 3: Analyze each chunk separately
            var allSegments: [GPTSegment] = []
            for (chunkIndex, chunk) in chunks.enumerated() {
                print("Processing chunk \(chunkIndex + 1)/\(chunks.count)")
                do {
                    let chunkSegments = try await analyzeTextByGranularity(
                        text: chunk,
                        granularity: granularity
                    )
                    allSegments.append(contentsOf: chunkSegments)
                    print("Chunk \(chunkIndex + 1) processed successfully with \(chunkSegments.count) segments")
                } catch {
                    print("Chunk \(chunkIndex + 1) failed: \(error.localizedDescription)")
                    print("Continuing with remaining chunks...")
                    // Continue processing other chunks instead of failing completely
                }
            }
            
            // Step 4: Match each segment back to its original page and position using real text positions
            print("Matching segments to pages using real text positions...")
            let allTextRegions = matchSegmentsToPagesWithRealPositions(
                gptSegments: allSegments,
                pageTexts: request.textContent,
                textPositions: textPositions,
                granularity: granularity
            )
            
            let analysisTime = Date().timeIntervalSince(startTime)
            
            print("✅ Analysis completed successfully")
            print("📊 Found \(allTextRegions.count) text regions")
            print("📊 Processing time: \(String(format: "%.2f", analysisTime))s")
            
            return PDFAnalysisResult(
                mode: request.mode,
                textRegions: allTextRegions,
                imageRegions: [], // Will be added later if needed
                analysisTimestamp: Date(),
                processingTime: analysisTime
            )
            
        } catch {
            print("❌ GPT Granularity Analysis Error: \(error)")
            print("❌ Error type: \(type(of: error))")
            throw GPTAnalysisError.apiError(error.localizedDescription)
        }
    }
    
    /// Split text into chunks that fit within token limits
    private func splitTextIntoChunks(_ text: String, maxTokens: Int) -> [String] {
        // More conservative estimation: 1 token ≈ 3 characters for English text
        // Also account for prompt overhead
        let promptOverhead = 1000 // Estimated tokens for prompt
        let availableTokens = maxTokens - promptOverhead
        let maxCharsPerChunk = availableTokens * 3
        
        if text.count <= maxCharsPerChunk {
            return [text]
        }
        
        var chunks: [String] = []
        var currentChunk = ""
        let sentences = text.components(separatedBy: [".", "!", "?"])
        
        for sentence in sentences {
            let sentenceWithPunctuation = sentence + "."
            let potentialChunk = currentChunk + sentenceWithPunctuation
            
            if potentialChunk.count > maxCharsPerChunk && !currentChunk.isEmpty {
                // Current chunk is full, start a new one
                chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
                currentChunk = sentenceWithPunctuation
            } else {
                currentChunk = potentialChunk
            }
        }
        
        // Add the last chunk if it's not empty
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        print("📄 Split text into \(chunks.count) chunks:")
        for (index, chunk) in chunks.enumerated() {
            print("   Chunk \(index + 1): \(chunk.count) characters (~\(chunk.count / 3) tokens)")
        }
        
        return chunks
    }
    
    /// Analyze full text by granularity - let GPT decide the segments
    private func analyzeTextByGranularity(
        text: String,
        granularity: TextGranularityLevel
    ) async throws -> [GPTSegment] {
        
        // Create granularity-specific prompt
        let prompt = createGranularityPrompt(text: text, granularity: granularity)
        
        // Send to GPT for analysis
        let result = try await sendTextPrompt(
            prompt: prompt,
            model: "gpt-4",
            maxTokens: 1000,
            temperature: 0.3
        )
        
        // Parse GPT response
        let response = try parseGranularityResponse(result)
        
        print("📝 Found \(response.emotionalSegments.count) emotional segments across all pages")
        return response.emotionalSegments
    }
    
    /// Match GPT-returned segments to their original pages and positions using real text positions
    private func matchSegmentsToPagesWithRealPositions(
        gptSegments: [GPTSegment],
        pageTexts: [String],
        textPositions: [[TextPosition]],
        granularity: TextGranularityLevel
    ) -> [TextEmotionRegion] {
        
        var allRegions: [TextEmotionRegion] = []
        
        for segment in gptSegments {
            print("🔍 Matching segment: '\(segment.text.prefix(50))...'")
            
            // Find the best match across ALL pages using simple text search
            var bestMatch: (pageIndex: Int, boundingBox: CGRect, quality: Float, textRange: NSRange)?
            var bestQuality: Float = 0.0
            
            for (pageIndex, pageText) in pageTexts.enumerated() {
                if let matchResult = findTextInPage(
                    segment: segment.text,
                    pageText: pageText,
                    textPositions: textPositions[pageIndex],
                    granularity: granularity
                ) {
                    if matchResult.quality > bestQuality {
                        bestQuality = matchResult.quality
                        bestMatch = (
                            pageIndex: pageIndex,
                            boundingBox: matchResult.boundingBox,
                            quality: matchResult.quality,
                            textRange: matchResult.textRange
                        )
                    }
                }
            }
            
            // Only create region if we found a good match
            if let match = bestMatch, match.quality > 0.3 {
                let region = TextEmotionRegion(
                    text: segment.text,
                    boundingBox: match.boundingBox,
                    emotion: segment.emotion,
                    confidence: segment.confidence * match.quality, // Adjust confidence based on match quality
                    keywords: [], // Could be extracted from reasoning if needed
                    reasoning: segment.reasoning,
                    pageIndex: match.pageIndex,
                    granularityLevel: granularity,
                    textRange: match.textRange
                )
                
                allRegions.append(region)
                print("✅ Matched segment to page \(match.pageIndex + 1) with quality \(String(format: "%.2f", match.quality))")
                print("📐 Bounding box: \(match.boundingBox)")
            } else {
                print("⚠️ Could not find good match for segment: '\(segment.text.prefix(50))...' (best quality: \(String(format: "%.2f", bestQuality)))")
            }
        }
        
        print("🎯 Successfully matched \(allRegions.count) out of \(gptSegments.count) segments to pages")
        return allRegions
    }
    
    /// Find text in page using exact match first, then fuzzy match as fallback
    private func findTextInPage(
        segment: String,
        pageText: String,
        textPositions: [TextPosition],
        granularity: TextGranularityLevel
    ) -> (boundingBox: CGRect, quality: Float, textRange: NSRange)? {
        
        // Clean the segment text for better matching
        let cleanSegment = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPageText = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Step 1: Try exact match first (highest priority)
        if let exactMatch = findExactTextMatch(cleanSegment, in: textPositions, pageText: cleanPageText) {
            print("✅ Found exact match for segment: '\(cleanSegment.prefix(30))...'")
            return exactMatch
        }
        
        // Step 2: Try fuzzy matching only if exact match fails
        print("🔍 Exact match failed, trying fuzzy match for: '\(cleanSegment.prefix(30))...'")
        let fuzzyMatch = findFuzzyTextMatch(
            segment: cleanSegment,
            pageText: cleanPageText,
            textPositions: textPositions,
            granularity: granularity
        )
        
        return fuzzyMatch
    }
    
    /// Find exact text match in text positions
    private func findExactTextMatch(
        _ segment: String,
        in textPositions: [TextPosition],
        pageText: String
    ) -> (boundingBox: CGRect, quality: Float, textRange: NSRange)? {
        
        // Try to find exact text match in text positions
        for textPosition in textPositions {
            let cleanTextPosition = textPosition.text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check for exact match (case-insensitive)
            if cleanTextPosition.lowercased() == segment.lowercased() {
                return (textPosition.boundingBox, 1.0, NSRange(location: 0, length: segment.count))
            }
            
            // Check if text position contains the segment
            if cleanTextPosition.contains(segment) || segment.contains(cleanTextPosition) {
                return (textPosition.boundingBox, 0.9, NSRange(location: 0, length: segment.count))
            }
        }
        
        // Try to find exact match in page text and map to text positions
        if let range = pageText.range(of: segment, options: .caseInsensitive) {
            let nsRange = NSRange(range, in: pageText)
            if let boundingBox = findBoundingBoxForTextRange(nsRange, in: textPositions, pageText: pageText) {
                return (boundingBox, 1.0, nsRange)
            }
        }
        
        return nil
    }
    
    /// Find bounding box for a text range using text positions
    private func findBoundingBoxForTextRange(
        _ range: NSRange,
        in textPositions: [TextPosition],
        pageText: String
    ) -> CGRect? {
        
        // Find text positions that overlap with the range
        var overlappingPositions: [TextPosition] = []
        
        for textPosition in textPositions {
            // Check if this text position's text appears in the range
            if let textRange = pageText.range(of: textPosition.text, options: .caseInsensitive) {
                let nsTextRange = NSRange(textRange, in: pageText)
                if nsTextRange.location < range.location + range.length && 
                   nsTextRange.location + nsTextRange.length > range.location {
                    overlappingPositions.append(textPosition)
                }
            }
        }
        
        if overlappingPositions.isEmpty {
            return nil
        }
        
        // Calculate the combined bounding box
        let minX = overlappingPositions.map { $0.boundingBox.minX }.min() ?? 0
        let minY = overlappingPositions.map { $0.boundingBox.minY }.min() ?? 0
        let maxX = overlappingPositions.map { $0.boundingBox.maxX }.max() ?? 0
        let maxY = overlappingPositions.map { $0.boundingBox.maxY }.max() ?? 0
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    /// Find fuzzy text match using similarity (only used when exact match fails)
    private func findFuzzyTextMatch(
        segment: String,
        pageText: String,
        textPositions: [TextPosition],
        granularity: TextGranularityLevel
    ) -> (boundingBox: CGRect, quality: Float, textRange: NSRange)? {
        
        var bestMatch: (boundingBox: CGRect, quality: Float, textRange: NSRange)?
        var bestQuality: Float = 0.0
        
        // Split page text into chunks based on granularity for better matching
        let textChunks = splitTextIntoChunks(pageText, granularity: granularity)
        
        for (chunkIndex, chunk) in textChunks.enumerated() {
            let similarity = calculateTextSimilarity(segment, chunk)
            
            // Higher threshold for fuzzy matching since exact match failed
            if similarity > bestQuality && similarity > 0.7 { // Increased threshold from 0.4 to 0.7
                // Find the best text position that matches this chunk
                if let textPosition = findBestTextPositionForChunk(chunk, in: textPositions) {
                    let textRange = NSRange(location: chunkIndex * 100, length: chunk.count) // Approximate range
                    bestQuality = similarity
                    bestMatch = (textPosition.boundingBox, similarity, textRange)
                }
            }
        }
        
        if let match = bestMatch {
            print("🔍 Fuzzy match found with quality: \(String(format: "%.2f", match.quality))")
        }
        
        return bestMatch
    }
    
    /// Calculate text similarity using improved character-based comparison
    private func calculateTextSimilarity(_ text1: String, _ text2: String) -> Float {
        let cleanText1 = text1.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanText2 = text2.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If texts are identical, return 1.0
        if cleanText1 == cleanText2 {
            return 1.0
        }
        
        // If one text contains the other, return high similarity
        if cleanText1.contains(cleanText2) || cleanText2.contains(cleanText1) {
            return 0.9
        }
        
        // Calculate character-based similarity
        let set1 = Set(cleanText1.filter { $0.isLetter || $0.isNumber })
        let set2 = Set(cleanText2.filter { $0.isLetter || $0.isNumber })
        
        let intersection = set1.intersection(set2)
        let union = set1.union(set2)
        
        return union.isEmpty ? 0.0 : Float(intersection.count) / Float(union.count)
    }
    
    /// Find the best text position for a chunk
    private func findBestTextPositionForChunk(_ chunk: String, in textPositions: [TextPosition]) -> TextPosition? {
        var bestPosition: TextPosition?
        var bestSimilarity: Float = 0.0
        
        for textPosition in textPositions {
            let similarity = calculateTextSimilarity(chunk, textPosition.text)
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestPosition = textPosition
            }
        }
        
        return bestPosition
    }
    
    /// Create granularity-specific prompt
    private func createGranularityPrompt(text: String, granularity: TextGranularityLevel) -> String {
        let granularityInstructions = switch granularity {
        case .word:
            "Please identify individual emotionally charged words or short phrases, such as 'love', 'hate', 'beautiful', 'terrible', etc. Focus on vocabulary that carries emotional weight."
        case .sentence:
            "Please identify complete sentences that express distinct emotions. Maintain sentence integrity and consider sentence structure and punctuation."
        case .paragraph:
            "Please identify entire paragraphs with consistent emotional themes. Consider paragraph structure and flow, focusing on overall emotional tone."
        }
        
        return """
        Please analyze the following text chunk and extract emotionally significant segments at the \(granularity.displayName) level.
        
        IMPORTANT: This is a chunk of a larger multi-page document. Focus on analyzing the emotional content within this specific chunk.
        The text may contain content from multiple pages separated by "--- PAGE BREAK ---".
        
        \(granularityInstructions)
        
        CRITICAL REQUIREMENTS FOR TEXT EXTRACTION:
        1. Extract EXACT text segments from the provided chunk - do not modify, summarize, or paraphrase
        2. Use the exact wording, punctuation, and case as it appears in the original text
        3. For word-level: extract individual emotionally charged words or short phrases
        4. For sentence-level: extract complete sentences with proper punctuation
        5. For paragraph-level: extract entire paragraphs with consistent emotional themes
        6. Do not add any text that is not in the original chunk
        7. Do not combine text from different parts of the chunk unless they form a natural unit
        
        Text chunk to analyze:
        \(text)
        
        CRITICAL: You must respond with ONLY valid JSON in this exact format:
        {
          "emotional_segments": [
            {
              "text": "exact text segment from the provided chunk",
              "emotion": "any descriptive emotion word or phrase",
              "confidence": 0.85,
              "reasoning": "explanation of why this segment has this emotion"
            }
          ]
        }
        
        IMPORTANT: If no emotional content is found, return an empty array:
        {
          "emotional_segments": []
        }
        
        Requirements:
        1. Return ONLY the JSON object, no additional text or explanations
        2. The "text" field must be an exact, unmodified segment from the provided text chunk
        3. Extract content at the \(granularity.displayName) level as specified
        4. Only include segments with clear emotional content (confidence > 0.3)
        5. Maintain the original text formatting and case
        6. Do not modify, summarize, or paraphrase the text segments
        7. Focus only on the emotional content within this specific chunk
        8. Each segment should be a complete unit at the specified granularity level
        9. Use valid JSON syntax with proper quotes and commas
        10. If no emotional content is found, return empty array, not text explanation
        11. Ensure text segments can be found in the original chunk for accurate positioning
        12. Be creative and specific with emotion descriptions - use any descriptive emotion word or phrase
        """
    }
    
    /// Calculate bounding box for text range (improved implementation)
    private func calculateBoundingBox(
        for range: NSRange,
        in text: String,
        pageIndex: Int
    ) -> CGRect {
        // Improved calculation for PDF text layout
        let textLength = range.length
        let averageCharWidth: CGFloat = 10.0
        let lineHeight: CGFloat = 18.0
        let charsPerLine: CGFloat = 70.0 // More realistic characters per line for PDF
        let pageMargin: CGFloat = 50.0 // Left margin
        
        // Calculate position based on character index
        let charIndex = range.location
        let lineNumber = CGFloat(charIndex) / charsPerLine
        let charInLine = CGFloat(charIndex).truncatingRemainder(dividingBy: charsPerLine)
        
        // Calculate coordinates (PDF coordinates: origin at bottom-left)
        let x = pageMargin + charInLine * averageCharWidth
        let y = 800.0 - (lineNumber * lineHeight) // Start from top, going down
        let width = CGFloat(textLength) * averageCharWidth
        let height = lineHeight
        
        // Ensure coordinates are within reasonable bounds
        let finalX = max(0, min(x, 600)) // Max width
        let finalY = max(0, min(y, 800)) // Max height
        let finalWidth = min(width, 600 - finalX) // Don't exceed page width
        let finalHeight = min(height, 800 - finalY) // Don't exceed page height
        
        print("📐 Calculated bounding box: (\(finalX), \(finalY), \(finalWidth), \(finalHeight)) for text length \(textLength)")
        
        return CGRect(x: finalX, y: finalY, width: finalWidth, height: finalHeight)
    }

    func analyzePDFContent(request: GPTAnalysisRequest, textPositions: [[TextPosition]] = []) async throws -> PDFAnalysisResult {
        let startTime = Date()
        
        do {
            // Check if granularity is specified - if so, use the new granularity processing
            if let granularity = request.textGranularity {
                print("🔄 Using new granularity processing for \(granularity.displayName)")
                return try await analyzePDFContentWithGranularity(
                    request: request,
                    granularity: granularity,
                    textPositions: textPositions
                )
            }
            
            // Fallback to traditional prompt-based analysis
            print("🔄 Using traditional prompt-based analysis")
            let result = try await sendTextPrompt(
                prompt: request.prompt,
                model: "gpt-4",
                maxTokens: 2000,
                temperature: 0.3
            )
            
            let analysisTime = Date().timeIntervalSince(startTime)
            
            // Parse the JSON response
            let response = try parseGPTResponse(result)
            
            // Convert to our data models with explicit typing
            let textRegions: [TextEmotionRegion] = response.textRegions?.compactMap { gptRegion in
                return TextEmotionRegion(
                    text: gptRegion.text,
                    boundingBox: CGRect(
                        x: gptRegion.boundingBox.x,
                        y: gptRegion.boundingBox.y,
                        width: gptRegion.boundingBox.width,
                        height: gptRegion.boundingBox.height
                    ),
                    emotion: gptRegion.emotion, // Use string directly
                    confidence: gptRegion.confidence,
                    keywords: gptRegion.keywords ?? [],
                    reasoning: gptRegion.reasoning ?? "",
                    pageIndex: gptRegion.pageIndex,
                    granularityLevel: TextGranularityLevel(rawValue: gptRegion.granularityLevel ?? "sentence") ?? .sentence,
                    textRange: gptRegion.textRange.map { NSRange(location: $0.location, length: $0.length) }
                )
            } ?? []
            
            let imageRegions: [ImageEmotionRegion] = response.imageRegions?.compactMap { gptRegion in
                return ImageEmotionRegion(
                    boundingBox: CGRect(
                        x: gptRegion.boundingBox.x,
                        y: gptRegion.boundingBox.y,
                        width: gptRegion.boundingBox.width,
                        height: gptRegion.boundingBox.height
                    ),
                    emotion: gptRegion.emotion, // Use string directly
                    confidence: gptRegion.confidence,
                    description: gptRegion.description ?? "",
                    visualElements: gptRegion.visualElements ?? [],
                    pageIndex: gptRegion.pageIndex
                )
            } ?? []
            
            return PDFAnalysisResult(
                mode: request.mode,
                textRegions: textRegions,
                imageRegions: imageRegions,
                analysisTimestamp: Date(),
                processingTime: analysisTime
            )
            
        } catch {
            print("GPT Analysis Error: \(error)")
            throw GPTAnalysisError.apiError(error.localizedDescription)
        }
    }
    
    /// Analyze images with GPT-4 Vision for detailed description and emotion recognition
    /// This method analyzes ALL images from ALL pages and returns each image as a separate region
    func analyzeImagesWithGPT4Vision(imageRegions: [ImageRegion]) async throws -> [ImageEmotionRegion] {
        print("🖼️ Starting analysis of \(imageRegions.count) images from all pages")
        
        var analyzedRegions: [ImageEmotionRegion] = []
        
        // Analyze each image individually to ensure all images are processed
        for (index, imageRegion) in imageRegions.enumerated() {
            print("📸 Analyzing image \(index + 1)/\(imageRegions.count) from page \(imageRegion.pageIndex + 1)")
            
            do {
                let analyzedRegion = try await analyzeSingleImageWithVision(imageRegion)
                analyzedRegions.append(analyzedRegion)
                print("✅ Successfully analyzed image \(index + 1): \(analyzedRegion.emotion) (confidence: \(String(format: "%.2f", analyzedRegion.confidence)))")
            } catch {
                print("⚠️ Failed to analyze image \(index + 1): \(error)")
                // Create a fallback region with basic info
                let fallbackRegion = ImageEmotionRegion(
                    boundingBox: imageRegion.boundingBox,
                    emotion: "neutral", // Use string instead of enum
                    confidence: 0.5,
                    description: "Image analysis failed",
                    visualElements: [],
                    pageIndex: imageRegion.pageIndex
                )
                analyzedRegions.append(fallbackRegion)
                print("🔄 Created fallback region for image \(index + 1)")
            }
        }
        
        print("🎯 Completed image analysis: \(analyzedRegions.count) regions created")
        return analyzedRegions
    }
    
    private func analyzeSingleImageWithVision(_ imageRegion: ImageRegion) async throws -> ImageEmotionRegion {
        // Convert UIImage to base64 for GPT-4 Vision
        guard let imageData = imageRegion.image.jpegData(compressionQuality: 0.8) else {
            throw GPTAnalysisError.invalidResponse("Failed to convert image to JPEG data")
        }
        
        let base64Image = imageData.base64EncodedString()
        
        // Create vision prompt for emotion analysis
        let visionPrompt = """
        Please analyze this image from a multi-page PDF document and provide:
        1. A detailed description of what you see
        2. The emotional content and mood
        3. Key visual elements that contribute to the emotion
        
        This image is from page \(imageRegion.pageIndex + 1) of the PDF document.
        
        Return your analysis in this JSON format:
        {
          "description": "detailed image description",
          "emotion": "any descriptive emotion word or phrase",
          "confidence": 0.85,
          "visual_elements": ["element1", "element2"],
          "reasoning": "explanation of why this emotion was detected"
        }
        
        Focus on the emotional impact and visual storytelling elements.
        Consider the context of this being part of a larger document.
        Be creative and specific with emotion descriptions.
        """
        
        // Use GPT-4 Vision for analysis
        let result = try await sendMultimodalPromptWithBase64Image(
            text: visionPrompt,
            base64Image: base64Image,
            model: "gpt-4o",
            maxTokens: 1000
        )
        
        // Parse the vision response
        let visionResponse = try parseVisionResponse(result)
        
        // Convert to ImageEmotionRegion (now directly use string)
        return ImageEmotionRegion(
            boundingBox: imageRegion.boundingBox,
            emotion: visionResponse.emotion, // Use string directly
            confidence: visionResponse.confidence,
            description: visionResponse.description,
            visualElements: visionResponse.visualElements,
            pageIndex: imageRegion.pageIndex
        )
    }
    
    /// Analyze text and images together using GPT-4 Vision for images and GPT-4 for text
    func analyzeTextAndImagesWithVision(textContent: [String], imageRegions: [ImageRegion]) async throws -> PDFAnalysisResult {
        let startTime = Date()
        
        var textRegions: [TextEmotionRegion] = []
        var analyzedImageRegions: [ImageEmotionRegion] = []
        
        // Step 1: Analyze text content with GPT-4
        if !textContent.isEmpty {
            let textPrompt = """
            Please analyze the emotional content of the following text and identify regions with distinct emotions.
            
            Text Content:
            \(textContent.enumerated().map { "Page \($0 + 1): \($1)" }.joined(separator: "\n"))
            
            Return your analysis in this JSON format:
            {
              "text_regions": [
                {
                  "text": "text content",
                  "bounding_box": {"x": 100, "y": 200, "width": 300, "height": 50},
                  "emotion": "any descriptive emotion word or phrase",
                  "confidence": 0.85,
                  "keywords": ["keyword1", "keyword2"],
                  "reasoning": "analysis reasoning",
                  "page_index": 0
                }
              ]
            }
            
            Be creative and specific with emotion descriptions.
            """
            
            let textResult = try await sendTextPrompt(
                prompt: textPrompt,
                model: "gpt-4",
                maxTokens: 2000,
                temperature: 0.3
            )
            
            let textResponse = try parseGPTResponse(textResult)
            textRegions = textResponse.textRegions?.compactMap { gptRegion in
                return TextEmotionRegion(
                    text: gptRegion.text,
                    boundingBox: CGRect(
                        x: gptRegion.boundingBox.x,
                        y: gptRegion.boundingBox.y,
                        width: gptRegion.boundingBox.width,
                        height: gptRegion.boundingBox.height
                    ),
                    emotion: gptRegion.emotion, // Use string directly
                    confidence: gptRegion.confidence,
                    keywords: gptRegion.keywords ?? [],
                    reasoning: gptRegion.reasoning ?? "",
                    pageIndex: gptRegion.pageIndex,
                    granularityLevel: TextGranularityLevel(rawValue: gptRegion.granularityLevel ?? "sentence") ?? .sentence,
                    textRange: gptRegion.textRange.map { NSRange(location: $0.location, length: $0.length) }
                )
            } ?? []
        }
        
        // Step 2: Analyze images with GPT-4 Vision
        if !imageRegions.isEmpty {
            analyzedImageRegions = try await analyzeImagesWithGPT4Vision(imageRegions: imageRegions)
        }
        
        let analysisTime = Date().timeIntervalSince(startTime)
        
        return PDFAnalysisResult(
            mode: .textAndImage,
            textRegions: textRegions,
            imageRegions: analyzedImageRegions,
            analysisTimestamp: Date(),
            processingTime: analysisTime
        )
    }
    
    /// Analyze images with text descriptions only (fallback method when Vision API is not available)
    func analyzeImagesWithDescriptions(imageDescriptions: [String]) async throws -> [ImageEmotionRegion] {
        let startTime = Date()
        
        // Create a prompt that includes image descriptions
        let descriptionPrompt = """
        Please analyze the emotional content of the following image descriptions.
        
        Image Descriptions:
        \(imageDescriptions.enumerated().map { "Image \($0 + 1): \($1)" }.joined(separator: "\n"))
        
        Return your analysis in this JSON format:
        {
          "image_regions": [
            {
              "bounding_box": {"x": 150, "y": 250, "width": 200, "height": 150},
              "emotion": "any descriptive emotion word or phrase",
              "confidence": 0.92,
              "description": "image description",
              "visual_elements": ["element1", "element2"],
              "page_index": 0
            }
          ]
        }
        
        Be creative and specific with emotion descriptions.
        """
        
        do {
            let result = try await sendTextPrompt(
                prompt: descriptionPrompt,
                model: "gpt-4",
                maxTokens: 2000,
                temperature: 0.3
            )
            
            let response = try parseGPTResponse(result)
            
            let imageRegions: [ImageEmotionRegion] = response.imageRegions?.compactMap { gptRegion in
                return ImageEmotionRegion(
                    boundingBox: CGRect(
                        x: gptRegion.boundingBox.x,
                        y: gptRegion.boundingBox.y,
                        width: gptRegion.boundingBox.width,
                        height: gptRegion.boundingBox.height
                    ),
                    emotion: gptRegion.emotion, // Use string directly
                    confidence: gptRegion.confidence,
                    description: gptRegion.description ?? "",
                    visualElements: gptRegion.visualElements ?? [],
                    pageIndex: gptRegion.pageIndex
                )
            } ?? []
            
            return imageRegions
            
        } catch {
            print("Image Description Analysis Error: \(error)")
            throw GPTAnalysisError.apiError(error.localizedDescription)
        }
    }
    
    // MARK: - Alamofire API Methods
    
    private func sendTextPrompt(
        prompt: String,
        model: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        print("📤 Sending text prompt to GPT")
        print("📊 Model: \(model)")
        print("📊 Max tokens: \(maxTokens)")
        print("📊 Temperature: \(temperature)")
        print("📊 Prompt length: \(prompt.count) characters")
        
        return try await withCheckedThrowingContinuation { continuation in
            let parameters: [String: Any] = [
                "model": model,
                "messages": [
                    [
                        "role": "user",
                        "content": prompt
                    ]
                ],
                "max_tokens": maxTokens,
                "temperature": temperature
            ]
            
            let headers: HTTPHeaders = [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ]
            
            print("🌐 Making API request to: \(baseURL)")
            print("🔑 API Key (first 10 chars): \(String(apiKey.prefix(10)))...")
            
            AF.request(baseURL, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
                .responseJSON { response in
                    print("📥 Received API response")
                    print("📊 Status code: \(response.response?.statusCode ?? 0)")
                    
                    switch response.result {
                    case .success(let value):
                        print("✅ API Response received")
                        if let json = value as? [String: Any] {
                            print("📄 Response JSON keys: \(json.keys)")
                            
                            // Check for API errors first
                            if let error = json["error"] as? [String: Any] {
                                let errorMessage = error["message"] as? String ?? "Unknown API error"
                                print("❌ API Error: \(errorMessage)")
                                continuation.resume(throwing: GPTAnalysisError.apiError(errorMessage))
                                return
                            }
                            
                            if let choices = json["choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let message = firstChoice["message"] as? [String: Any],
                               let content = message["content"] as? String {
                                print("✅ Content extracted successfully")
                                continuation.resume(returning: content)
                            } else {
                                print("❌ Invalid response structure")
                                print("📄 Full response: \(json)")
                                continuation.resume(throwing: GPTAnalysisError.parsingError("Invalid response format - missing choices or content"))
                            }
                        } else {
                            print("❌ Response is not valid JSON")
                            continuation.resume(throwing: GPTAnalysisError.parsingError("Response is not valid JSON"))
                        }
                    case .failure(let error):
                        print("❌ Request failed with error: \(error)")
                        print("📄 Response status code: \(response.response?.statusCode ?? 0)")
                        print("📄 Response headers: \(response.response?.allHeaderFields ?? [:])")
                        
                        // Try to extract error details from response data
                        if let data = response.data,
                           let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let apiError = errorJson["error"] as? [String: Any],
                           let errorMessage = apiError["message"] as? String {
                            print("❌ API Error details: \(errorMessage)")
                            continuation.resume(throwing: GPTAnalysisError.apiError(errorMessage))
                        } else {
                            continuation.resume(throwing: GPTAnalysisError.apiError(error.localizedDescription))
                        }
                    }
                }
        }
    }
    
    private func sendMultimodalPromptWithBase64Image(
        text: String,
        base64Image: String,
        model: String,
        maxTokens: Int
    ) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let parameters: [String: Any] = [
                "model": model,
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": text
                            ],
                            [
                                "type": "image_url",
                                "image_url": [
                                    "url": "data:image/jpeg;base64,\(base64Image)"
                                ]
                            ]
                        ]
                    ]
                ],
                "max_tokens": maxTokens
            ]
            
            let headers: HTTPHeaders = [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ]
            
            AF.request(baseURL, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
                .responseJSON { response in
                    switch response.result {
                    case .success(let value):
                        print("✅ API Response received")
                        if let json = value as? [String: Any] {
                            print("📄 Response JSON keys: \(json.keys)")
                            
                            // Check for API errors first
                            if let error = json["error"] as? [String: Any] {
                                let errorMessage = error["message"] as? String ?? "Unknown API error"
                                print("❌ API Error: \(errorMessage)")
                                continuation.resume(throwing: GPTAnalysisError.apiError(errorMessage))
                                return
                            }
                            
                            if let choices = json["choices"] as? [[String: Any]],
                               let firstChoice = choices.first,
                               let message = firstChoice["message"] as? [String: Any],
                               let content = message["content"] as? String {
                                print("✅ Content extracted successfully")
                                continuation.resume(returning: content)
                            } else {
                                print("❌ Invalid response structure")
                                print("📄 Full response: \(json)")
                                continuation.resume(throwing: GPTAnalysisError.parsingError("Invalid response format - missing choices or content"))
                            }
                        } else {
                            print("❌ Response is not valid JSON")
                            continuation.resume(throwing: GPTAnalysisError.parsingError("Response is not valid JSON"))
                        }
                    case .failure(let error):
                        print("❌ Request failed with error: \(error)")
                        print("📄 Response status code: \(response.response?.statusCode ?? 0)")
                        print("📄 Response headers: \(response.response?.allHeaderFields ?? [:])")
                        
                        // Try to extract error details from response data
                        if let data = response.data,
                           let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let apiError = errorJson["error"] as? [String: Any],
                           let errorMessage = apiError["message"] as? String {
                            print("❌ API Error details: \(errorMessage)")
                            continuation.resume(throwing: GPTAnalysisError.apiError(errorMessage))
                        } else {
                            continuation.resume(throwing: GPTAnalysisError.apiError(error.localizedDescription))
                        }
                    }
                }
        }
    }
    
    // MARK: - Helper Methods
    private func parseGPTResponse(_ responseText: String) throws -> GPTAnalysisResponse {
        // Clean up the response text to extract JSON
        let cleanedText = cleanGPTResponse(responseText)
        
        do {
            let data = cleanedText.data(using: .utf8) ?? Data()
            let response = try JSONDecoder().decode(GPTAnalysisResponse.self, from: data)
            return response
        } catch {
            print("GPT JSON Parsing Error: \(error)")
            print("Response Text: \(responseText)")
            throw GPTAnalysisError.parsingError("Failed to parse GPT response: \(error.localizedDescription)")
        }
    }
    
    private func parseGranularityResponse(_ responseText: String) throws -> GranularityAnalysisResponse {
        print("🔍 Parsing granularity response...")
        print("📄 Raw response length: \(responseText.count) characters")
        print("📄 Raw response preview: \(String(responseText.prefix(500)))...")
        
        // Clean up the response text to extract JSON
        let cleanedText = cleanGPTResponse(responseText)
        print("📄 Cleaned response length: \(cleanedText.count) characters")
        print("📄 Cleaned response preview: \(String(cleanedText.prefix(500)))...")
        
        do {
            let data = cleanedText.data(using: .utf8) ?? Data()
            let response = try JSONDecoder().decode(GranularityAnalysisResponse.self, from: data)
            print("✅ Successfully parsed granularity response with \(response.emotionalSegments.count) segments")
            return response
        } catch {
            print("❌ Granularity JSON Parsing Error: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            print("📄 Full cleaned response: \(cleanedText)")
            
            // Try to extract any JSON-like content
            if let jsonStart = cleanedText.firstIndex(of: "{"),
               let jsonEnd = cleanedText.lastIndex(of: "}") {
                let jsonContent = String(cleanedText[jsonStart...jsonEnd])
                print("📄 Attempting to parse JSON content: \(jsonContent)")
                
                do {
                    let data = jsonContent.data(using: .utf8) ?? Data()
                    let response = try JSONDecoder().decode(GranularityAnalysisResponse.self, from: data)
                    print("✅ Successfully parsed extracted JSON with \(response.emotionalSegments.count) segments")
                    return response
                } catch {
                    print("❌ Failed to parse extracted JSON: \(error)")
                }
            }
            
            // If all parsing attempts fail, check if it's a "no emotional content" response
            let lowercasedResponse = cleanedText.lowercased()
            if lowercasedResponse.contains("no emotional") || 
               lowercasedResponse.contains("does not contain") ||
               lowercasedResponse.contains("no emotionally") {
                print("📄 Detected 'no emotional content' response, returning empty array")
                return GranularityAnalysisResponse(emotionalSegments: [])
            }
            
            throw GPTAnalysisError.parsingError("Failed to parse granularity response: \(error.localizedDescription)")
        }
    }
    
    private func parseVisionResponse(_ responseText: String) throws -> VisionAnalysisResponse {
        // Clean up the response text to extract JSON
        let cleanedText = cleanGPTResponse(responseText)
        
        do {
            let data = cleanedText.data(using: .utf8) ?? Data()
            let response = try JSONDecoder().decode(VisionAnalysisResponse.self, from: data)
            return response
        } catch {
            print("Vision JSON Parsing Error: \(error)")
            print("Response Text: \(responseText)")
            throw GPTAnalysisError.parsingError("Failed to parse Vision response: \(error.localizedDescription)")
        }
    }
    
    private func cleanGPTResponse(_ response: String) -> String {
        print("🧹 Cleaning GPT response...")
        
        // Remove markdown code blocks if present
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        }
        if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        
        // Try to find JSON content
        if let jsonStart = cleaned.firstIndex(of: "{"),
           let jsonEnd = cleaned.lastIndex(of: "}") {
            let jsonContent = String(cleaned[jsonStart...jsonEnd])
            print("📄 Found JSON content: \(jsonContent.prefix(200))...")
            return jsonContent.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // If no JSON brackets found, return the cleaned text
        print("📄 No JSON brackets found, returning cleaned text")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Split text into chunks based on granularity for fuzzy matching
    private func splitTextIntoChunks(_ text: String, granularity: TextGranularityLevel) -> [String] {
        switch granularity {
        case .word:
            return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        case .sentence:
            return text.components(separatedBy: [".", "!", "?"]).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case .paragraph:
            return text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }
}

// MARK: - Granularity Analysis Response
struct GranularityAnalysisResponse: Codable {
    let emotionalSegments: [GPTSegment]
    
    enum CodingKeys: String, CodingKey {
        case emotionalSegments = "emotional_segments"
    }
}

struct GPTSegment: Codable {
    let text: String
    let emotion: String
    let confidence: Float
    let reasoning: String
}

// MARK: - Vision Analysis Response
struct VisionAnalysisResponse: Codable {
    let description: String
    let emotion: String
    let confidence: Float
    let visualElements: [String]
    let reasoning: String
    
    enum CodingKeys: String, CodingKey {
        case description, emotion, confidence, reasoning
        case visualElements = "visual_elements"
    }
}

// MARK: - Errors
enum GPTAnalysisError: Error, LocalizedError {
    case apiError(String)
    case parsingError(String)
    case invalidResponse(String)
    
    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "API Error: \(message)"
        case .parsingError(let message):
            return "Parsing Error: \(message)"
        case .invalidResponse(let message):
            return "Invalid Response: \(message)"
        }
    }
} 