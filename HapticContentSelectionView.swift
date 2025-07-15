import UIKit
import PDFKit

// MARK: - Delegate Protocol
protocol HapticContentSelectionDelegate: AnyObject {
    func didSelectContent(_ content: String, in rect: CGRect, contentType: ContentType)
}

class HapticContentSelectionView: UIView {
    
    // MARK: - Properties
    weak var delegate: HapticContentSelectionDelegate?
    
    private var selectionOverlays: [UIView] = []
    private var isSelecting = false
    private var selectionStartPoint: CGPoint = .zero
    private var currentSelectionView: UIView?
    private var currentContentType: ContentType = .text
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupView() {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        
        // Add long press gesture recognizer
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        addGestureRecognizer(longPressGesture)
        
        // Add pan gesture for selection extension
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)
        
        print("📱 HapticContentSelectionView initialized")
    }
    
    // MARK: - Public Methods
    
    /// Set the current content type
    func setContentType(_ contentType: ContentType) {
        currentContentType = contentType
        print("📱 Content selection view set to: \(contentType.displayName)")
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: self)
        
        switch gesture.state {
        case .began:
            startSelection(at: location)
        case .changed:
            updateSelection(to: location)
        case .ended, .cancelled:
            endSelection(at: location)
        default:
            break
        }
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isSelecting else { return }
        
        let location = gesture.location(in: self)
        
        switch gesture.state {
        case .changed:
            updateSelection(to: location)
        case .ended, .cancelled:
            endSelection(at: location)
        default:
            break
        }
    }
    
    // MARK: - Selection Methods
    
    private func startSelection(at point: CGPoint) {
        isSelecting = true
        selectionStartPoint = point
        
        // Create selection overlay
        currentSelectionView = createSelectionOverlay(from: point, to: point)
        if let overlay = currentSelectionView {
            addSubview(overlay)
        }
        
        print("🔍 Started \(currentContentType.displayName) selection at: \(point)")
    }
    
    private func updateSelection(to point: CGPoint) {
        guard isSelecting, let selectionView = currentSelectionView else { return }
        
        // Update selection rectangle
        let rect = CGRect(
            x: min(selectionStartPoint.x, point.x),
            y: min(selectionStartPoint.y, point.y),
            width: abs(point.x - selectionStartPoint.x),
            height: abs(point.y - selectionStartPoint.y)
        )
        
        selectionView.frame = rect
    }
    
    private func endSelection(at point: CGPoint) {
        guard isSelecting, let selectionView = currentSelectionView else { return }
        
        isSelecting = false
        
        let finalRect = selectionView.frame
        
        // Only process selection if it has meaningful size
        let minSize = getMinimumSelectionSize()
        if finalRect.width > minSize.width && finalRect.height > minSize.height {
            // Extract content based on content type
            let extractedContent = extractContentFromSelection(rect: finalRect, contentType: currentContentType)
            
            if !extractedContent.isEmpty {
                // Create permanent selection overlay
                let permanentOverlay = createPermanentSelectionOverlay(rect: finalRect, contentType: currentContentType)
                addSubview(permanentOverlay)
                selectionOverlays.append(permanentOverlay)
                
                // Notify delegate
                delegate?.didSelectContent(extractedContent, in: finalRect, contentType: currentContentType)
                
                print("✅ \(currentContentType.displayName) selection completed: \(extractedContent.prefix(50))...")
            }
        }
        
        // Remove temporary selection view
        selectionView.removeFromSuperview()
        currentSelectionView = nil
    }
    
    // MARK: - Visual Elements
    
    private func createSelectionOverlay(from startPoint: CGPoint, to endPoint: CGPoint) -> UIView {
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
        
        let overlay = UIView(frame: rect)
        overlay.backgroundColor = getSelectionColor(for: currentContentType).withAlphaComponent(0.3)
        overlay.layer.borderColor = getSelectionColor(for: currentContentType).cgColor
        overlay.layer.borderWidth = 2.0
        overlay.layer.cornerRadius = 4.0
        overlay.isUserInteractionEnabled = false
        
        return overlay
    }
    
    private func createPermanentSelectionOverlay(rect: CGRect, contentType: ContentType) -> UIView {
        let overlay = UIView(frame: rect)
        overlay.backgroundColor = getSelectionColor(for: contentType).withAlphaComponent(0.2)
        overlay.layer.borderColor = getSelectionColor(for: contentType).cgColor
        overlay.layer.borderWidth = 1.5
        overlay.layer.cornerRadius = 4.0
        overlay.isUserInteractionEnabled = false
        
        // Add content type indicator
        let indicator = UILabel(frame: CGRect(x: 5, y: 2, width: 30, height: 16))
        indicator.text = contentType.icon
        indicator.font = .systemFont(ofSize: 12)
        overlay.addSubview(indicator)
        
        // Add selection index
        let indexLabel = UILabel(frame: CGRect(x: rect.width - 25, y: 2, width: 20, height: 16))
        indexLabel.text = "\(selectionOverlays.count + 1)"
        indexLabel.font = .systemFont(ofSize: 10, weight: .bold)
        indexLabel.textColor = getSelectionColor(for: contentType)
        indexLabel.textAlignment = .center
        overlay.addSubview(indexLabel)
        
        return overlay
    }
    
    // MARK: - Content Extraction
    
    private func extractContentFromSelection(rect: CGRect, contentType: ContentType) -> String {
        switch contentType {
        case .text:
            return extractTextContent(from: rect)
        case .image:
            return extractImageContent(from: rect)
        case .gif:
            return extractGIFContent(from: rect)
        }
    }
    
    private func extractTextContent(from rect: CGRect) -> String {
        // In a real implementation, this would extract text from the PDF at the given coordinates
        // For now, return simulated text based on selection area
        
        let area = rect.width * rect.height
        
        if area < 1000 {
            return "Brief text content"
        } else if area < 5000 {
            return "This is a sample text that represents what would be extracted from the PDF document in this selected area. It contains meaningful content for emotion analysis."
        } else {
            return "This is a longer sample text that would represent a larger selection from the PDF document. It demonstrates how the emotion analysis would work with more substantial text content that users might select for haptic feedback interaction. The system can analyze various emotions and match them to appropriate haptic patterns from the comprehensive library."
        }
    }
    
    private func extractImageContent(from rect: CGRect) -> String {
        // For images, we return a description that could be used for analysis
        // In a real implementation, this might use image recognition or manual tagging
        
        let area = rect.width * rect.height
        
        if area < 2000 {
            return "Small image region"
        } else if area < 8000 {
            return "Medium image area with visual content"
        } else {
            return "Large image section containing complex visual elements"
        }
    }
    
    private func extractGIFContent(from rect: CGRect) -> String {
        return "Animated GIF content with motion elements" // Placeholder
    }
    
    // MARK: - Helper Methods
    
    private func getSelectionColor(for contentType: ContentType) -> UIColor {
        switch contentType {
        case .text:
            return .systemBlue
        case .image:
            return .systemGreen
        case .gif:
            return .systemOrange
        }
    }
    
    private func getMinimumSelectionSize() -> CGSize {
        switch currentContentType {
        case .text:
            return CGSize(width: 20, height: 10)
        case .image:
            return CGSize(width: 30, height: 30)
        case .gif:
            return CGSize(width: 40, height: 40)
        }
    }
    
    // MARK: - Public Interface
    
    /// Clear all content selections
    func clearSelections() {
        selectionOverlays.forEach { $0.removeFromSuperview() }
        selectionOverlays.removeAll()
        
        currentSelectionView?.removeFromSuperview()
        currentSelectionView = nil
        isSelecting = false
        
        print("🗑️ Cleared all \(currentContentType.displayName) selections")
    }
    
    /// Get number of active selections
    func getSelectionCount() -> Int {
        return selectionOverlays.count
    }
    
    /// Highlight specific area (for programmatic selection)
    func highlightArea(rect: CGRect, contentType: ContentType, emotion: EmotionType? = nil, scene: SceneType? = nil) {
        // Convert PDF coordinates to view coordinates
        let viewRect = convertPDFCoordinatesToViewCoordinates(rect)
        
        let overlay = UIView(frame: viewRect)
        
        // Use unified style for all areas (same as manual selection)
        let highlightColor = getSelectionColor(for: contentType)
        
        overlay.backgroundColor = highlightColor.withAlphaComponent(0.3)
        overlay.layer.borderColor = highlightColor.cgColor
        overlay.layer.borderWidth = 2.0
        overlay.layer.cornerRadius = 4.0
        overlay.isUserInteractionEnabled = false
        
        // Add content type icon
        let iconLabel = UILabel(frame: CGRect(x: 5, y: 2, width: 20, height: 16))
        iconLabel.text = contentType.icon
        iconLabel.font = .systemFont(ofSize: 12)
        overlay.addSubview(iconLabel)
        
        // Add emotion or scene label if available
        if let emotion = emotion {
            let emotionLabel = UILabel(frame: CGRect(x: 25, y: 2, width: viewRect.width - 30, height: 16))
            emotionLabel.text = emotion.capitalized
            emotionLabel.font = .systemFont(ofSize: 10, weight: .medium)
            emotionLabel.textColor = highlightColor
            overlay.addSubview(emotionLabel)
        } else if let scene = scene {
            let sceneLabel = UILabel(frame: CGRect(x: 25, y: 2, width: viewRect.width - 30, height: 16))
            sceneLabel.text = scene.displayName
            sceneLabel.font = .systemFont(ofSize: 10, weight: .medium)
            sceneLabel.textColor = highlightColor
            overlay.addSubview(sceneLabel)
        }
        
        addSubview(overlay)
        selectionOverlays.append(overlay)
    }
    
    /// Get selections by content type
    func getSelections(for contentType: ContentType) -> [UIView] {
        // This is a simplified implementation
        // In a real app, you'd track content type per selection
        return selectionOverlays
    }
    
    /// Remove specific selection
    func removeSelection(at index: Int) {
        guard index < selectionOverlays.count else { return }
        
        let overlay = selectionOverlays[index]
        overlay.removeFromSuperview()
        selectionOverlays.remove(at: index)
        
        print("➖ Removed selection at index \(index)")
    }
    
    /// Show emotion regions from PDF analysis
    func showEmotionRegions(_ segments: [ContentSegment]) {
        // Clear existing selections first
        clearSelections()
        
        // Create emotion region overlays
        for (index, segment) in segments.enumerated() {
            print("🎯 Processing segment \(index + 1): \(segment.contentType.displayName)")
            print("📐 Original PDF rect: \(segment.rect)")
            
            // Convert PDF coordinates to view coordinates
            let viewRect = convertPDFCoordinatesToViewCoordinates(segment.rect)
            print("📐 Converted view rect: \(viewRect)")
            
            let overlay = createEmotionRegionOverlay(
                rect: viewRect,
                contentType: segment.contentType,
                emotion: segment.emotion,
                index: index + 1,
                metadata: segment.metadata
            )
            addSubview(overlay)
            selectionOverlays.append(overlay)
            
            print("✅ Added overlay for segment \(index + 1) at \(viewRect)")
        }
        
        print("🎯 Displayed \(segments.count) emotion regions")
    }
    
    /// Show text regions with precise highlighting
    func showTextRegions(_ textPositions: [TextPosition]) {
        // Clear existing selections first
        clearSelections()
        
        // Limit the number of text regions to avoid performance issues
        let maxTextRegions = 10
        let limitedTextPositions = Array(textPositions.prefix(maxTextRegions))
        
        if textPositions.count > maxTextRegions {
            print("⚠️ Limiting text regions from \(textPositions.count) to \(maxTextRegions) for performance")
        }
        
        print("📝 Creating \(limitedTextPositions.count) precise text region overlays...")
        
        // Create precise text region overlays
        for (index, textPosition) in limitedTextPositions.enumerated() {
            // Convert PDF coordinates to view coordinates
            let viewRect = convertPDFCoordinatesToViewCoordinates(textPosition.boundingBox)
            
            // Skip if the rect is too small or invalid
            if viewRect.width < 5 || viewRect.height < 3 {
                print("⚠️ Skipping text region \(index + 1) - too small: \(viewRect)")
                continue
            }
            
            // Use precise bounds without expansion for accurate highlighting
            let overlay = createPreciseTextRegionOverlay(
                rect: viewRect,
                text: textPosition.text,
                confidence: textPosition.confidence,
                index: index + 1
            )
            addSubview(overlay)
            selectionOverlays.append(overlay)
            
            print("✅ Created precise text region overlay \(index + 1): \(viewRect)")
        }
        
        print("📝 Displayed \(selectionOverlays.count) precise text regions")
    }
    
    /// Expand text region with line spacing for better visibility
    private func expandTextRegionWithSpacing(_ rect: CGRect) -> CGRect {
        let spacingMultiplier: CGFloat = 1.2  // 20% extra spacing
        let minSpacing: CGFloat = 4.0  // Minimum 4 points spacing
        let maxExpansion: CGFloat = 50.0  // Maximum expansion to avoid huge overlays
        
        let expandedWidth = rect.width * spacingMultiplier
        let expandedHeight = rect.height * spacingMultiplier
        
        let x = rect.origin.x - (expandedWidth - rect.width) / 2
        let y = rect.origin.y - (expandedHeight - rect.height) / 2
        
        let finalWidth = min(expandedWidth, rect.width + maxExpansion)
        let finalHeight = max(expandedHeight, rect.height + minSpacing)
        
        // Ensure the expanded rect doesn't go outside view bounds
        let viewBounds = bounds
        let constrainedX = max(0, min(x, viewBounds.width - finalWidth))
        let constrainedY = max(0, min(y, viewBounds.height - finalHeight))
        
        return CGRect(
            x: constrainedX,
            y: constrainedY,
            width: finalWidth,
            height: finalHeight
        )
    }
    
    /// Create text region overlay with improved styling
    private func createTextRegionOverlay(
        rect: CGRect,
        text: String,
        confidence: Float,
        index: Int
    ) -> UIView {
        let overlay = UIView(frame: rect)
        
        // Use blue color for text regions
        let textColor = UIColor.systemBlue
        
        // Semi-transparent background with border
        overlay.backgroundColor = textColor.withAlphaComponent(0.15)
        overlay.layer.borderColor = textColor.cgColor
        overlay.layer.borderWidth = 2.0
        overlay.layer.cornerRadius = 6.0
        overlay.isUserInteractionEnabled = false
        
        // Add shadow for better visibility
        overlay.layer.shadowColor = textColor.cgColor
        overlay.layer.shadowOffset = CGSize(width: 0, height: 2)
        overlay.layer.shadowOpacity = 0.3
        overlay.layer.shadowRadius = 3.0
        
        // Ensure minimum size for labels
        let minWidth: CGFloat = 60
        let minHeight: CGFloat = 30
        
        if rect.width < minWidth || rect.height < minHeight {
            print("⚠️ Text region too small for labels: \(rect)")
            return overlay
        }
        
        // Add text icon
        let iconLabel = UILabel(frame: CGRect(x: 6, y: 4, width: 20, height: 20))
        iconLabel.text = "📝"
        iconLabel.font = .systemFont(ofSize: 14)
        iconLabel.textAlignment = .center
        overlay.addSubview(iconLabel)
        
        // Add text preview (truncated) - only if there's enough space
        if rect.width > 80 {
            let previewText = text.prefix(30) + (text.count > 30 ? "..." : "")
            let textLabel = UILabel(frame: CGRect(x: 30, y: 4, width: rect.width - 60, height: 20))
            textLabel.text = String(previewText)
            textLabel.font = .systemFont(ofSize: 11, weight: .medium)
            textLabel.textColor = textColor
            textLabel.adjustsFontSizeToFitWidth = true
            textLabel.minimumScaleFactor = 0.8
            overlay.addSubview(textLabel)
        }
        
        // Add confidence indicator - only if there's enough space
        if rect.height > 40 {
            let confidenceLabel = UILabel(frame: CGRect(x: 6, y: rect.height - 20, width: rect.width - 12, height: 16))
            confidenceLabel.text = String(format: "Confidence: %.1f%%", confidence * 100)
            confidenceLabel.font = .systemFont(ofSize: 9, weight: .medium)
            confidenceLabel.textColor = textColor
            confidenceLabel.textAlignment = .right
            confidenceLabel.backgroundColor = textColor.withAlphaComponent(0.1)
            confidenceLabel.layer.cornerRadius = 6
            confidenceLabel.layer.masksToBounds = true
            overlay.addSubview(confidenceLabel)
        }
        
        // Add index label
        let indexLabel = UILabel(frame: CGRect(x: rect.width - 24, y: 4, width: 18, height: 18))
        indexLabel.text = "\(index)"
        indexLabel.font = .systemFont(ofSize: 10, weight: .bold)
        indexLabel.textColor = textColor
        indexLabel.textAlignment = .center
        indexLabel.backgroundColor = textColor.withAlphaComponent(0.2)
        indexLabel.layer.cornerRadius = 9
        indexLabel.layer.masksToBounds = true
        overlay.addSubview(indexLabel)
        
        return overlay
    }
    
    /// Create precise text region overlay with minimal styling for accurate highlighting
    private func createPreciseTextRegionOverlay(
        rect: CGRect,
        text: String,
        confidence: Float,
        index: Int
    ) -> UIView {
        let overlay = UIView(frame: rect)
        
        // Use blue color for text regions
        let textColor = UIColor.systemBlue
        
        // Very light background with thin border for precise highlighting
        overlay.backgroundColor = textColor.withAlphaComponent(0.1)
        overlay.layer.borderColor = textColor.cgColor
        overlay.layer.borderWidth = 1.0
        overlay.layer.cornerRadius = 2.0
        overlay.isUserInteractionEnabled = false
        
        // Add subtle shadow for visibility
        overlay.layer.shadowColor = textColor.cgColor
        overlay.layer.shadowOffset = CGSize(width: 0, height: 1)
        overlay.layer.shadowOpacity = 0.2
        overlay.layer.shadowRadius = 1.0
        
        // Only add labels if there's enough space
        let minWidth: CGFloat = 40
        let minHeight: CGFloat = 20
        
        if rect.width >= minWidth && rect.height >= minHeight {
            // Add small index label
            let indexLabel = UILabel(frame: CGRect(x: rect.width - 16, y: 2, width: 14, height: 14))
            indexLabel.text = "\(index)"
            indexLabel.font = .systemFont(ofSize: 8, weight: .bold)
            indexLabel.textColor = textColor
            indexLabel.textAlignment = .center
            indexLabel.backgroundColor = textColor.withAlphaComponent(0.3)
            indexLabel.layer.cornerRadius = 7
            indexLabel.layer.masksToBounds = true
            overlay.addSubview(indexLabel)
            
            // Add small text preview if there's enough space
            if rect.width > 60 {
                let previewText = text.prefix(15) + (text.count > 15 ? "..." : "")
                let textLabel = UILabel(frame: CGRect(x: 4, y: 2, width: rect.width - 20, height: 14))
                textLabel.text = String(previewText)
                textLabel.font = .systemFont(ofSize: 8, weight: .medium)
                textLabel.textColor = textColor
                textLabel.adjustsFontSizeToFitWidth = true
                textLabel.minimumScaleFactor = 0.7
                overlay.addSubview(textLabel)
            }
        }
        
        return overlay
    }
    
    /// Update selections with new content segments (for test mode and general use)
    func updateSelections(_ segments: [ContentSegment]) {
        // Clear existing selections first
        clearSelections()
        
        // Create selection overlays for each segment
        for (index, segment) in segments.enumerated() {
            // Convert PDF coordinates to view coordinates
            let viewRect = convertPDFCoordinatesToViewCoordinates(segment.rect)
            let overlay = createSelectionOverlayForSegment(
                rect: viewRect,
                contentType: segment.contentType,
                emotion: segment.emotion,
                index: index + 1,
                metadata: segment.metadata
            )
            addSubview(overlay)
            selectionOverlays.append(overlay)
        }
        
        print("🔄 Updated selections with \(segments.count) segments")
    }
    
    /// Create selection overlay for content segments
    private func createSelectionOverlayForSegment(
        rect: CGRect,
        contentType: ContentType,
        emotion: EmotionType?,
        index: Int,
        metadata: [String: Any]
    ) -> UIView {
        let overlay = UIView(frame: rect)
        
        // Use unified style for all selections
        let regionColor = getSelectionColor(for: contentType)
        
        // Set background and border
        overlay.backgroundColor = regionColor.withAlphaComponent(0.2)
        overlay.layer.borderColor = regionColor.cgColor
        overlay.layer.borderWidth = 2.0
        overlay.layer.cornerRadius = 6.0
        overlay.isUserInteractionEnabled = false
        
        // Add content type icon
        let iconLabel = UILabel(frame: CGRect(x: 5, y: 3, width: 20, height: 16))
        iconLabel.text = contentType.icon
        iconLabel.font = .systemFont(ofSize: 12, weight: .bold)
        iconLabel.textColor = regionColor
        iconLabel.textAlignment = .center
        overlay.addSubview(iconLabel)
        
        // Add emotion label if available
        if let emotion = emotion {
            let emotionLabel = UILabel(frame: CGRect(x: 30, y: 3, width: rect.width - 35, height: 16))
            emotionLabel.text = emotion.capitalized
            emotionLabel.font = .systemFont(ofSize: 11, weight: .medium)
            emotionLabel.textColor = regionColor
            emotionLabel.adjustsFontSizeToFitWidth = true
            emotionLabel.minimumScaleFactor = 0.8
            overlay.addSubview(emotionLabel)
        }
        
        // Add index label
        let indexLabel = UILabel(frame: CGRect(x: rect.width - 25, y: 3, width: 20, height: 16))
        indexLabel.text = "\(index)"
        indexLabel.font = .systemFont(ofSize: 10, weight: .bold)
        indexLabel.textColor = regionColor
        indexLabel.textAlignment = .center
        indexLabel.backgroundColor = regionColor.withAlphaComponent(0.2)
        indexLabel.layer.cornerRadius = 8
        indexLabel.layer.masksToBounds = true
        overlay.addSubview(indexLabel)
        
        return overlay
    }
    
    /// Convert PDF coordinates to view coordinates using PDFKit's proper conversion
    private func convertPDFCoordinatesToViewCoordinates(_ pdfRect: CGRect) -> CGRect {
        // Try to get the PDFView from the parent view hierarchy
        guard let pdfView = findPDFView() else {
            print("⚠️ Could not find PDFView, falling back to manual conversion")
            return fallbackCoordinateConversion(pdfRect)
        }
        
        // Try to get the current page
        guard let currentPage = pdfView.currentPage else {
            print("⚠️ Could not get current page, falling back to manual conversion")
            return fallbackCoordinateConversion(pdfRect)
        }
        
        print("🔄 Converting PDF coordinates using PDFKit...")
        print("📐 Input PDF rect (0-1 range): \(pdfRect)")
        print("📄 Current page: \(currentPage.pageRef?.pageNumber ?? 0)")
        
        // Get the page bounds in PDF coordinates
        let pageBounds = currentPage.bounds(for: .mediaBox)
        print("📏 Page bounds: \(pageBounds)")
        
        // Convert normalized coordinates (0-1) to PDF page coordinates
        // Note: PDF uses bottom-up Y axis, but we keep the normalized coordinates as-is
        // since PDFKit's convert method will handle the Y-axis flip automatically
        let pdfPageRect = CGRect(
            x: pdfRect.origin.x * pageBounds.width,
            y: pdfRect.origin.y * pageBounds.height,
            width: pdfRect.width * pageBounds.width,
            height: pdfRect.height * pageBounds.height
        )
        
        print("📐 PDF page coordinates: \(pdfPageRect)")
        
        // Use PDFKit's built-in coordinate conversion
        // This handles all scaling, margins, and scroll offsets automatically
        let viewRect = pdfView.convert(pdfPageRect, from: currentPage)
        
        print("📐 PDFKit converted rect: \(viewRect)")
        
        // Ensure the rect is within the view bounds
        let finalRect = ensureRectInBounds(viewRect)
        
        print("📐 Final converted rect: \(finalRect)")
        
        return finalRect
    }
    
    /// Fallback coordinate conversion when PDFView is not available
    private func fallbackCoordinateConversion(_ pdfRect: CGRect) -> CGRect {
        let viewSize = bounds.size
        
        guard viewSize.width > 0 && viewSize.height > 0 else {
            print("⚠️ Invalid view size: \(viewSize)")
            return pdfRect
        }
        
        print("🔄 Using fallback coordinate conversion...")
        
        // Simple conversion (the old method)
        let x = pdfRect.origin.x * viewSize.width
        let y = (1.0 - pdfRect.origin.y - pdfRect.height) * viewSize.height
        let width = pdfRect.width * viewSize.width
        let height = pdfRect.height * viewSize.height
        
        let convertedRect = CGRect(x: x, y: y, width: width, height: height)
        let finalRect = ensureRectInBounds(convertedRect)
        
        print("📐 Fallback converted rect: \(finalRect)")
        
        return finalRect
    }
    
    /// Find PDFView in the view hierarchy
    private func findPDFView() -> PDFView? {
        var currentView: UIView? = self
        
        while currentView != nil {
            if let pdfView = currentView as? PDFView {
                return pdfView
            }
            currentView = currentView?.superview
        }
        
        return nil
    }
    
    /// Ensure rect is within view bounds
    private func ensureRectInBounds(_ rect: CGRect) -> CGRect {
        let viewBounds = bounds
        
        let finalX = max(0, min(rect.origin.x, viewBounds.width))
        let finalY = max(0, min(rect.origin.y, viewBounds.height))
        let finalWidth = min(rect.width, viewBounds.width - finalX)
        let finalHeight = min(rect.height, viewBounds.height - finalY)
        
        return CGRect(x: finalX, y: finalY, width: finalWidth, height: finalHeight)
    }
    
    /// Create emotion region overlay
    private func createEmotionRegionOverlay(
        rect: CGRect,
        contentType: ContentType,
        emotion: EmotionType?,
        index: Int,
        metadata: [String: Any]
    ) -> UIView {
        let overlay = UIView(frame: rect)
        
        // Use unified style for all emotion regions (same as manual selection)
        let regionColor = getSelectionColor(for: contentType)
        
        // For image content type, display the actual image
        if contentType == .image, let image = metadata["image"] as? UIImage {
            // Create image view with the actual image
            let imageView = UIImageView(frame: overlay.bounds)
            imageView.image = image
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 8.0
            overlay.addSubview(imageView)
            
            // Add border and shadow for better visibility
            imageView.layer.borderColor = regionColor.cgColor
            imageView.layer.borderWidth = 2.0
            imageView.layer.shadowColor = regionColor.cgColor
            imageView.layer.shadowOffset = CGSize(width: 0, height: 2)
            imageView.layer.shadowOpacity = 0.3
            imageView.layer.shadowRadius = 4.0
        } else {
            // For non-image content, use the original overlay style
            overlay.backgroundColor = regionColor.withAlphaComponent(0.15)
            overlay.layer.borderColor = regionColor.cgColor
            overlay.layer.borderWidth = 3.0
            overlay.layer.cornerRadius = 8.0
            overlay.layer.shadowColor = regionColor.cgColor
            overlay.layer.shadowOffset = CGSize(width: 0, height: 2)
            overlay.layer.shadowOpacity = 0.3
            overlay.layer.shadowRadius = 4.0
            
            // Add content type icon
            let iconLabel = UILabel(frame: CGRect(x: 8, y: 6, width: 24, height: 20))
            iconLabel.text = contentType.icon
            iconLabel.font = .systemFont(ofSize: 14, weight: .bold)
            iconLabel.textColor = regionColor
            iconLabel.textAlignment = .center
            overlay.addSubview(iconLabel)
        }
        
        overlay.isUserInteractionEnabled = false
        
        // Add emotion label (now just a string, not enum) - Improved layout
        if let emotion = emotion {
            let emotionLabel = UILabel(frame: CGRect(x: 8, y: rect.height - 24, width: rect.width - 16, height: 20))
            emotionLabel.text = emotion.capitalized
            emotionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            emotionLabel.textColor = regionColor
            emotionLabel.adjustsFontSizeToFitWidth = true
            emotionLabel.minimumScaleFactor = 0.8
            emotionLabel.textAlignment = .left
            emotionLabel.backgroundColor = regionColor.withAlphaComponent(0.8)
            emotionLabel.layer.cornerRadius = 4
            emotionLabel.layer.masksToBounds = true
            overlay.addSubview(emotionLabel)
        }
        
        // Add region index - Adjust position
        let indexLabel = UILabel(frame: CGRect(x: rect.width - 28, y: 6, width: 20, height: 20))
        indexLabel.text = "\(index)"
        indexLabel.font = .systemFont(ofSize: 12, weight: .bold)
        indexLabel.textColor = regionColor
        indexLabel.textAlignment = .center
        indexLabel.backgroundColor = regionColor.withAlphaComponent(0.2)
        indexLabel.layer.cornerRadius = 10
        indexLabel.layer.masksToBounds = true
        overlay.addSubview(indexLabel)
        
        // Add confidence indicator if available - Adjust position
        if let confidence = metadata["confidence"] as? Float {
            let confidenceLabel = UILabel(frame: CGRect(x: 8, y: rect.height - 44, width: rect.width - 16, height: 16))
            confidenceLabel.text = String(format: "Confidence: %.1f%%", confidence * 100)
            confidenceLabel.font = .systemFont(ofSize: 10, weight: .medium)
            confidenceLabel.textColor = regionColor
            confidenceLabel.textAlignment = .right
            confidenceLabel.backgroundColor = regionColor.withAlphaComponent(0.1)
            confidenceLabel.layer.cornerRadius = 8
            confidenceLabel.layer.masksToBounds = true
            overlay.addSubview(confidenceLabel)
        }
        
        // Add matching method indicator
        if let matchMethod = metadata["match_method"] as? String {
            let methodLabel = UILabel(frame: CGRect(x: 8, y: rect.height - 60, width: rect.width - 16, height: 16))
            let methodText = matchMethod == "gpt_embedding" ? "🤖 GPT matching" : "🔄 Alternate matching"
            methodLabel.text = methodText
            methodLabel.font = .systemFont(ofSize: 10, weight: .medium)
            methodLabel.textColor = regionColor
            methodLabel.textAlignment = .left
            methodLabel.backgroundColor = regionColor.withAlphaComponent(0.1)
            methodLabel.layer.cornerRadius = 8
            methodLabel.layer.masksToBounds = true
            overlay.addSubview(methodLabel)
        }
        
        return overlay
    }
    
    /// Test coordinate conversion with sample data
    func testCoordinateConversion() {
        print("🧪 Testing coordinate conversion...")
        
        // Simulated PDF coordinates (0-1 range)
        let testPDFRect = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        print("📄 Test PDF coordinates: \(testPDFRect)")
        
        // Simulated view size
        let testViewSize = CGSize(width: 800, height: 600)
        print("📏 Test view size: \(testViewSize)")
        
        // Manual calculation of expected conversion result
        let expectedX = testPDFRect.origin.x * testViewSize.width // 0.1 * 800 = 80
        let expectedY = (1.0 - testPDFRect.origin.y - testPDFRect.height) * testViewSize.height // (1-0.2-0.4) * 600 = 240
        let expectedWidth = testPDFRect.width * testViewSize.width // 0.3 * 800 = 240
        let expectedHeight = testPDFRect.height * testViewSize.height // 0.4 * 600 = 240
        
        let expectedRect = CGRect(x: expectedX, y: expectedY, width: expectedWidth, height: expectedHeight)
        print("✅ Expected view coordinates: \(expectedRect)")
        
        // Verify conversion logic
        let convertedRect = convertPDFCoordinatesToViewCoordinates(testPDFRect)
        print("🔄 Actual conversion result: \(convertedRect)")
        
        if abs(convertedRect.origin.x - expectedRect.origin.x) < 1 &&
           abs(convertedRect.origin.y - expectedRect.origin.y) < 1 &&
           abs(convertedRect.width - expectedRect.width) < 1 &&
           abs(convertedRect.height - expectedRect.height) < 1 {
            print("✅ Coordinate conversion test passed!")
        } else {
            print("❌ Coordinate conversion test failed!")
        }
    }
} 