import UIKit
import PDFKit
import Foundation
import CoreGraphics

// MARK: - Global C Function Pointer for PDF Dictionary Iteration
func imageXObjectCallbackGlobal(key: UnsafePointer<Int8>, value: CGPDFObjectRef, info: UnsafeMutableRawPointer?) {
    let keyString = String(cString: key)
    
    // Check if this is an image XObject
    if CGPDFObjectGetType(value) == .stream {
        var stream: CGPDFStreamRef?
        if CGPDFObjectGetValue(value, .stream, &stream), let stream = stream {
            guard let streamDict = CGPDFStreamGetDictionary(stream) else { return }
            
            var isImage = false
            var subtypeString = "Unknown"
            var width: CGPDFInteger = 0
            var height: CGPDFInteger = 0
            
            // Method 1: Check Subtype field
            var subtype: CGPDFStringRef?
            if CGPDFDictionaryGetString(streamDict, "Subtype", &subtype) {
                if let subtype = subtype, let subtypePtr = CGPDFStringGetBytePtr(subtype) {
                    let subtypeStr = String(cString: subtypePtr)
                    if subtypeStr == "Image" {
                        isImage = true
                        subtypeString = "Image"
                    }
                }
            }
            // Method 2: Check if it has image-related fields (Width, Height, etc.)
            if !isImage {
                var bitsPerComponent: CGPDFInteger = 0
                CGPDFDictionaryGetInteger(streamDict, "Width", &width)
                CGPDFDictionaryGetInteger(streamDict, "Height", &height)
                CGPDFDictionaryGetInteger(streamDict, "BitsPerComponent", &bitsPerComponent)
                if width > 0 && height > 0 {
                    isImage = true
                    subtypeString = "Image (detected by dimensions)"
                }
            }
            // Method 3: Check for image filters
            if !isImage {
                var filter: CGPDFStringRef?
                if CGPDFDictionaryGetString(streamDict, "Filter", &filter) {
                    if let filter = filter, let filterStr = CGPDFStringGetBytePtr(filter) {
                        let filterString = String(cString: filterStr)
                        let imageFilters = ["DCTDecode", "JPXDecode", "FlateDecode", "LZWDecode"]
                        if imageFilters.contains(filterString) {
                            isImage = true
                            subtypeString = "Image (detected by filter: \(filterString))"
                        }
                    }
                }
            }
            if isImage {
                // Try to handle ClosureData first
                if let closureDataPtr = info?.assumingMemoryBound(to: ClosureData.self) {
                    let data = closureDataPtr.pointee
                    let hasRealPosition = data.imagePositions[keyString] != nil
                    let realBoundingBox = data.imagePositions[keyString]
                    
                    // Debug: Print available positions
                    print("🔍 Debug: Checking position for \(keyString)")
                    print("🔍 Debug: Available positions: \(data.imagePositions.keys)")
                    print("🔍 Debug: Has real position: \(hasRealPosition)")
                    
                    // Use real position if available, otherwise fallback
                    let finalBoundingBox: CGRect
                    if hasRealPosition, let realBox = realBoundingBox {
                        finalBoundingBox = realBox
                        print("✅ Using REAL position for \(keyString): \(realBox)")
                    } else {
                        finalBoundingBox = data.extractor.calculateImprovedFallbackImagePosition(
                            for: keyString,
                            pageBounds: data.pageBounds,
                            streamDict: streamDict
                        )
                        print("⚠️ Using FALLBACK position for \(keyString): \(finalBoundingBox)")
                    }
                    
                    if let imageRegion = data.extractor.extractImageFromStreamWithPosition(
                        stream,
                        key: value,
                        boundingBox: finalBoundingBox,
                        pageIndex: data.pageIndex
                    ) {
                        var region = imageRegion
                        if !hasRealPosition {
                            region = ImageRegion(
                                image: imageRegion.image,
                                boundingBox: finalBoundingBox,
                                pageIndex: imageRegion.pageIndex,
                                description: imageRegion.description + " (Fallback position)"
                            )
                        }
                        closureDataPtr.pointee.imageRegions.append(region)
                        print("📷 Image detected: \(keyString) on page \(data.pageIndex + 1)")
                        if hasRealPosition {
                            print("📍 Position: REAL (\(String(format: "%.3f", finalBoundingBox.origin.x)), \(String(format: "%.3f", finalBoundingBox.origin.y)), \(String(format: "%.3f", finalBoundingBox.width))x\(String(format: "%.3f", finalBoundingBox.height)))")
                        } else {
                            print("📍 Position: ESTIMATED (\(String(format: "%.3f", finalBoundingBox.origin.x)), \(String(format: "%.3f", finalBoundingBox.origin.y)), \(String(format: "%.3f", finalBoundingBox.width))x\(String(format: "%.3f", finalBoundingBox.height)))")
                        }
                    }
                } else if let xObjectDataPtr = info?.assumingMemoryBound(to: XObjectData.self) {
                    // Handle XObjectData
                    let data = xObjectDataPtr.pointee
                    let position = data.extractor.calculateImagePositionFromDimensions(
                        width: Int(width),
                        height: Int(height),
                        pageBounds: data.pageBounds,
                        pdfPageBounds: data.pdfPageBounds
                    )
                    xObjectDataPtr.pointee.imagePositions[keyString] = position
                }
            }
        }
    }
}

// MARK: - PDF Content Extractor
class PDFContentExtractor {
    
    // MARK: - Extraction Methods
    func extractContent(from pdfURL: URL) -> PDFContent? {
        // Check if we can access the security scoped resource
        guard pdfURL.startAccessingSecurityScopedResource() else {
            return nil
        }
        
        defer {
            pdfURL.stopAccessingSecurityScopedResource()
        }
        
        // Check if file exists
        let fileExists = FileManager.default.fileExists(atPath: pdfURL.path)
        
        // Also check alternative path for some PDFs
        let alternativePath = pdfURL.path.replacingOccurrences(of: "file://", with: "")
        let alternativeExists = FileManager.default.fileExists(atPath: alternativePath)
        
        guard fileExists || alternativeExists else {
            return nil
        }
        
        // Get file size
        let fileSize: UInt64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: pdfURL.path)
            fileSize = attributes[.size] as? UInt64 ?? 0
        } catch {
            return nil
        }
        
        // Check for reasonable file size
        guard fileSize > 100 else {
            return nil
        }
        
        // Try to load PDF document
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            // Try alternative loading method
            guard let data = try? Data(contentsOf: pdfURL) else {
                return nil
            }
            
            // Check if it's actually a PDF by looking at the header
            let header = String(data: data.prefix(8), encoding: .ascii) ?? ""
            guard header.hasPrefix("%PDF") else {
                return nil
            }
            
            guard let pdfDocument = PDFDocument(data: data) else {
                return nil
            }
            
            return extractContentFromDocument(pdfDocument)
        }
        
        return extractContentFromDocument(pdfDocument)
    }
    
    private func extractContentFromDocument(_ pdfDocument: PDFDocument) -> PDFContent? {
        let pageCount = pdfDocument.pageCount
        
        if pageCount == 0 {
            return nil
        }
        
        var allText: [String] = []
        var allTextPositions: [[TextPosition]] = []
        var allImageDescriptions: [String] = []
        var imageRegions: [ImageRegion] = []
        
        // Process each page
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { 
                continue 
            }
            
            // Extract text from page
            let pageText = extractTextFromPage(page)
            allText.append(pageText)
            
            // Extract text positions from page
            let pageTextPositions = extractTextWithPositions(from: page)
            allTextPositions.append(pageTextPositions)
            
            // Extract images from page using PDFKit native extraction
            let pageImages = extractImagesFromPageWithPDFKit(page, pageIndex: pageIndex)
            imageRegions.append(contentsOf: pageImages)
            
            // Generate basic descriptions for images (will be enhanced by GPT-4 Vision later)
            for imageRegion in pageImages {
                let description = generateBasicImageDescription(for: imageRegion.image)
                allImageDescriptions.append(description)
            }
        }
        
        let content = PDFContent(
            textContent: allText,
            textPositions: allTextPositions,
            imageDescriptions: allImageDescriptions,
            imageRegions: imageRegions,
            pageCount: pageCount
        )
        
        return content
    }
    
    // MARK: - Text Extraction
    private func extractTextFromPage(_ page: PDFPage) -> String {
        guard let pageContent = page.string else {
            return ""
        }
        
        // Clean up the text
        let cleanedText = pageContent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression)
        
        return cleanedText
    }
    
    /// Extract text with their actual positions from PDF page
    private func extractTextWithPositions(from page: PDFPage) -> [TextPosition] {
        var textPositions: [TextPosition] = []
        
        let pageBounds = page.bounds(for: .mediaBox)
        
        // Method 1: Use PDFKit's native text selection to get REAL positions
        if let selections = page.document?.findString("", withOptions: .caseInsensitive) {
            for selection in selections {
                if let selectionPage = selection.pages.first {
                    let bounds = selection.bounds(for: selectionPage)
                    
                    // Convert to relative coordinates
                    let relativeBounds = CGRect(
                        x: bounds.origin.x / pageBounds.width,
                        y: bounds.origin.y / pageBounds.height,
                        width: bounds.width / pageBounds.width,
                        height: bounds.height / pageBounds.height
                    )
                    
                    let textPosition = TextPosition(
                        text: selection.string ?? "",
                        boundingBox: relativeBounds,
                        confidence: 0.9
                    )
                    textPositions.append(textPosition)
                    // print("✅ Added text position with REAL bounds: \(relativeBounds)")
                }
            }
        } else {
            // Fallback: use simple text extraction
            let textPosition = TextPosition(
                text: page.string ?? "",
                boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
                confidence: 0.5
            )
            textPositions.append(textPosition)
        }
        
        // Method 2: Extract character-level positions
        let characterPositions = extractTextPositionsByCharacter(page, pageBounds: pageBounds)
        textPositions.append(contentsOf: characterPositions)
        
        // print("📄 Extracted \(textPositions.count) text positions with REAL PDFKit positions")
        return textPositions
    }
    
    /// Extract text positions by character using PDFKit
    private func extractTextPositionsByCharacter(_ page: PDFPage, pageBounds: CGRect) -> [TextPosition] {
        var textPositions: [TextPosition] = []
        
        guard let pageContent = page.string, !pageContent.isEmpty else {
            return textPositions
        }
        
        // Split content into words and get positions for each
        let words = pageContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        for word in words.prefix(10) { // Limit to first 10 words for performance
            if let selections = page.document?.findString(word, withOptions: .caseInsensitive) {
                for selection in selections {
                    if let selectionPage = selection.pages.first {
                        let bounds = selection.bounds(for: selectionPage)
                        
                        // Convert to relative coordinates
                        let relativeBounds = CGRect(
                            x: bounds.origin.x / pageBounds.width,
                            y: bounds.origin.y / pageBounds.height,
                            width: bounds.width / pageBounds.width,
                            height: bounds.height / pageBounds.height
                        )
                        
                        let textPosition = TextPosition(
                            text: word,
                            boundingBox: relativeBounds,
                            confidence: 0.9
                        )
                        textPositions.append(textPosition)
                        // print("📐 Word '\(word)' at REAL position: \(relativeBounds)")
                    }
                }
            }
        }
        
        return textPositions
    }
    
    // MARK: - Annotation Image Extraction
    private func extractImagesFromAnnotations(_ page: PDFPage, pageIndex: Int) -> [ImageRegion] {
        var imageRegions: [ImageRegion] = []
        
        for annotation in page.annotations {
            if annotation.type == "Stamp" || annotation.type == "Image" {
                let boundingBox = annotation.bounds
                
                // Try to extract actual image data from annotation
                if let image = extractImageFromAnnotation(annotation) {
                    let imageRegion = ImageRegion(
                        image: image,
                        boundingBox: boundingBox,
                        pageIndex: pageIndex,
                        description: "Annotation Image"
                    )
                    imageRegions.append(imageRegion)
                }
            }
        }
        
        return imageRegions
    }
    
    private func extractImageFromAnnotation(_ annotation: PDFAnnotation) -> UIImage? {
        // Method 1: Try to get image data directly
        if let imageData = annotation.value(forKey: "imageData") as? Data {
            return UIImage(data: imageData)
        }
        
        // Method 2: Try to render the annotation as an image
        let bounds = annotation.bounds
        return renderAnnotationAsImage(annotation, bounds: bounds)
    }
    
    private func renderAnnotationAsImage(_ annotation: PDFAnnotation, bounds: CGRect) -> UIImage? {
        // Create a graphics context to render the annotation
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { context in
            // Set up the context with white background
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: bounds.size))
            
            // Save the current graphics state
            context.cgContext.saveGState()
            
            // Try to draw the annotation
            annotation.draw(with: .mediaBox, in: context.cgContext)
            
            // Restore the graphics state
            context.cgContext.restoreGState()
        }
    }
    
    // MARK: - PDFKit Native Image Extraction
    private func extractImagesFromPageWithPDFKit(_ page: PDFPage, pageIndex: Int) -> [ImageRegion] {
        var imageRegions: [ImageRegion] = []
        
        // Method 1: Extract images from annotations
        let annotationImages = extractImagesFromAnnotations(page, pageIndex: pageIndex)
        imageRegions.append(contentsOf: annotationImages)
        
        // Method 2: Extract images using PDFKit native methods
        let pdfKitImages = extractImagesUsingPDFKit(page, pageIndex: pageIndex)
        imageRegions.append(contentsOf: pdfKitImages)
        
        return imageRegions
    }
    
    // MARK: - PDFKit Native Image Detection
    private func extractImagesUsingPDFKit(_ page: PDFPage, pageIndex: Int) -> [ImageRegion] {
        var imageRegions: [ImageRegion] = []
        
        // Get page bounds
        let pageBounds = page.bounds(for: .mediaBox)
        
        // Method 1: Extract images from PDF resources
        if let pageRef = page.pageRef {
            let resourceImages = extractImagesFromPDFResources(pageRef, pageBounds: pageBounds, pageIndex: pageIndex)
            imageRegions.append(contentsOf: resourceImages)
        }
        
        // Method 2: Extract images from PDF content streams (currently not implemented)
        // let contentStreamImages = extractImagesFromContentStreams(page, pageIndex: pageIndex)
        // imageRegions.append(contentsOf: contentStreamImages)
        
        // Method 3: Extract images from PDF XObjects (currently not implemented)
        // if let pageRef = page.pageRef {
        //     let xObjectImages = extractImagesFromXObjects(pageRef, pageBounds: pageBounds, pageIndex: pageIndex)
        //     imageRegions.append(contentsOf: xObjectImages)
        // }
        
        return imageRegions
    }
    
    /// Extract images from PDF resources (most reliable method)
    private func extractImagesFromPDFResources(_ pageRef: CGPDFPage, pageBounds: CGRect, pageIndex: Int) -> [ImageRegion] {
        var imageRegions: [ImageRegion] = []
        
        // Get the page dictionary to access content stream
        guard let pageDictionary = pageRef.dictionary else {
            return imageRegions
        }
        
        // Get the resources dictionary
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDictionary, "Resources", &resources), let resources = resources else {
            return imageRegions
        }
        
        // Get the XObject dictionary (contains images)
        var xObjectDict: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjectDict), let xObjectDict = xObjectDict else {
            return imageRegions
        }
        
        // Parse content stream to find REAL image positions
        let realImagePositions = parseContentStreamForRealImagePositions(pageRef, xObjectDict: xObjectDict, pageBounds: pageBounds)
        
        // Create a data structure to pass to the closure
        var closureData = ClosureData(
            imageRegions: [],
            pageBounds: pageBounds,
            pageIndex: pageIndex,
            extractor: self,
            imagePositions: realImagePositions
        )
        
        // Iterate through XObjects to find images
        CGPDFDictionaryApplyFunction(xObjectDict, imageXObjectCallbackGlobal, &closureData)
        
        // Copy the results back
        imageRegions = closureData.imageRegions
        
        return imageRegions
    }
    
    /// Parse content stream to find REAL image positions using PDFKit
    private func parseContentStreamForRealImagePositions(_ pageRef: CGPDFPage, xObjectDict: CGPDFDictionaryRef, pageBounds: CGRect) -> [String: CGRect] {
        var imagePositions: [String: CGRect] = [:]
        
        // Method 1: Use enhanced content stream parsing (most precise)
        let enhancedPositions = parseContentStreamEnhanced(pageRef, xObjectDict: xObjectDict, pageBounds: pageBounds)
        imagePositions = enhancedPositions
        
        // Method 2: Use PDFKit's REAL annotation analysis for REAL positions (fallback)
        if imagePositions.isEmpty {
            let annotationPositions = getImagePositionsFromPDFKitAnnotations(pageRef, pageBounds: pageBounds)
            imagePositions = annotationPositions
        }
        
        // Method 3: Use PDFKit's REAL content stream analysis (if available)
        if imagePositions.isEmpty {
            let contentStreamInfo = parseContentStreamForRealImageCommands(pageRef, xObjectDict: xObjectDict, pageBounds: pageBounds)
            imagePositions = contentStreamInfo
        }
        
        return imagePositions
    }
    
    /// Get REAL image positions from PDFKit annotations with correct coordinate conversion
    private func getImagePositionsFromPDFKitAnnotations(_ pageRef: CGPDFPage, pageBounds: CGRect) -> [String: CGRect] {
        var imagePositions: [String: CGRect] = [:]
        
        // Get annotations from page dictionary
        guard let pageDictionary = pageRef.dictionary else {
            return imagePositions
        }
        
        var annotations: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(pageDictionary, "Annots", &annotations), let annotations = annotations {
            let annotationCount = CGPDFArrayGetCount(annotations)
            
            for i in 0..<annotationCount {
                var annotation: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(annotations, i, &annotation), let annotation = annotation {
                    
                    // Check if this is an image annotation
                    var subtype: CGPDFStringRef?
                    if CGPDFDictionaryGetString(annotation, "Subtype", &subtype), let subtype = subtype {
                        if let subtypePtr = CGPDFStringGetBytePtr(subtype) {
                            let subtypeString = String(cString: subtypePtr)
                            
                            // Check for various image-related annotation types
                            if subtypeString == "Stamp" || subtypeString == "Image" || subtypeString == "Widget" {
                                // Get annotation bounds
                                var rect: CGPDFArrayRef?
                                if CGPDFDictionaryGetArray(annotation, "Rect", &rect), let rect = rect {
                                    var x1: CGPDFReal = 0
                                    var y1: CGPDFReal = 0
                                    var x2: CGPDFReal = 0
                                    var y2: CGPDFReal = 0
                                    CGPDFArrayGetNumber(rect, 0, &x1)
                                    CGPDFArrayGetNumber(rect, 1, &y1)
                                    CGPDFArrayGetNumber(rect, 2, &x2)
                                    CGPDFArrayGetNumber(rect, 3, &y2)
                                    
                                    // PDF coordinates (bottom-left origin)
                                    let pdfBounds = CGRect(
                                        x: min(x1, x2),
                                        y: min(y1, y2),
                                        width: abs(x2 - x1),
                                        height: abs(y2 - y1)
                                    )
                                    
                                    // Convert to UI coordinates (top-left origin)
                                    let uiBounds = convertPDFBoundsToUIBounds(pdfBounds, pageBounds: pageBounds)
                                    
                                    let xObjectName = "Annot\(i + 1)"
                                    imagePositions[xObjectName] = uiBounds
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return imagePositions
    }
    
    /// Convert PDF bounds to UI bounds with correct coordinate system - IMPROVED
    private func convertPDFBoundsToUIBounds(_ pdfBounds: CGRect, pageBounds: CGRect) -> CGRect {
        // PDF uses bottom-left origin, UI uses top-left origin
        // Convert PDF coordinates to UI coordinates
        
        // Normalize PDF coordinates to page bounds
        let normalizedX = pdfBounds.origin.x / pageBounds.width
        let normalizedY = pdfBounds.origin.y / pageBounds.height
        let normalizedWidth = pdfBounds.width / pageBounds.width
        let normalizedHeight = pdfBounds.height / pageBounds.height
        
        // Convert Y coordinate (PDF bottom-up, UI top-down)
        // PDF: (0,0) is bottom-left, UI: (0,0) is top-left
        let uiY = 1.0 - (normalizedY + normalizedHeight)  // Flip Y axis
        
        let uiBounds = CGRect(
            x: normalizedX,
            y: uiY,
            width: normalizedWidth,
            height: normalizedHeight
        )
        
        return uiBounds
    }
    
    /// Parse content stream for REAL image commands using PDFKit
    private func parseContentStreamForRealImageCommands(_ pageRef: CGPDFPage, xObjectDict: CGPDFDictionaryRef, pageBounds: CGRect) -> [String: CGRect] {
        var imagePositions: [String: CGRect] = [:]
        
        // Get the page dictionary
        guard let pageDictionary = pageRef.dictionary else {
            return imagePositions
        }
        
        // Get content stream
        var contentStream: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(pageDictionary, "Contents", &contentStream), let contentStream = contentStream {
            // Parse content stream for "Do" commands (image drawing)
            let streamData = parseContentStreamDataReal(contentStream, xObjectDict: xObjectDict, pageBounds: pageBounds)
            imagePositions = streamData
        }
        
        return imagePositions
    }
    
    /// Parse content stream data for REAL image commands
    private func parseContentStreamDataReal(_ contentStream: CGPDFStreamRef, xObjectDict: CGPDFDictionaryRef, pageBounds: CGRect) -> [String: CGRect] {
        var imagePositions: [String: CGRect] = [:]
        
        // Get stream data
        var format: CGPDFDataFormat = .raw
        guard let data = CGPDFStreamCopyData(contentStream, &format) else {
            return imagePositions
        }
        
        // Convert to string for parsing
        let dataLength = CFDataGetLength(data)
        let dataPointer = CFDataGetBytePtr(data)
        
        guard dataPointer != nil && dataLength > 0 else {
            return imagePositions
        }
        
        // Convert to string (simplified - in reality you'd need proper PDF content stream parsing)
        let streamString = String(data: Data(bytes: dataPointer!, count: dataLength), encoding: .ascii) ?? ""
        
        // Look for "Do" commands (image drawing commands)
        let lines = streamString.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("Do") {
                // This is an image drawing command
                // Extract the XObject name and position
                let components = line.components(separatedBy: .whitespaces)
                for component in components {
                    if component.hasSuffix("Do") {
                        let xObjectName = String(component.dropLast(2)) // Remove "Do"
                        
                        // Get REAL position from transformation matrix
                        let position = extractRealImagePositionFromCommand(line, pageBounds: pageBounds)
                        imagePositions[xObjectName] = position
                    }
                }
            }
        }
        
        return imagePositions
    }
    
    /// Extract REAL image position from content stream command
    private func extractRealImagePositionFromCommand(_ command: String, pageBounds: CGRect) -> CGRect {
        // Parse transformation matrix from command
        // Format: [a b c d e f] cm ... Do
        let components = command.components(separatedBy: .whitespaces)
        
        var matrix: [CGFloat] = [1, 0, 0, 1, 0, 0] // Default identity matrix
        
        // Look for matrix values in the command
        var matrixIndex = 0
        var inMatrix = false
        
        for component in components {
            if component.hasPrefix("[") {
                // Start of matrix
                matrixIndex = 0
                inMatrix = true
            } else if component.hasSuffix("]") {
                // End of matrix
                inMatrix = false
                break
            } else if inMatrix, let value = Double(component), matrixIndex < 6 {
                matrix[matrixIndex] = CGFloat(value)
                matrixIndex += 1
            }
        }
        
        // Extract REAL position from transformation matrix
        // The matrix [a b c d e f] transforms coordinates as:
        // x' = a*x + c*y + e
        // y' = b*x + d*y + f
        
        // Convert PDF coordinates to UI coordinates
        // PDF uses bottom-left origin, UI uses top-left origin
        let pdfX = matrix[4]  // Translation X in PDF coordinates
        let pdfY = matrix[5]  // Translation Y in PDF coordinates
        
        // Convert to UI coordinates (flip Y axis)
        let uiX = pdfX / pageBounds.width
        let uiY = 1.0 - (pdfY / pageBounds.height)  // Flip Y axis
        
        // Calculate width and height from transformation matrix
        // Use the scale factors from the transformation matrix
        let width = abs(matrix[0]) / pageBounds.width
        let height = abs(matrix[3]) / pageBounds.height
        
        return CGRect(x: uiX, y: uiY, width: width, height: height)
    }
    
    /// Calculate improved fallback image position when content stream analysis fails
    internal func calculateImprovedFallbackImagePosition(for key: String, pageBounds: CGRect, streamDict: CGPDFDictionaryRef) -> CGRect {
        // Get image dimensions from stream dictionary
        var width: CGPDFInteger = 0
        var height: CGPDFInteger = 0
        
        CGPDFDictionaryGetInteger(streamDict, "Width", &width)
        CGPDFDictionaryGetInteger(streamDict, "Height", &height)
        
        if width > 0 && height > 0 {
            // Calculate aspect ratio
            let aspectRatio = CGFloat(width) / CGFloat(height)
            
            // Use intelligent positioning based on image size and aspect ratio
            let maxWidth = 0.6  // 60% of page width
            let maxHeight = 0.4 // 40% of page height
            
            // Scale to fit while maintaining aspect ratio
            let scaleX = maxWidth / aspectRatio
            let scaleY = maxHeight
            let scale = min(scaleX, scaleY, 1.0)
            
            let scaledWidth = maxWidth * scale
            let scaledHeight = maxHeight * scale
            
            // Position in the center of the page with some margin
            let x = (1.0 - scaledWidth) / 2.0
            let y = 0.1 + (0.8 - scaledHeight) / 2.0  // Add top margin
            
            let fallbackRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
            
            return fallbackRect
        }
        
        // Default fallback position for unknown dimensions
        let defaultRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.6)
        
        return defaultRect
    }
    
    /// Calculate fallback image position when content stream analysis fails (legacy method)
    private func calculateFallbackImagePosition(for key: String, pageBounds: CGRect, streamDict: CGPDFDictionaryRef) -> CGRect {
        // Get image dimensions from stream dictionary
        var width: CGPDFInteger = 0
        var height: CGPDFInteger = 0
        
        CGPDFDictionaryGetInteger(streamDict, "Width", &width)
        CGPDFDictionaryGetInteger(streamDict, "Height", &height)
        
        if width > 0 && height > 0 {
            // Calculate aspect ratio
            let aspectRatio = CGFloat(width) / CGFloat(height)
            
            // Use a more sophisticated positioning algorithm
            let maxWidth = 0.7  // 70% of page width
            let maxHeight = 0.5 // 50% of page height
            
            // Scale to fit while maintaining aspect ratio
            let scaleX = maxWidth / aspectRatio
            let scaleY = maxHeight
            let scale = min(scaleX, scaleY, 1.0)
            
            let scaledWidth = maxWidth * scale
            let scaledHeight = maxHeight * scale
            
            // Position in the upper half of the page
            let x = 0.15 + (0.7 - scaledWidth) / 2 // Center horizontally
            let y = 0.1 + (0.4 - scaledHeight) / 2 // Upper half
            
            return CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
        }
        
        // Default fallback position
        return CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.6)
    }
    
    /// Extract image from PDF stream with real position
    internal func extractImageFromStreamWithPosition(_ stream: CGPDFStreamRef, key: CGPDFObjectRef, boundingBox: CGRect, pageIndex: Int) -> ImageRegion? {
        // Get stream data
        var format: CGPDFDataFormat = .raw
        guard let data = CGPDFStreamCopyData(stream, &format) else {
            return nil
        }
        
        // Get stream dictionary for metadata
        guard let streamDict = CGPDFStreamGetDictionary(stream) else { 
            return nil 
        }
        
        // Extract image dimensions
        var width: CGPDFInteger = 0
        var height: CGPDFInteger = 0
        
        CGPDFDictionaryGetInteger(streamDict, "Width", &width)
        CGPDFDictionaryGetInteger(streamDict, "Height", &height)
        
        if width == 0 || height == 0 {
            return nil
        }
        
        // Create image from data
        guard let image = createImageFromPDFData(data, width: Int(width), height: Int(height)) else {
            return nil
        }
        
        let imageRegion = ImageRegion(
            image: image,
            boundingBox: boundingBox,
            pageIndex: pageIndex,
            description: "PDF Image (\(width)x\(height)) - REAL Position from PDF"
        )
        
        return imageRegion
    }
    
    // MARK: - Core Graphics Image Extraction
    private func extractImagesFromPageContent(_ pageRef: CGPDFPage, pageBounds: CGRect, pageIndex: Int) -> [ImageRegion] {
        var imageRegions: [ImageRegion] = []
        
        // Create a graphics context to render the page
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: Int(pageBounds.width),
            height: Int(pageBounds.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        guard let context = context else { return imageRegions }
        
        // Set up the context
        context.setFillColor(UIColor.white.cgColor)
        context.fill(pageBounds)
        
        // Draw the PDF page
        context.translateBy(x: 0, y: pageBounds.height)
        context.scaleBy(x: 1.0, y: -1.0)
        context.drawPDFPage(pageRef)
        
        // Get the rendered image
        guard let cgImage = context.makeImage() else { return imageRegions }
        let renderedImage = UIImage(cgImage: cgImage)
        
        // Use simple rectangle detection to find potential image regions
        let detectedRegions = detectSimpleImageRegions(in: renderedImage, pageBounds: pageBounds, pageIndex: pageIndex)
        imageRegions.append(contentsOf: detectedRegions)
        
        return imageRegions
    }
    
    // MARK: - Simple Image Region Detection
    private func detectSimpleImageRegions(in image: UIImage, pageBounds: CGRect, pageIndex: Int) -> [ImageRegion] {
        var imageRegions: [ImageRegion] = []
        
        guard let cgImage = image.cgImage else { return imageRegions }
        
        // Simple approach: divide the image into grid and check for non-white regions
        let gridSize = 4 // 4x4 grid
        let cellWidth = cgImage.width / gridSize
        let cellHeight = cgImage.height / gridSize
        
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let x = col * cellWidth
                let y = row * cellHeight
                let cellRect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
                
                // Check if this cell contains non-white content
                if hasSignificantContent(in: cgImage, rect: cellRect) {
                    // Convert to PDF coordinates
                    let pdfBoundingBox = CGRect(
                        x: CGFloat(x) / CGFloat(cgImage.width) * pageBounds.width,
                        y: (1 - CGFloat(y + cellHeight) / CGFloat(cgImage.height)) * pageBounds.height,
                        width: CGFloat(cellWidth) / CGFloat(cgImage.width) * pageBounds.width,
                        height: CGFloat(cellHeight) / CGFloat(cgImage.height) * pageBounds.height
                    )
                    
                    // Extract the region as an image
                    if let regionImage = extractRegion(from: image, boundingBox: CGRect(
                        x: CGFloat(x) / CGFloat(cgImage.width),
                        y: CGFloat(y) / CGFloat(cgImage.height),
                        width: CGFloat(cellWidth) / CGFloat(cgImage.width),
                        height: CGFloat(cellHeight) / CGFloat(cgImage.height)
                    )) {
                        let imageRegion = ImageRegion(
                            image: regionImage,
                            boundingBox: pdfBoundingBox,
                            pageIndex: pageIndex,
                            description: "Detected image region"
                        )
                        imageRegions.append(imageRegion)
                    }
                }
            }
        }
        
        return imageRegions
    }
    
    private func hasSignificantContent(in cgImage: CGImage, rect: CGRect) -> Bool {
        // Simple check: sample a few pixels and see if they're not white
        let dataProvider = cgImage.dataProvider
        guard let data = dataProvider?.data else { return false }
        
        let dataPointer = CFDataGetBytePtr(data)
        let dataLength = CFDataGetLength(data)
        
        guard dataPointer != nil && dataLength > 0 else { return false }
        
        let bytesPerPixel = 4
        let bytesPerRow = cgImage.bytesPerRow
        
        // Sample pixels in the rect
        let samplePoints = 10
        var nonWhitePixels = 0
        
        for _ in 0..<samplePoints {
            let sampleX = Int(rect.origin.x) + Int.random(in: 0..<Int(rect.width))
            let sampleY = Int(rect.origin.y) + Int.random(in: 0..<Int(rect.height))
            
            let offset = sampleY * bytesPerRow + sampleX * bytesPerPixel
            
            if offset + 3 < dataLength {
                let r = dataPointer![offset]
                let g = dataPointer![offset + 1]
                let b = dataPointer![offset + 2]
                
                // Check if pixel is not white (with some tolerance)
                if r < 240 || g < 240 || b < 240 {
                    nonWhitePixels += 1
                }
            }
        }
        
        // Return true if more than 30% of sampled pixels are not white
        return nonWhitePixels > samplePoints / 3
    }
    
    private func extractRegion(from image: UIImage, boundingBox: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        // Convert normalized coordinates to pixel coordinates
        let pixelRect = CGRect(
            x: boundingBox.origin.x * CGFloat(cgImage.width),
            y: (1 - boundingBox.origin.y - boundingBox.height) * CGFloat(cgImage.height),
            width: boundingBox.width * CGFloat(cgImage.width),
            height: boundingBox.height * CGFloat(cgImage.height)
        )
        
        // Crop the image
        guard let croppedCGImage = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: croppedCGImage)
    }
    
    // MARK: - Basic Image Description Generation
    private func generateBasicImageDescription(for image: UIImage) -> String {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var description = "Image with dimensions \(Int(size.width))x\(Int(size.height))"
        
        if aspectRatio > 1.5 {
            description += ", landscape orientation"
        } else if aspectRatio < 0.7 {
            description += ", portrait orientation"
        } else {
            description += ", square-like proportions"
        }
        
        return description
    }
    
    /// Create UIImage from PDF image data
    private func createImageFromPDFData(_ data: CFData, width: Int, height: Int) -> UIImage? {
        let dataLength = CFDataGetLength(data)
        let dataPointer = CFDataGetBytePtr(data)
        
        guard dataPointer != nil && dataLength > 0 else {
            return nil
        }
        
        // Create CGImage from data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        
        // Copy data to context
        let dataBytes = CFDataGetBytePtr(data)
        context.data?.copyMemory(from: dataBytes!, byteCount: dataLength)
        
        // Create image from context
        guard let cgImage = context.makeImage() else {
            return nil
        }
        
        let uiImage = UIImage(cgImage: cgImage)
        
        return uiImage
    }
    
    // Note: extractImagesFromContentStreams and extractImagesFromXObjects removed - were unimplemented placeholder methods
    
    /// Parse PDF content stream for REAL image positions
    private func parsePDFContentStreamReal(_ pageRef: CGPDFPage, xObjectDict: CGPDFDictionaryRef, pageBounds: CGRect) -> [String: CGRect] {
        var imagePositions: [String: CGRect] = [:]
        
        // Method 1: Use PDFKit's REAL annotation analysis for REAL positions
        let annotationPositions = getImagePositionsFromPDFKitAnnotations(pageRef, pageBounds: pageBounds)
        imagePositions = annotationPositions
        
        // Method 2: Use PDFKit's REAL content stream analysis (if available)
        if imagePositions.isEmpty {
            let contentStreamInfo = parseContentStreamForRealImageCommands(pageRef, xObjectDict: xObjectDict, pageBounds: pageBounds)
            imagePositions = contentStreamInfo
        }
        
        // Method 3: Use PDFKit's native PDFPage annotations (if we can get PDFPage)
        if imagePositions.isEmpty {
            let nativePositions = getImagePositionsFromPDFKitNative(pageRef, pageBounds: pageBounds)
            imagePositions = nativePositions
        }
        
        return imagePositions
    }
    
    /// Get image positions from PDFKit native API
    private func getImagePositionsFromPDFKitNative(_ pageRef: CGPDFPage, pageBounds: CGRect) -> [String: CGRect] {
        var imagePositions: [String: CGRect] = [:]
        
        // Get page bounds in PDF coordinates
        let pdfPageBounds = pageRef.getBoxRect(.mediaBox)
        
        // Get content stream for more accurate analysis
        guard let pageDictionary = pageRef.dictionary else {
            return imagePositions
        }
        
        // Look for XObject resources that are images
        var resources: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(pageDictionary, "Resources", &resources), let resources = resources {
            var xObjectDict: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(resources, "XObject", &xObjectDict), let xObjectDict = xObjectDict {
                
                // Create data structure for closure
                
                var xObjectData = XObjectData(
                    imagePositions: [:],
                    pageBounds: pageBounds,
                    pdfPageBounds: pdfPageBounds,
                    extractor: self
                )
                
                // Iterate through XObjects to find images
                CGPDFDictionaryApplyFunction(xObjectDict, imageXObjectCallbackGlobal, &xObjectData)
                
                imagePositions = xObjectData.imagePositions
            }
        }
        
        return imagePositions
    }
    
    /// Calculate image position from dimensions and page layout with better positioning
    internal func calculateImagePositionFromDimensions(width: Int, height: Int, pageBounds: CGRect, pdfPageBounds: CGRect) -> CGRect {
        // Calculate aspect ratio
        let aspectRatio = CGFloat(width) / CGFloat(height)
        
        // Use a more intelligent positioning based on image size
        let maxWidth = 0.6  // 60% of page width
        let maxHeight = 0.4 // 40% of page height
        
        // Scale to fit while maintaining aspect ratio
        let scaleX = maxWidth / aspectRatio
        let scaleY = maxHeight
        let scale = min(scaleX, scaleY, 1.0)
        
        let scaledWidth = maxWidth * scale
        let scaledHeight = maxHeight * scale
        
        // Position in the center of the page with some margin
        let x = (1.0 - scaledWidth) / 2.0
        let y = 0.1 + (0.8 - scaledHeight) / 2.0  // Add top margin
        
        print("📐 Image dimensions: \(width)x\(height), aspect ratio: \(aspectRatio)")
        print("📐 Calculated position: x=\(x), y=\(y), w=\(scaledWidth), h=\(scaledHeight)")
        
        return CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
    }
    
    /// Enhanced PDF content stream parsing for precise image positions
    private func parseContentStreamEnhanced(_ pageRef: CGPDFPage, xObjectDict: CGPDFDictionaryRef, pageBounds: CGRect) -> [String: CGRect] {
        var imagePositions: [String: CGRect] = [:]
        
        // Get the page dictionary
        guard let pageDictionary = pageRef.dictionary else {
            return imagePositions
        }
        
        // Get content stream
        var contentStream: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(pageDictionary, "Contents", &contentStream), let contentStream = contentStream {
            // Parse with enhanced method
            let enhancedPositions = parseContentStreamDataEnhanced(contentStream, xObjectDict: xObjectDict, pageBounds: pageBounds)
            imagePositions = enhancedPositions
        }
        
        return imagePositions
    }
    
    /// Enhanced content stream data parsing with better matrix handling
    private func parseContentStreamDataEnhanced(_ contentStream: CGPDFStreamRef, xObjectDict: CGPDFDictionaryRef, pageBounds: CGRect) -> [String: CGRect] {
        var imagePositions: [String: CGRect] = [:]
        
        // Get stream data
        var format: CGPDFDataFormat = .raw
        guard let data = CGPDFStreamCopyData(contentStream, &format) else {
            return imagePositions
        }
        
        let dataLength = CFDataGetLength(data)
        let dataPointer = CFDataGetBytePtr(data)
        
        guard dataPointer != nil && dataLength > 0 else {
            return imagePositions
        }
        
        // Convert to string for parsing
        let streamString = String(data: Data(bytes: dataPointer!, count: dataLength), encoding: .ascii) ?? ""
        
        // Enhanced parsing: look for complete transformation sequences
        let lines = streamString.components(separatedBy: .newlines)
        var currentMatrix: [CGFloat] = [1, 0, 0, 1, 0, 0] // Identity matrix
        var matrixStack: [[CGFloat]] = []
        var currentPixelWidth: CGFloat = 1.0
        var currentPixelHeight: CGFloat = 1.0
        
        print("🔍 Debug: Starting content stream parsing with \(lines.count) lines")
        print("🔍 Debug: First few lines of content stream:")
        for i in 0..<min(10, lines.count) {
            print("🔍 Debug: Line \(i): '\(lines[i])'")
        }
        
        for (lineIndex, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Output all non-empty lines to see what commands exist
            if !trimmedLine.isEmpty {
                // Handle matrix transformations - IMPROVED PARSING WITH CONCATENATION
                if trimmedLine.contains("cm") {
                    // Extract matrix values from "cm" command
                    let matrixString = trimmedLine.replacingOccurrences(of: "cm", with: "").trimmingCharacters(in: .whitespaces)
                    let matrixValues = matrixString.components(separatedBy: .whitespaces).compactMap { Double($0) }
                    
                    if matrixValues.count == 6 {
                        // Check if this is a pixel dimension matrix (third cm command for images)
                        // Pixel dimension matrices typically have: [width 0 0 height 0 0]
                        // where width and height are the actual pixel dimensions
                        let isPixelDimensionMatrix = matrixValues[1] == 0 && matrixValues[2] == 0 && 
                                                   matrixValues[4] == 0 && matrixValues[5] == 0 &&
                                                   matrixValues[0] > 100 && matrixValues[3] > 100  // Likely pixel dimensions
                        
                        if isPixelDimensionMatrix {
                            print("📐 Detected pixel dimension matrix: [\(matrixValues[0]), \(matrixValues[1]), \(matrixValues[2]), \(matrixValues[3]), \(matrixValues[4]), \(matrixValues[5])]")
                            print("📐 Storing pixel dimensions for later use")
                            
                            // Store pixel dimensions for later use in position calculation
                            currentPixelWidth = CGFloat(matrixValues[0])
                            currentPixelHeight = CGFloat(matrixValues[3])
                        } else {
                            // Create CGAffineTransform from the new matrix values
                            let newTransform = CGAffineTransform(
                                a: CGFloat(matrixValues[0]), b: CGFloat(matrixValues[1]),
                                c: CGFloat(matrixValues[2]), d: CGFloat(matrixValues[3]),
                                tx: CGFloat(matrixValues[4]), ty: CGFloat(matrixValues[5])
                            )
                            
                            // Create CGAffineTransform from current matrix
                            let currentTransform = CGAffineTransform(
                                a: currentMatrix[0], b: currentMatrix[1],
                                c: currentMatrix[2], d: currentMatrix[3],
                                tx: currentMatrix[4], ty: currentMatrix[5]
                            )
                            
                            // Concatenate the transforms (accumulate matrices)
                            let concatenatedTransform = currentTransform.concatenating(newTransform)
                            
                            // Update current matrix with concatenated values
                            currentMatrix = [
                                concatenatedTransform.a, concatenatedTransform.b,
                                concatenatedTransform.c, concatenatedTransform.d,
                                concatenatedTransform.tx, concatenatedTransform.ty
                            ]
                            
                            print("📐 New matrix: \(matrixValues)")
                            print("📐 Concatenated matrix: [\(currentMatrix[0]), \(currentMatrix[1]), \(currentMatrix[2]), \(currentMatrix[3]), \(currentMatrix[4]), \(currentMatrix[5])]")
                            print("📐 Matrix string: '\(matrixString)'")
                        }
                    } else {
                        print("⚠️ Warning: Invalid matrix format in line: '\(trimmedLine)'")
                        print("⚠️ Expected 6 values, got \(matrixValues.count)")
                    }
                }
                
                // Handle matrix stack operations
                if trimmedLine == "q" {
                    // Save current matrix
                    matrixStack.append(currentMatrix)
                } else if trimmedLine == "Q" {
                    // Restore matrix
                    if !matrixStack.isEmpty {
                        currentMatrix = matrixStack.removeLast()
                    }
                }
                
                // Handle image drawing commands - IMPROVED DETECTION
                if trimmedLine.contains("Do") {
                    // Extract XObject name (fix: handle '/Im2 Do' format)
                    let components = trimmedLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    print("🔍 Debug: Do command line: '\(trimmedLine)'")
                    print("🔍 Debug: Do command components: \(components)")
                    for (i, component) in components.enumerated() {
                        if component == "Do", i > 0 {
                            var xObjectName = components[i-1]
                            if xObjectName.hasPrefix("/") {
                                xObjectName = String(xObjectName.dropFirst())
                            }
                            print("🔍 Debug: Found Do command for XObject: '\(xObjectName)'")
                            if xObjectName.isEmpty {
                                print("🔍 Debug: Skipping empty XObject name")
                                continue
                            }
                            // Get image dimensions from XObject dictionary
                            var imageWidth: CGFloat = 1.0
                            var imageHeight: CGFloat = 1.0
                            var xObject: CGPDFObjectRef?
                            if CGPDFDictionaryGetObject(xObjectDict, xObjectName, &xObject), let xObject = xObject {
                                if CGPDFObjectGetType(xObject) == .stream {
                                    var stream: CGPDFStreamRef?
                                    if CGPDFObjectGetValue(xObject, .stream, &stream), let stream = stream {
                                        if let streamDict = CGPDFStreamGetDictionary(stream) {
                                            var width: CGPDFInteger = 0
                                            var height: CGPDFInteger = 0
                                            CGPDFDictionaryGetInteger(streamDict, "Width", &width)
                                            CGPDFDictionaryGetInteger(streamDict, "Height", &height)
                                            if width > 0 && height > 0 {
                                                imageWidth = CGFloat(width)
                                                imageHeight = CGFloat(height)
                                                print("📐 Found image dimensions for \(xObjectName): \(width)x\(height)")
                                            }
                                        }
                                    }
                                }
                            }
                            // Calculate precise position using current transformation matrix and actual dimensions
                            let position = calculatePreciseImagePositionWithDimensions(
                                matrix: currentMatrix,
                                imageWidth: imageWidth,
                                imageHeight: imageHeight,
                                pageBounds: pageBounds,
                                xObjectName: xObjectName
                            )
                            // Store the position with the correct key name
                            imagePositions[xObjectName] = position
                            print("🔍 Debug: Stored REAL position for '\(xObjectName)': \(position)")
                        }
                    }
                }
            }
        }
        
        print("🔍 Debug: Final imagePositions dictionary: \(imagePositions.keys)")
        return imagePositions
    }
    
    /// Calculate precise image position using transformation matrix with actual dimensions
    private func calculatePreciseImagePositionWithDimensions(matrix: [CGFloat], imageWidth: CGFloat, imageHeight: CGFloat, pageBounds: CGRect, xObjectName: String) -> CGRect {
        // For image XObjects, the transformation matrix [a b c d e f] typically represents:
        // - a, d: scaling factors for width and height
        // - e, f: translation (position) in PDF coordinates
        // - b, c: usually 0 for images (no rotation/skew)
        
        let a = matrix[0], b = matrix[1], c = matrix[2], d = matrix[3], e = matrix[4], f = matrix[5]
        
        // The matrix [a 0 0 d e f] with image dimensions (w, h) gives us:
        // - Position: (e, f)
        // - Size: (a*w, d*h)
        
        // Calculate the image bounds in PDF coordinates
        // currentMatrix.a = sx, currentMatrix.d = sy (scaling factors)
        // We need to multiply by the actual pixel dimensions to get the final size
        let pdfX = e  // X position in PDF coordinates
        let pdfY = f  // Y position in PDF coordinates
        let pdfWidth = abs(a) * imageWidth   // sx * pixel width
        let pdfHeight = abs(d) * imageHeight // sy * pixel height
        
        let pdfBounds = CGRect(
            x: pdfX,
            y: pdfY,
            width: pdfWidth,
            height: pdfHeight
        )
        
        // Convert PDF coordinates to normalized UI coordinates (0-1 range)
        let normalizedBounds = CGRect(
            x: pdfBounds.origin.x / pageBounds.width,
            y: pdfBounds.origin.y / pageBounds.height,
            width: pdfBounds.width / pageBounds.width,
            height: pdfBounds.height / pageBounds.height
        )
        
        // Convert Y coordinate (PDF uses bottom-up, UI uses top-down)
        let uiBounds = CGRect(
            x: normalizedBounds.origin.x,
            y: 1.0 - (normalizedBounds.origin.y + normalizedBounds.height),
            width: normalizedBounds.width,
            height: normalizedBounds.height
        )
        
        // Only clamp if the bounds are clearly out of range
        let clampedBounds: CGRect
        if uiBounds.origin.x < -0.1 || uiBounds.origin.y < -0.1 || 
           uiBounds.origin.x + uiBounds.width > 1.1 || uiBounds.origin.y + uiBounds.height > 1.1 {
            // Only clamp if significantly out of range
            clampedBounds = CGRect(
                x: max(0, min(1, uiBounds.origin.x)),
                y: max(0, min(1, uiBounds.origin.y)),
                width: max(0, min(1, uiBounds.width)),
                height: max(0, min(1, uiBounds.height))
            )
        } else {
            // Keep original bounds if they're reasonable
            clampedBounds = uiBounds
        }
        
        print("📐 Matrix: [\(a), \(b), \(c), \(d), \(e), \(f)]")
        print("📐 Image dimensions: \(imageWidth)x\(imageHeight)")
        print("📐 PDF bounds: \(pdfBounds)")
        print("📐 UI bounds: \(uiBounds)")
        print("📐 Clamped bounds: \(clampedBounds)")
        
        return clampedBounds
    }
    
}

// MARK: - Data Models
struct ClosureData {
    var imageRegions: [ImageRegion]
    let pageBounds: CGRect
    let pageIndex: Int
    let extractor: PDFContentExtractor
    let imagePositions: [String: CGRect]
}

struct XObjectData {
    var imagePositions: [String: CGRect]
    let pageBounds: CGRect
    let pdfPageBounds: CGRect
    let extractor: PDFContentExtractor
}

struct PDFContent {
    let textContent: [String]
    let textPositions: [[TextPosition]] // Text positions for each page
    let imageDescriptions: [String]
    let imageRegions: [ImageRegion]
    let pageCount: Int
    
    var hasText: Bool {
        return textContent.contains { !$0.isEmpty }
    }
    
    var hasImages: Bool {
        return !imageRegions.isEmpty
    }
    
    var totalImages: Int {
        return imageRegions.count
    }
}

struct TextPosition {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
}

struct ImageRegion {
    let image: UIImage
    let boundingBox: CGRect
    let pageIndex: Int
    let description: String
}

// MARK: - Errors
enum PDFExtractionError: Error, LocalizedError {
    case invalidPDF(String)
    case extractionFailed(String)
    case unsupportedFormat(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidPDF(let message):
            return "Invalid PDF: \(message)"
        case .extractionFailed(let message):
            return "Extraction Failed: \(message)"
        case .unsupportedFormat(let message):
            return "Unsupported Format: \(message)"
        }
    }
} 