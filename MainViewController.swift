import UIKit
import PDFKit
import CoreBluetooth
import NaturalLanguage

class MainViewController: UIViewController {
    
    // MARK: - UI Components
    private var contentView: UIView!
    private var pdfView: PDFView!
    private var imageView: UIImageView!
    private var gifView: UIView! // Placeholder for future GIF support
    private var contentSelectionView: HapticContentSelectionView!
    private var controlPanel: UIView!
    private var contentTypeSegment: UISegmentedControl!
    
    // MARK: - Page Navigation Controls
    private var pageControl: UIPageControl!
    private var prevButton: UIButton!
    private var nextButton: UIButton!
    
    // MARK: - Core Components
    private var bleController: BLEController!
    private var hapticLibrary: HapticLibrary!
    
    // MARK: - Data
    private var selectedContentSegments: [ContentSegment] = []
    private var currentContentType: ContentType = .text
    private var currentlyPlayingPattern: HapticPattern?
    private var hapticWorkItems: [DispatchWorkItem] = [] // Track async haptic tasks
    
    // MARK: - PDF Analysis
    private var selectedAnalysisMode: PDFAnalysisMode = .textOnly
    private var selectedGranularity: TextGranularityLevel = .sentence
    private var allEmotionSegments: [ContentSegment] = [] // Store all emotion segments
    private var allTextPositions: [[TextPosition]] = [] // Store all text positions
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Haptic Content Reader"
        view.backgroundColor = .systemBackground
        
        // Setup components first
        setupComponents()
        
        // Content View Container
        contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .white
        view.addSubview(contentView)
        
        // Content Type Selector
        setupContentTypeSelector()
        
        // PDF View (default visible)
        setupPDFView()
        
        // Image View (hidden initially)
        setupImageView()
        
        // GIF View (hidden initially)
        setupGIFView()
        
        // Content Selection Overlay
        contentSelectionView = HapticContentSelectionView()
        contentSelectionView.translatesAutoresizingMaskIntoConstraints = false
        contentSelectionView.backgroundColor = .clear
        contentSelectionView.delegate = self
        view.addSubview(contentSelectionView)
        
        // Control Panel
        setupControlPanel()
        
        // Layout
        setupLayout()
        
        // Add touch detection for pen position simulation
        setupTouchDetection()
        
        // Setup navigation bar
        setupNavigationBar()
    }
    
    // MARK: - Setup Methods
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Content Type Selector
        setupContentTypeSelector()
        
        // Main Content View
        contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .systemBackground
        view.addSubview(contentView)
        
        // PDF View (default)
        setupPDFView()
        
        // Image View (hidden initially)
        setupImageView()
        
        // GIF View (hidden initially)
        setupGIFView()
        
        // Content Selection Overlay
        contentSelectionView = HapticContentSelectionView()
        contentSelectionView.translatesAutoresizingMaskIntoConstraints = false
        contentSelectionView.backgroundColor = .clear
        contentSelectionView.delegate = self
        view.addSubview(contentSelectionView)
        
        // Control Panel
        setupControlPanel()
        
        // Layout
        setupLayout()
    }
    
    private func setupContentTypeSelector() {
        contentTypeSegment = UISegmentedControl(items: ContentType.allCases.map { "\($0.icon) \($0.displayName)" })
        contentTypeSegment.selectedSegmentIndex = 0
        contentTypeSegment.translatesAutoresizingMaskIntoConstraints = false
        contentTypeSegment.addTarget(self, action: #selector(contentTypeChanged(_:)), for: .valueChanged)
        view.addSubview(contentTypeSegment)
    }
    
    private func setupPDFView() {
        pdfView = PDFView()
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage // Changed to single page for better navigation
        pdfView.displayDirection = .vertical
        
        // Enable user interaction for navigation
        pdfView.isUserInteractionEnabled = true
        
        // Additional PDFView configuration for better navigation
        pdfView.scaleFactor = 1.0
        pdfView.minScaleFactor = 0.5
        pdfView.maxScaleFactor = 3.0
        
        print("📄 PDFView configured with navigation settings")
        
        contentView.addSubview(pdfView)
        
        // Update page controls when PDF changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfViewPageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        print("📄 PDFView setup completed with navigation controls")
    }
    
    private func setupImageView() {
        imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .systemGray6
        imageView.isHidden = true
        contentView.addSubview(imageView)
    }
    
    private func setupGIFView() {
        gifView = UIView()
        gifView.translatesAutoresizingMaskIntoConstraints = false
        gifView.backgroundColor = .systemGray6
        gifView.isHidden = true
        
        // Placeholder label for future GIF support
        let placeholderLabel = UILabel()
        placeholderLabel.text = "🎬 GIF Support\nComing Soon"
        placeholderLabel.textAlignment = .center
        placeholderLabel.numberOfLines = 2
        placeholderLabel.font = .systemFont(ofSize: 24, weight: .medium)
        placeholderLabel.textColor = .systemGray
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        gifView.addSubview(placeholderLabel)
        
        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: gifView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: gifView.centerYAnchor)
        ])
        
        contentView.addSubview(gifView)
    }
    
    private func setupControlPanel() {
        controlPanel = UIView()
        controlPanel.translatesAutoresizingMaskIntoConstraints = false
        controlPanel.backgroundColor = .systemGray6
        controlPanel.layer.cornerRadius = 12
        view.addSubview(controlPanel)
        
        // BLE Connection Status
        let connectionLabel = UILabel()
        connectionLabel.text = "MagicPen: Not Connected"
        connectionLabel.font = .systemFont(ofSize: 14)
        connectionLabel.textColor = .systemRed
        connectionLabel.translatesAutoresizingMaskIntoConstraints = false
        connectionLabel.tag = 100 // For updating later
        controlPanel.addSubview(connectionLabel)
        
        // Selected Content Info
        let selectedContentLabel = UILabel()
        selectedContentLabel.text = "Selected Content: 0 segments"
        selectedContentLabel.font = .systemFont(ofSize: 14)
        selectedContentLabel.translatesAutoresizingMaskIntoConstraints = false
        selectedContentLabel.tag = 101 // For updating later
        controlPanel.addSubview(selectedContentLabel)
        
        // Haptic Pattern Info
        let patternLabel = UILabel()
        patternLabel.text = "Haptic Pattern: None"
        patternLabel.font = .systemFont(ofSize: 14)
        patternLabel.translatesAutoresizingMaskIntoConstraints = false
        patternLabel.tag = 102 // For updating later
        controlPanel.addSubview(patternLabel)
        
        // Library Stats
        let libraryStatsLabel = UILabel()
        libraryStatsLabel.text = "Library: Loading..."
        libraryStatsLabel.font = .systemFont(ofSize: 12)
        libraryStatsLabel.textColor = .systemGray
        libraryStatsLabel.translatesAutoresizingMaskIntoConstraints = false
        libraryStatsLabel.tag = 103 // For updating later
        controlPanel.addSubview(libraryStatsLabel)
        
        // Import Content Button
        let importButton = UIButton(type: .system)
        importButton.setTitle("Import Content", for: .normal)
        importButton.backgroundColor = .systemBlue
        importButton.setTitleColor(.white, for: .normal)
        importButton.layer.cornerRadius = 8
        importButton.addTarget(self, action: #selector(importContent), for: .touchUpInside)
        importButton.translatesAutoresizingMaskIntoConstraints = false
        controlPanel.addSubview(importButton)
        
        // Clear Selection Button
        let clearButton = UIButton(type: .system)
        clearButton.setTitle("Clear All", for: .normal)
        clearButton.addTarget(self, action: #selector(clearSelections), for: .touchUpInside)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        controlPanel.addSubview(clearButton)
        
        // Haptic Test Button
        let testButton = UIButton(type: .system)
        testButton.setTitle("Analyze PDF", for: .normal)
        testButton.addTarget(self, action: #selector(testHaptics), for: .touchUpInside)
        testButton.translatesAutoresizingMaskIntoConstraints = false
        controlPanel.addSubview(testButton)
        
        // Page control in center
        pageControl = UIPageControl()
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
        pageControl.layer.cornerRadius = 8
        pageControl.addTarget(self, action: #selector(pageChanged(_:)), for: .valueChanged)
        pageControl.isUserInteractionEnabled = true
        controlPanel.addSubview(pageControl)
        
        // Navigation buttons below page control
        prevButton = UIButton(type: .system)
        prevButton.setTitle("◀ Prev", for: .normal)
        prevButton.backgroundColor = .systemBlue
        prevButton.setTitleColor(.white, for: .normal)
        prevButton.layer.cornerRadius = 8
        prevButton.addTarget(self, action: #selector(previousPage), for: .touchUpInside)
        prevButton.translatesAutoresizingMaskIntoConstraints = false
        controlPanel.addSubview(prevButton)
        
        nextButton = UIButton(type: .system)
        nextButton.setTitle("Next ▶", for: .normal)
        nextButton.backgroundColor = .systemBlue
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.layer.cornerRadius = 8
        nextButton.addTarget(self, action: #selector(nextPage), for: .touchUpInside)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        controlPanel.addSubview(nextButton)
        
        NSLayoutConstraint.activate([
            connectionLabel.topAnchor.constraint(equalTo: controlPanel.topAnchor, constant: 12),
            connectionLabel.leadingAnchor.constraint(equalTo: controlPanel.leadingAnchor, constant: 16),
            
            selectedContentLabel.topAnchor.constraint(equalTo: connectionLabel.bottomAnchor, constant: 6),
            selectedContentLabel.leadingAnchor.constraint(equalTo: controlPanel.leadingAnchor, constant: 16),
            
            patternLabel.topAnchor.constraint(equalTo: selectedContentLabel.bottomAnchor, constant: 6),
            patternLabel.leadingAnchor.constraint(equalTo: controlPanel.leadingAnchor, constant: 16),
            
            libraryStatsLabel.topAnchor.constraint(equalTo: patternLabel.bottomAnchor, constant: 6),
            libraryStatsLabel.leadingAnchor.constraint(equalTo: controlPanel.leadingAnchor, constant: 16),
            
            // Right button column
            importButton.topAnchor.constraint(equalTo: controlPanel.topAnchor, constant: 12),
            importButton.trailingAnchor.constraint(equalTo: controlPanel.trailingAnchor, constant: -16),
            importButton.widthAnchor.constraint(equalToConstant: 120),
            importButton.heightAnchor.constraint(equalToConstant: 32),
            
            clearButton.topAnchor.constraint(equalTo: importButton.bottomAnchor, constant: 8),
            clearButton.trailingAnchor.constraint(equalTo: controlPanel.trailingAnchor, constant: -16),
            
            testButton.topAnchor.constraint(equalTo: clearButton.bottomAnchor, constant: 8),
            testButton.trailingAnchor.constraint(equalTo: controlPanel.trailingAnchor, constant: -16),
            
            // Page control in center
            pageControl.topAnchor.constraint(equalTo: testButton.bottomAnchor, constant: 12),
            pageControl.centerXAnchor.constraint(equalTo: controlPanel.centerXAnchor),
            pageControl.heightAnchor.constraint(equalToConstant: 30),
            
            // Navigation buttons below page control
            prevButton.topAnchor.constraint(equalTo: pageControl.bottomAnchor, constant: 8),
            prevButton.leadingAnchor.constraint(equalTo: controlPanel.leadingAnchor, constant: 16),
            prevButton.widthAnchor.constraint(equalToConstant: 120),
            prevButton.heightAnchor.constraint(equalToConstant: 32),
            
            nextButton.topAnchor.constraint(equalTo: pageControl.bottomAnchor, constant: 8),
            nextButton.trailingAnchor.constraint(equalTo: controlPanel.trailingAnchor, constant: -16),
            nextButton.widthAnchor.constraint(equalToConstant: 120),
            nextButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    private func setupLayout() {
        NSLayoutConstraint.activate([
            contentTypeSegment.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            contentTypeSegment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            contentTypeSegment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            contentView.topAnchor.constraint(equalTo: contentTypeSegment.bottomAnchor, constant: 8),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: controlPanel.topAnchor),
            
            pdfView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            gifView.topAnchor.constraint(equalTo: contentView.topAnchor),
            gifView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            gifView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            gifView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            contentSelectionView.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentSelectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentSelectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentSelectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            controlPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            controlPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            controlPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            controlPanel.heightAnchor.constraint(equalToConstant: 200)
        ])
    }
    
    private func setupComponents() {
        // Initialize BLE Controller
        bleController = BLEController()
        bleController.delegate = self
        
        // Initialize Haptic Library with enhanced configuration
        let config = HapticLibraryConfig(
            preloadPatterns: true,
            enableCustomPatterns: true,
            maxCustomPatterns: 100,
            supportedContentTypes: [.text, .image, .gif],
            defaultIntensityMultiplier: 1.0
        )
        hapticLibrary = HapticLibrary.shared // Use singleton
        hapticLibrary.reconfigure(with: config) // Pass configuration
        
        // Update library stats after initialization
        updateLibraryStats()
        print("🔄 Library stats updated: \(hapticLibrary.getAllPatterns().count) enhanced patterns")
        
        // Delay update stats again to ensure basic patterns are fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.updateLibraryStats()
            print("🔄 Delayed library stats update: \(self.hapticLibrary.getAllPatterns().count) enhanced patterns")
        }
    }
    
    private func setupNavigationBar() {
        title = "Haptic Content Reader"
        
        let importButton = UIBarButtonItem(
            title: "Import",
            style: .plain,
            target: self,
            action: #selector(importContent)
        )
        
        let connectButton = UIBarButtonItem(
            title: "Connect",
            style: .plain,
            target: self,
            action: #selector(connectDevice)
        )
        
        let libraryButton = UIBarButtonItem(
            title: "Library",
            style: .plain,
            target: self,
            action: #selector(showHapticLibrary)
        )
        
        navigationItem.leftBarButtonItems = [importButton, libraryButton]
        navigationItem.rightBarButtonItem = connectButton
    }
    
    // MARK: - Actions
    
    @objc private func contentTypeChanged(_ sender: UISegmentedControl) {
        let newType = ContentType.allCases[sender.selectedSegmentIndex]
        switchToContentType(newType)
        
        // Show import hint
        showImportHint(for: newType)
    }
    
    private func switchToContentType(_ contentType: ContentType) {
        currentContentType = contentType
        
        // Hide all content views
        pdfView.isHidden = true
        imageView.isHidden = true
        gifView.isHidden = true
        
        // Show appropriate content view
        switch contentType {
        case .text:
            pdfView.isHidden = false
        case .image:
            imageView.isHidden = false
        case .gif:
            gifView.isHidden = false
        }
        
        // Update selection view
        contentSelectionView.setContentType(contentType)
        
        // Clear previous selections
        clearSelections()
        
        print("📱 Switched to content type: \(contentType.displayName)")
    }
    
    @objc private func importContent() {
        switch currentContentType {
        case .text:
            importPDF()
        case .image:
            importImage()
        case .gif:
            importGIF()
        }
    }
    
    private func importPDF() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }
    
    private func importImage() {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.sourceType = .photoLibrary
        imagePicker.mediaTypes = ["public.image"]
        present(imagePicker, animated: true)
    }
    
    private func importGIF() {
        showAlert(title: "GIF Support", message: "GIF import functionality will be available in a future update.")
    }
    
    @objc private func connectDevice() {
        bleController.startScan()
    }
    
    @objc private func showHapticLibrary() {
        // Show haptic library browser (placeholder)
        let alert = UIAlertController(title: "Haptic Library", message: "Library contains \(hapticLibrary.getAllPatterns().count) patterns", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presentAlert(alert)
    }
    
    @objc private func clearSelections() {
        selectedContentSegments.removeAll()
        contentSelectionView.clearSelections()
        updateUI()
    }
    
    @objc private func testHaptics() {
        // Check if we have a PDF loaded
        guard let document = pdfView.document else {
            showAlert(title: "No PDF File", message: "Please import a PDF file first.")
            return
        }
        
        print("Starting PDF analysis for: \(document.documentURL?.lastPathComponent ?? "Unknown")")
        print("PDF has \(document.pageCount) pages")
        
        // Show analysis mode selection with test option
        let alert = UIAlertController(
            title: "Select Analysis Mode",
            message: "Please select the content type to analyze:",
            preferredStyle: .actionSheet
        )
        
        // Normal analysis options
        for mode in PDFAnalysisMode.allCases {
            alert.addAction(UIAlertAction(title: "\(mode.icon) \(mode.displayName)", style: .default) { _ in
                self.selectedAnalysisMode = mode
                if mode == .textOnly || mode == .textAndImage {
                    self.showTextGranularitySelection()
                } else {
                    self.startPDFAnalysis(mode: mode, granularity: .sentence)
                }
            })
        }
        
        // Test image detection option
        alert.addAction(UIAlertAction(title: "🔍 Test Image Detection", style: .default) { _ in
            guard let url = document.documentURL else {
                self.showAlert(title: "PDF File Error", message: "Unable to get PDF file path.")
            return
        }
        
            Task {
                await self.testImageDetection(from: url)
            }
        })
        
        // Test text highlighting option
        alert.addAction(UIAlertAction(title: "📝 Test Text Highlighting", style: .default) { _ in
            Task {
                await self.testTextHighlighting()
            }
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentAlert(alert)
    }
    
    // MARK: - PDF Analysis Methods
    
    private func showAnalysisModeSelection() {
        let alert = UIAlertController(
            title: "Select Analysis Mode",
            message: "Please select the content type to analyze:",
            preferredStyle: .actionSheet
        )
        
        for mode in PDFAnalysisMode.allCases {
            alert.addAction(UIAlertAction(title: "\(mode.icon) \(mode.displayName)", style: .default) { _ in
                self.selectedAnalysisMode = mode
                if mode == .textOnly || mode == .textAndImage {
                    self.showTextGranularitySelection()
                } else {
                    self.startPDFAnalysis(mode: mode, granularity: .sentence)
                }
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentAlert(alert)
    }
    
    private func showTextGranularitySelection() {
        let alert = UIAlertController(
            title: "Select Text Granularity",
            message: "Please select the text analysis granularity level:",
            preferredStyle: .actionSheet
        )
        
        for granularity in TextGranularityLevel.allCases {
            alert.addAction(UIAlertAction(title: "\(granularity.icon) \(granularity.displayName)", style: .default) { _ in
                self.selectedGranularity = granularity
                self.startPDFAnalysis(mode: self.selectedAnalysisMode, granularity: granularity)
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentAlert(alert)
    }
    
    private func startPDFAnalysis(mode: PDFAnalysisMode, granularity: TextGranularityLevel) {
        guard let document = pdfView.document,
              let url = document.documentURL else {
            showAlert(title: "PDF File Error", message: "Unable to get PDF file path.")
            return
        }
        
        // Show progress
        showAnalysisProgress()
        
        Task {
            do {
                // Ensure we have access to the PDF file
                guard url.startAccessingSecurityScopedResource() else {
                    throw PDFAnalysisError.analysisFailed("Unable to access PDF file")
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let result = try await PDFAnalysisManager.shared.analyzePDFWithGranularity(
                    from: url,
                    mode: mode,
                    granularity: granularity
                ) { progress in
                    DispatchQueue.main.async {
                        self.updateAnalysisProgress(progress)
                    }
                }
                
                DispatchQueue.main.async {
                    self.hideAnalysisProgress()
                    self.displayAnalysisResults(result)
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.hideAnalysisProgress()
                    print("❌ PDF Analysis Error: \(error)")
                    self.showAlert(title: "Analysis Failed", message: "Error details: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func displayAnalysisResults(_ result: PDFAnalysisResult) {
        // Clear previous selections
        selectedContentSegments.removeAll()
        contentSelectionView.clearSelections()
        
        // Show progress for embedding matching
        showEmbeddingMatchingProgress()
        
        Task {
            do {
                // Extract all unique emotions from analysis results
                let textEmotions = result.textRegions.map { $0.emotion }
                let imageEmotions = result.imageRegions.map { $0.emotion }
                let allEmotions = Array(Set(textEmotions + imageEmotions))
                
                print("Starting GPT embedding matching for \(allEmotions.count) unique emotions")
                
                // Batch match emotions to patterns using GPT embeddings
                let emotionMatches = try await hapticLibrary.batchMatchEmotionsToPatterns(
                    emotions: allEmotions,
                    contentType: nil // Match against all content types
                )
                
                print("GPT embedding matching completed: \(emotionMatches.count) matches found")
                
                // Convert GPT analysis results to unified text segments format
                let gptTextSegments = result.textRegions.map { textRegion in
                    return (
                        text: textRegion.text,
                        emotion: textRegion.emotion,
                        confidence: textRegion.confidence,
                        reasoning: textRegion.reasoning
                    )
                }
                
                // Use unified text search mechanism for GPT results
                print("Processing \(gptTextSegments.count) GPT text segments using unified search")
                let textContentSegments = searchAndCreateTextSegments(gptTextSegments, isTestMode: false)
                
                // Update haptic patterns with GPT embedding matches
                var newSegments: [ContentSegment] = []
                for segment in textContentSegments {
                    var updatedMetadata = segment.metadata
                    
                    // Apply GPT embedding matching if available
                    if let emotion = segment.emotion,
                       let match = emotionMatches[emotion] {
                        updatedMetadata["embedding_similarity"] = match.similarity
                        updatedMetadata["match_method"] = "gpt_embedding"
                        
                        let updatedSegment = ContentSegment(
                            content: segment.content,
                            contentType: segment.contentType,
                            rect: segment.rect,
                            emotion: segment.emotion,
                            scene: segment.scene,
                            hapticPattern: match.pattern,
                            metadata: updatedMetadata
                        )
                        newSegments.append(updatedSegment)
                        } else {
                        updatedMetadata["match_method"] = "fallback"
                        updatedMetadata["embedding_similarity"] = 0.0
                        
                        let updatedSegment = ContentSegment(
                            content: segment.content,
                            contentType: segment.contentType,
                            rect: segment.rect,
                            emotion: segment.emotion,
                            scene: segment.scene,
                            hapticPattern: segment.hapticPattern,
                            metadata: updatedMetadata
                        )
                        newSegments.append(updatedSegment)
                    }
                }
                // Image regions - show all regions for now (will be filtered by page later)
                let allImageRegions = result.imageRegions
                print("Processing \(allImageRegions.count) total image regions")
                
                for imageRegion in allImageRegions {
                    let matchedPattern: HapticPattern
                    let similarity: Float
                    if let match = emotionMatches[imageRegion.emotion] {
                        matchedPattern = match.pattern
                        similarity = match.similarity
                    } else {
                        matchedPattern = hapticLibrary.getRecommendedPattern(
                            for: .image,
                            emotion: imageRegion.emotion,
                            scene: nil
                        )
                        similarity = 0.0
                    }
                    let segment = ContentSegment(
                        content: imageRegion.description,
                        contentType: .image,
                        rect: imageRegion.boundingBox,
                        emotion: imageRegion.emotion,
                        scene: nil,
                        hapticPattern: matchedPattern,
                        metadata: [
                            "page_index": imageRegion.pageIndex,
                            "confidence": imageRegion.confidence,
                            "visual_elements": imageRegion.visualElements.joined(separator: ", "),
                            "auto_matched": "gpt_embedding",
                            "pattern_name": matchedPattern.name,
                            "embedding_similarity": similarity,
                            "match_method": similarity > 0 ? "gpt_embedding" : "fallback",
                            "image": imageRegion.imageData as Any
                        ]
                    )
                    newSegments.append(segment)
                }
                // Update UI on main thread
                DispatchQueue.main.async {
                    self.hideEmbeddingMatchingProgress()
                    self.allEmotionSegments = newSegments
                    self.selectedContentSegments = newSegments
                    self.updateUI()
                    // Store all segments for later page-based filtering
                    self.allEmotionSegments = newSegments
                    
                    // Update current page display using unified display logic
                    self.updateEmotionRegionsForCurrentPage()
                    let imageSegments = newSegments.filter { $0.contentType == .image }
                    if !imageSegments.isEmpty {
                        // Filter image segments for current page
                        let currentPageIndex = self.pdfView.document?.index(for: self.pdfView.currentPage ?? self.pdfView.document?.page(at: 0) ?? PDFPage()) ?? 0
                        let currentPageImageSegments = imageSegments.filter { segment in
                            if let pageIndex = segment.metadata["page_index"] as? Int {
                                return pageIndex == currentPageIndex
                            }
                            return false
                        }
                        if !currentPageImageSegments.isEmpty {
                            self.contentSelectionView.showEmotionRegions(currentPageImageSegments)
                            print("📊 Displayed \(currentPageImageSegments.count) image regions for current page \(currentPageIndex + 1)")
                        } else {
                            print("📊 No image regions found for current page \(currentPageIndex + 1)")
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.hideEmbeddingMatchingProgress()
                    print("❌ PDF Analysis Error: \(error)")
                    self.showAlert(title: "Analysis Failed", message: "Error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Intersection over Union for two CGRects
    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        if intersection.isNull { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        return intersectionArea / unionArea
    }
    
    private func showAnalysisProgress() {
        // Create progress overlay
        let progressView = UIView()
        progressView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.tag = 300
        view.addSubview(progressView)
        
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = .white
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        progressView.addSubview(activityIndicator)
        
        let progressLabel = UILabel()
        progressLabel.text = "Analyzing PDF..."
        progressLabel.textColor = .white
        progressLabel.textAlignment = .center
        progressLabel.font = .systemFont(ofSize: 16, weight: .medium)
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressView.addSubview(progressLabel)
        
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            activityIndicator.centerXAnchor.constraint(equalTo: progressView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: progressView.centerYAnchor, constant: -20),
            
            progressLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            progressLabel.centerXAnchor.constraint(equalTo: progressView.centerXAnchor),
            progressLabel.leadingAnchor.constraint(equalTo: progressView.leadingAnchor, constant: 20),
            progressLabel.trailingAnchor.constraint(equalTo: progressView.trailingAnchor, constant: -20)
        ])
    }
    
    private func updateAnalysisProgress(_ progress: String) {
        if let progressView = view.viewWithTag(300),
           let progressLabel = progressView.subviews.last as? UILabel {
            progressLabel.text = progress
        }
    }
    
    private func hideAnalysisProgress() {
        if let progressView = view.viewWithTag(300) {
            progressView.removeFromSuperview()
        }
    }
    
    /// Display detailed analysis results
    private func showDetailedAnalysisResults() {
        let alert = UIAlertController(
            title: "📊 Content Analysis Results",
            message: "Found \(selectedContentSegments.count) content regions, please select the regions to configure haptic feedback:",
            preferredStyle: .actionSheet
        )
        
        // Create options for each content region
        for (index, segment) in selectedContentSegments.enumerated() {
            let emotionText = segment.emotion?.capitalized ?? "Unknown"
            let contentTypeIcon = segment.contentType.icon
            let matchMethod = segment.metadata["match_method"] as? String ?? "unknown"
            let matchIcon = matchMethod == "gpt_embedding" ? "🤖" : "🔄"
            
            let title = "\(contentTypeIcon) \(matchIcon) Region \(index + 1): \(emotionText)"
            
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                self.configureHapticPattern(for: segment, at: index)
            })
        }
        
        // Add option to auto-configure all regions
        alert.addAction(UIAlertAction(title: "🤖 Auto-configure All Regions", style: .default) { _ in
            self.autoConfigureAllSegments()
        })
        
        // Add option to view GPT Embedding match details
        alert.addAction(UIAlertAction(title: "🤖 View GPT Embedding Match Details", style: .default) { _ in
            self.showEmbeddingMatchDetails()
        })
        
        // Add option to view analysis details
        alert.addAction(UIAlertAction(title: "📋 View Analysis Details", style: .default) { _ in
            self.showAnalysisDetails()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        presentAlert(alert)
    }
    
    /// Configure haptic pattern for a single region
    private func configureHapticPattern(for segment: ContentSegment, at index: Int) {
        let alert = UIAlertController(
            title: "Configure Haptic Pattern",
            message: """
            Content Type: \(segment.contentType.displayName)
            Detected Emotion: \(segment.emotion?.capitalized ?? "Unknown")
            
            Please select a haptic pattern:
            """,
            preferredStyle: .actionSheet
        )
        
        // Get recommended pattern
        let recommendedPattern = hapticLibrary.getRecommendedPattern(
            for: segment.contentType,
            emotion: segment.emotion,
            scene: segment.scene
        )
        
        // Recommended pattern option
        alert.addAction(UIAlertAction(title: "🤖 Recommended Pattern: \(recommendedPattern.name)", style: .default) { _ in
            self.selectedContentSegments[index].hapticPattern = recommendedPattern
            self.updateUI()
            print("✅ Configured recommended pattern for region \(index + 1): \(recommendedPattern.name)")
        })
        
        // Manual pattern selection option
        alert.addAction(UIAlertAction(title: "📋 Manual Pattern Selection", style: .default) { _ in
            self.showManualPatternSelection(for: segment, at: index)
        })
        
        // Custom pattern option
        alert.addAction(UIAlertAction(title: "⚙️ Custom Parameters", style: .default) { _ in
            self.showCustomPatternConfiguration(for: segment, at: index)
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        presentAlert(alert)
    }
    
    /// Auto-configure all regions
    private func autoConfigureAllSegments() {
        var configuredCount = 0
        
        for (index, segment) in selectedContentSegments.enumerated() {
            let recommendedPattern = hapticLibrary.getRecommendedPattern(
                for: segment.contentType,
                emotion: segment.emotion,
                scene: segment.scene
            )
            
            selectedContentSegments[index].hapticPattern = recommendedPattern
            configuredCount += 1
            
            print("🤖 Auto-configured region \(index + 1): \(recommendedPattern.name)")
        }
        
        updateUI()
        
        let alert = UIAlertController(
            title: "Auto-configuration Complete",
            message: "Auto-configured haptic patterns for \(configuredCount) regions. You can now test haptic feedback with Apple Pencil!",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Start Testing", style: .default))
        present(alert, animated: true)
    }
    
    /// Display analysis details
    private func showAnalysisDetails() {
        var details = "📊 Detailed Analysis Results:\n\n"
        
        for (index, segment) in selectedContentSegments.enumerated() {
            details += "Region \(index + 1) (\(segment.contentType.displayName)):\n"
            details += "• Content: \(segment.content.prefix(100))...\n"
            
            if let emotion = segment.emotion {
                details += "• Emotion: \(emotion)\n"
            }
            
            if let scene = segment.scene {
                details += "• Scene: \(scene.displayName)\n"
            }
            
            details += "\n"
        }
        
        let alert = UIAlertController(title: "Analysis Details", message: details, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    /// Show manual pattern selection
    private func showManualPatternSelection(for segment: ContentSegment, at index: Int) {
        let alert = UIAlertController(
            title: "Select Haptic Pattern",
            message: "Select haptic pattern for \(segment.contentType.displayName) content:",
            preferredStyle: .actionSheet
        )
        
        // Get available patterns
        let availablePatterns = hapticLibrary.getAllPatterns().filter { pattern in
            pattern.contentTypes.contains(segment.contentType)
        }
        
        for pattern in availablePatterns {
            let categoryIcon = getCategoryIcon(for: pattern.category)
            alert.addAction(UIAlertAction(title: "\(categoryIcon) \(pattern.name)", style: .default) { _ in
                self.selectedContentSegments[index].hapticPattern = pattern
                self.updateUI()
                print("✅ Manually selected pattern: \(pattern.name)")
            })
        }
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentAlert(alert)
    }
    
    /// Show custom parameter configuration
    private func showCustomPatternConfiguration(for segment: ContentSegment, at index: Int) {
        let alert = UIAlertController(
            title: "Custom Haptic Parameters",
            message: "Customize haptic parameters for \(segment.contentType.displayName) content:",
            preferredStyle: .alert
        )
        
        // Add intensity input field
        alert.addTextField { textField in
            textField.placeholder = "Intensity (1-255)"
            textField.text = "50"
            textField.keyboardType = .numberPad
        }
        
        // Add duration input field
        alert.addTextField { textField in
            textField.placeholder = "Duration (seconds)"
            textField.text = "0.5"
            textField.keyboardType = .decimalPad
        }
        
        // Confirm button
        alert.addAction(UIAlertAction(title: "Create Custom Pattern", style: .default) { _ in
            guard let intensityText = alert.textFields?[0].text,
                  let durationText = alert.textFields?[1].text,
                  let intensity = UInt8(intensityText),
                  let duration = Double(durationText) else {
                print("❌ Invalid parameter input")
                return
            }
            
            // Create custom pattern
            let customPattern = HapticPattern(
                id: "custom_\(UUID().uuidString)",
                name: "Custom Pattern",
                description: "User-defined haptic pattern",
                category: .feedback,
                contentTypes: [segment.contentType],
                emotion: segment.emotion,
                scene: segment.scene,
                intensity: intensity,
                duration: duration,
                pattern: [
                    HapticEvent(timestamp: 0.0, intensity: intensity, duration: duration, type: .vibration(frequency: nil))
                ],
                tags: ["custom", "user-defined"],
                isCustomizable: true,
                metadata: ["created_from": "user_custom", "segment_id": segment.id.uuidString]
            )
            
            self.selectedContentSegments[index].hapticPattern = customPattern
            self.updateUI()
            print("✅ Created custom pattern: intensity=\(intensity), duration=\(duration) seconds")
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentAlert(alert)
    }
    
    private func updateUI() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update content count
            if let label = self.controlPanel.viewWithTag(101) as? UILabel {
                label.text = "Selected Content: \(self.selectedContentSegments.count) segments"
            }
            
            // Update pattern info
            if let label = self.controlPanel.viewWithTag(102) as? UILabel {
                if let lastSegment = self.selectedContentSegments.last {
                    label.text = "Haptic Pattern: \(lastSegment.hapticPattern?.name ?? "None")"
                } else {
                    label.text = "Haptic Pattern: None"
                }
            }
        }
    }
    
    private func updateLibraryStats() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let label = self.controlPanel.viewWithTag(103) as? UILabel {
                // Count Enhanced patterns
                let enhancedPatterns = self.hapticLibrary.getAllPatterns().count
                print("🔍 Debug - Enhanced patterns count: \(enhancedPatterns)")
                
                // Note: Legacy preset counting removed - using enhanced HapticPattern system only
                let totalPatterns = enhancedPatterns
                print("🔍 Debug - Total patterns: \(totalPatterns)")
                
                // Count Enhanced patterns by content type
                let textPatterns = self.hapticLibrary.getPatterns(for: .text).count
                let imagePatterns = self.hapticLibrary.getPatterns(for: .image).count
                let gifPatterns = self.hapticLibrary.getPatterns(for: .gif).count
                print("🔍 Debug - Enhanced by type: text=\(textPatterns), image=\(imagePatterns), gif=\(gifPatterns)")
                
                let finalText = textPatterns
                let finalImage = imagePatterns
                let finalGif = gifPatterns
                
                label.text = "Library: \(totalPatterns) total (📄\(finalText) 🖼️\(finalImage) 🎬\(finalGif))"
                print("🔍 Debug - Final display text: \(label.text ?? "nil")")
            }
        }
    }
    
    /// Play haptic pattern
    private func playHapticPattern(_ pattern: HapticPattern) {
        guard bleController.isConnected else { 
            print("⚠️ BLE not connected, cannot play haptic pattern")
            return 
        }
        
        // Cancel any existing haptic work items
        for workItem in hapticWorkItems {
            workItem.cancel()
        }
        hapticWorkItems.removeAll()
        
        // Set current pattern
        currentlyPlayingPattern = pattern
        
        print("Starting haptic pattern: \(pattern.name) (duration: \(pattern.duration)s)")
        
        // Execute all events immediately without delay
        for (index, event) in pattern.pattern.enumerated() {
                switch event.type {
            case .vibration(let frequency):
                bleController.sendVibration(intensity: event.intensity, duration: event.duration)
                print("Event \(index): Immediate vibration intensity=\(event.intensity) duration=\(event.duration)s")
                
                case .force(let x, let y):
                bleController.sendForce(x: x, y: y, duration: event.duration)
                print("Event \(index): Immediate force x=\(x) y=\(y) duration=\(event.duration)s")
                
                case .pause:
                    print("Event \(index): Pause duration=\(event.duration)s")
                // Do nothing for pause
                
            case .ramp(let startIntensity, let endIntensity):
                // Use average intensity as fallback for ramp
                let avgIntensity = (startIntensity + endIntensity) / 2
                bleController.sendVibration(intensity: avgIntensity, duration: event.duration)
                print("Event \(index): Ramp vibration start=\(startIntensity) end=\(endIntensity) duration=\(event.duration)s")
                
            case .pulse(let count, let interval):
                // Simplified pulse implementation - just use the event intensity
                bleController.sendVibration(intensity: event.intensity, duration: event.duration)
                print("💥 Event \(index): Pulse vibration count=\(count) interval=\(interval) duration=\(event.duration)s")
            }
        }
        
        // Auto-stop: automatically stop vibration based on pattern duration
        let autoStopWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Only stop if the currently playing pattern is still this pattern (avoid accidentally stopping new patterns)
            if self.currentlyPlayingPattern?.id == pattern.id {
                self.bleController.stop()
                self.currentlyPlayingPattern = nil
                print("⏰ Auto-stop vibration: pattern '\(pattern.name)' playback completed (\(pattern.duration)s)")
                print("🛑 Even if pen tip is not lifted, vibration has been automatically stopped according to preset duration")
            }
        }
        
        // Use pattern duration as auto-stop time
        DispatchQueue.main.asyncAfter(deadline: .now() + pattern.duration, execute: autoStopWorkItem)
        hapticWorkItems.append(autoStopWorkItem)
        
        print("✅ Vibration started, will auto-stop after \(pattern.duration)s")
        print("🖊️ If pen tip is lifted or leaves the area, it will stop immediately")
    }
    
    /// Immediately stop all vibration
    private func stopHapticPlayback() {
        // Cancel all pending vibration tasks
        for workItem in hapticWorkItems {
            workItem.cancel()
        }
        let cancelledCount = hapticWorkItems.count
        hapticWorkItems.removeAll()
        
        // Force send stop command - reference original code approach
        bleController.stop() // This will send both force feedback stop (all 0) and vibration stop commands
        
        // Send again immediately to ensure it takes effect
        bleController.stop()
        
        // Clear playback state
        currentlyPlayingPattern = nil
        
        print("🛑 Force stopped all haptic playback immediately - cancelled \(cancelledCount) pending tasks")
        print("🛑 Double stop command sent for immediate effect")
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presentAlert(alert)
    }
    
    // MARK: - Pen Interaction Logic
    
    /// Handle pen movement in content area, detect if touching selected content
    func handlePenPosition(_ position: CGPoint) {
        guard bleController.isConnected else { 
            print("⚠️ BLE not connected, ignoring pen position")
            return 
        }
        
        print("🖊️ Pen position: (\(Int(position.x)), \(Int(position.y))) - checking \(selectedContentSegments.count) segments")
        
        // Check if pen is within any selected content area
        var foundActiveSegment = false
        
        for (index, segment) in selectedContentSegments.enumerated() {
            let isInside = segment.rect.contains(position)
            let hasPattern = segment.hapticPattern != nil
            
            print("   Segment \(index + 1): rect=(\(Int(segment.rect.minX)),\(Int(segment.rect.minY)),\(Int(segment.rect.width)),\(Int(segment.rect.height))) inside=\(isInside) pattern=\(hasPattern ? "✓" : "✗")")
            
            if isInside && hasPattern {
                foundActiveSegment = true
                
                // Only trigger haptic when pen first enters the area AND no pattern is currently playing
                if !segment.isActive {
                    // Stop previous haptic playback first
                    stopHapticPlayback()
                    
                    // Mark segment as active and play haptic pattern
                    segment.isActive = true
                    playHapticPattern(segment.hapticPattern!)
                    print("Pen entered content area \(index + 1), playing haptic pattern: \(segment.hapticPattern!.name)")
                    
                    // Highlight currently active area
                    highlightActiveSegment(segment)
                } else if currentlyPlayingPattern != nil {
                    // Pattern is still playing - do nothing, let it complete naturally
                    print("Pen continuing in active area \(index + 1) - pattern still playing: \(currentlyPlayingPattern!.name)")
                } else {
                    // Segment is active but no pattern is playing (pattern finished naturally)
                    print("Pen in active area \(index + 1) - pattern completed, not replaying")
                }
                return // Exit early since we found an active segment
            }
        }
        
        // If pen is not in any content area, deactivate all segments
        if !foundActiveSegment {
            var hadActiveSegments = false
            for (index, segment) in selectedContentSegments.enumerated() {
                if segment.isActive {
                    segment.isActive = false
                    hadActiveSegments = true
                    print("🖊️ Pen left content area \(index + 1)")
                }
            }
            
            if hadActiveSegments {
                // Stop haptic playback when leaving all areas
                stopHapticPlayback()
                
                // Clear highlight
                clearActiveHighlight()
                
                print("🛑 Stopped haptic playback - pen left all areas")
            }
        }
    }
    
    private func highlightActiveSegment(_ segment: ContentSegment) {
        // Highlight active area on selection view
        contentSelectionView.highlightArea(
            rect: segment.rect,
            contentType: segment.contentType,
            emotion: segment.emotion,
            scene: segment.scene
        )
    }
    
    private func clearActiveHighlight() {
        // Clear active highlight (implementation can be added here)
        // contentSelectionView.clearActiveHighlight()
    }
    
    /// Pen position update callback
    func didTouchAt(point: CGPoint) {
        handlePenPosition(point)
    }
    
    // MARK: - Touch Detection (Apple Pencil)
    
    private func setupTouchDetection() {
        // Enable Apple Pencil interaction on content selection view
        contentSelectionView.isUserInteractionEnabled = true
        contentSelectionView.isMultipleTouchEnabled = false
        
        print("🖊️ Apple Pencil detection setup complete")
        print("📍 Waiting for Apple Pencil touches on contentSelectionView")
    }
    
    // Override touch methods to detect Apple Pencil
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        for touch in touches {
            if touch.type == .pencil {
                // Pen tip pressed down - detect position and play vibration
                let location = touch.location(in: contentSelectionView)
                let force = touch.force
                
                print("🖊️ Apple Pencil touched down at: (\(Int(location.x)), \(Int(location.y))) force: \(String(format: "%.2f", force))")
                
                // Use unified position handling method, consistent with Navigation project
                handlePenPosition(location)
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        for touch in touches {
            if touch.type == .pencil {
                // Pen tip moved - use same processing logic, consistent with Navigation project
                let location = touch.location(in: contentSelectionView)
                let force = touch.force
                
                print("🖊️ Apple Pencil moved to: (\(Int(location.x)), \(Int(location.y))) force: \(String(format: "%.2f", force))")
                
                // Use unified position handling method, consistent with Navigation project
                handlePenPosition(location)
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        for touch in touches {
            if touch.type == .pencil {
                let location = touch.location(in: contentSelectionView)
                print("🖊️ Apple Pencil lifted at: (\(Int(location.x)), \(Int(location.y)))")
                
                // Call specialized pen tip lift handling method
                didLiftPencil()
                
                print("🛑 Stopped vibration immediately - pencil lifted")
                
                // Deactivate all segments when pencil is lifted
                for (index, segment) in selectedContentSegments.enumerated() {
                    if segment.isActive {
                        segment.isActive = false
                        print("🖊️ Pencil lifted - deactivated content area \(index + 1)")
                    }
                }
                clearActiveHighlight()
                
                print("🔄 Reset playing pattern - ready for next touch")
            }
        }
    }
    
    /// Pen tip lift handling method - implemented following Navigation project, enhanced stop protection
    func didLiftPencil() {
        print("🖊️ The user lifts the pencil - MainViewController processing")
        
        // First layer of protection: immediately stop application layer haptic playback
        stopHapticPlayback()
        
        // Second layer of protection: call BLE controller's enhanced stop sequence
        bleController.didLiftPencil()
        
        // Third layer of protection: immediately send stop command again to ensure it takes effect
        bleController.stop()
        
        // Fourth layer of protection: force stop vibration
        bleController.stopVibration()
        
        print("🛑 Multi-layer emergency stop sequence completed")
    }
    
    
    // MARK: - Import Hint
    
    private func showImportHint(for contentType: ContentType) {
        var message = ""
        
        switch contentType {
        case .text:
            if pdfView.document == nil {
                message = "📄 Tap 'Import Content' or navigate to Import to load a PDF document for text selection and haptic feedback."
            }
        case .image:
            if imageView.image == nil {
                message = "🖼️ Tap 'Import Content' or navigate to Import to load an image for visual content haptic feedback."
            }
        case .gif:
            message = "🎬 GIF support is coming soon! You can still configure haptic patterns for future use."
        }
        
        if !message.isEmpty {
            // Show a brief toast-style message
            let alert = UIAlertController(title: "\(contentType.icon) \(contentType.displayName) Mode", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            present(alert, animated: true)
        }
    }
    
    /// Get category icon
    private func getCategoryIcon(for category: HapticCategory) -> String {
        switch category {
        case .emotion: return "💝"
        case .scene: return "🎬"
        case .interaction: return "👆"
        case .feedback: return "📳"
        }
    }
    
    /// Present alert with iPad popover support
    private func presentAlert(_ alert: UIAlertController) {
        // Configure popover for iPad
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }
    
    // MARK: - Page Navigation Methods
    
    @objc private func pageChanged(_ sender: UIPageControl) {
        guard let document = pdfView.document else { 
            print("⚠️ Cannot change page - no PDF document")
            return 
        }
        
        let pageIndex = sender.currentPage
        print("📄 Page control changed to page \(pageIndex + 1)")
        
        if pageIndex < document.pageCount {
            if let page = document.page(at: pageIndex) {
                pdfView.go(to: page)
                print("✅ Navigated to page \(pageIndex + 1)")
                // Emotion regions will be updated by pdfViewPageChanged notification
            } else {
                print("❌ Failed to get page at index \(pageIndex)")
            }
        } else {
            print("❌ Page index \(pageIndex) is out of bounds (max: \(document.pageCount - 1))")
        }
    }
    
    @objc private func previousPage() {
        print("📄 Previous page button tapped")
        
        guard let document = pdfView.document else { 
            print("⚠️ Cannot go to previous page - no PDF document")
            return 
        }
        
        guard pdfView.canGoToPreviousPage else { 
            print("⚠️ Cannot go to previous page - already at first page")
            return 
        }
        
        pdfView.goToPreviousPage(nil)
        print("✅ Navigated to previous page")
        // Emotion regions will be updated by pdfViewPageChanged notification
    }
    
    @objc private func nextPage() {
        print("📄 Next page button tapped")
        
        guard let document = pdfView.document else { 
            print("⚠️ Cannot go to next page - no PDF document")
            return 
        }
        
        guard pdfView.canGoToNextPage else { 
            print("⚠️ Cannot go to next page - already at last page")
            return 
        }
        
        pdfView.goToNextPage(nil)
        print("✅ Navigated to next page")
        // Emotion regions will be updated by pdfViewPageChanged notification
    }
    
    @objc private func pdfViewPageChanged() {
        print("🔄 PDFView page changed notification received")
        updatePageControls()
        updateEmotionRegionsForCurrentPage()
        print("✅ Page change handling completed")
    }
    
    private func updatePageControls() {
        guard let document = pdfView.document else { 
            print("⚠️ No PDF document to update controls")
            // Reset controls when no document
            pageControl.numberOfPages = 0
            pageControl.currentPage = 0
            return 
        }
        
        print("🔄 Updating page controls for \(document.pageCount) pages")
        
        // Update page control
        pageControl.numberOfPages = document.pageCount
        print("📄 Set page control to \(document.pageCount) pages")
        
        // Safely get current page index
        let currentPageIndex: Int
        if let currentPage = pdfView.currentPage {
            currentPageIndex = document.index(for: currentPage)
            print("📄 Current page from PDFView: \(currentPageIndex + 1)")
        } else {
            currentPageIndex = 0
            print("📄 No current page, defaulting to page 1")
        }
        
        pageControl.currentPage = currentPageIndex
        print("📄 Set page control current page to \(currentPageIndex + 1)")
        
        // Update navigation buttons (find them in control panel)
        let canGoPrevious = pdfView.canGoToPreviousPage
        let canGoNext = pdfView.canGoToNextPage
        
        // Update button states directly
        prevButton.isEnabled = canGoPrevious
        nextButton.isEnabled = canGoNext
        prevButton.alpha = canGoPrevious ? 1.0 : 0.5
        nextButton.alpha = canGoNext ? 1.0 : 0.5
        
        print("📄 Previous button enabled: \(prevButton.isEnabled), alpha: \(prevButton.alpha)")
        print("📄 Next button enabled: \(nextButton.isEnabled), alpha: \(nextButton.alpha)")
        
        print("📄 Current page: \(currentPageIndex + 1)/\(document.pageCount)")
        print("📄 Can go previous: \(canGoPrevious)")
        print("📄 Can go next: \(canGoNext)")
        
        // Force layout update
        pageControl.setNeedsLayout()
    }
    
    private func updateEmotionRegionsForCurrentPage() {
        guard let document = pdfView.document,
              let currentPage = pdfView.currentPage else { return }
        
        let currentPageIndex = document.index(for: currentPage)
        print("🔄 Updating emotion regions for page \(currentPageIndex + 1)")
        
        // Filter emotion segments for current page
        let currentPageSegments = allEmotionSegments.filter { segment in
            if let pageIndex = segment.metadata["page_index"] as? Int {
                return pageIndex == currentPageIndex
            }
            return false
        }
        
        print("📄 Found \(currentPageSegments.count) emotion regions on page \(currentPageIndex + 1)")
        
        // Check if we're in test mode (image detection test)
        if !allEmotionSegments.isEmpty && allEmotionSegments.first?.metadata["test_mode"] as? Bool == true {
            print("🧪 Test mode detected - showing test image regions")
            
            // Show test image regions for current page
            let currentPageTestSegments = allEmotionSegments.filter { segment in
                if let pageIndex = segment.metadata["page_index"] as? Int {
                    return pageIndex == currentPageIndex
                }
                return false
            }
            
            if !currentPageTestSegments.isEmpty {
                contentSelectionView.showEmotionRegions(currentPageTestSegments)
                print("📊 Displayed \(currentPageTestSegments.count) test image regions on page \(currentPageIndex + 1)")
            } else {
                contentSelectionView.clearSelections()
                print("📄 No test image regions found on page \(currentPageIndex + 1)")
            }
            
            // Show test text regions for current page (only first 2 pages)
            // if currentPageIndex < 2 && !allTextPositions.isEmpty && currentPageIndex < allTextPositions.count {
            //     let currentPageTextPositions = allTextPositions[currentPageIndex]
            //     let limitedTextPositions = Array(currentPageTextPositions.prefix(5)) // Limit to 5 text regions per page
            //     
            //     if !limitedTextPositions.isEmpty {
            //         contentSelectionView.showTextRegions(limitedTextPositions)
            //         print("📝 Displayed \(limitedTextPositions.count) test text regions on page \(currentPageIndex + 1)")
            //     }
            // }
        } else {
            // Normal emotion region display (including GPT analysis results)
            selectedContentSegments = currentPageSegments
            
            // Update emotion region display
            contentSelectionView.clearSelections()
            if !currentPageSegments.isEmpty {
                // Separate text and image regions for proper display
                let textSegments = currentPageSegments.filter { $0.contentType == .text }
                let imageSegments = currentPageSegments.filter { $0.contentType == .image }
                
                if !textSegments.isEmpty {
                    // For text segments, we need to create TextPosition objects from the segments
                    let textPositions = textSegments.map { segment in
                        return TextPosition(
                            text: segment.content,
                            boundingBox: segment.rect,
                            confidence: segment.metadata["confidence"] as? Float ?? 0.8
                        )
                    }
                    contentSelectionView.showTextRegions(textPositions)
                    print("📝 Displayed \(textPositions.count) text regions using segment positions")
                }
                
                if !imageSegments.isEmpty {
                    contentSelectionView.showEmotionRegions(imageSegments)
                }
                
                print("📊 Displayed \(textSegments.count) text regions and \(imageSegments.count) image regions on page \(currentPageIndex + 1)")
                
                // Debug: Show which segments are being displayed
                for (index, textSegment) in textSegments.enumerated() {
                    let searchMethod = textSegment.metadata["search_method"] as? String ?? "unknown"
                    let searchQuality = textSegment.metadata["search_quality"] as? Float ?? 0.0
                    print("📝 Text segment \(index + 1): '\(textSegment.content.prefix(30))...' (\(searchMethod), quality: \(String(format: "%.2f", searchQuality)))")
                }
            }
        }
        
        // Update UI
        updateUI()
    }
    
    // MARK: - PDF Debug Methods
    
    private func debugPDFViewState() {
        print("🔍 Debugging PDFView state...")
        
        guard let document = pdfView.document else {
            print("❌ No PDF document loaded")
            return
        }
        
        print("📄 Document info:")
        print("   - Page count: \(document.pageCount)")
        print("   - Document URL: \(document.documentURL?.lastPathComponent ?? "Unknown")")
        
        if let currentPage = pdfView.currentPage {
            let pageIndex = document.index(for: currentPage)
            print("📄 Current page: \(pageIndex + 1)")
            print("   - Page bounds: \(currentPage.bounds(for: .mediaBox))")
                    } else {
            print("❌ No current page")
        }
        
        print("📄 PDFView properties:")
        print("   - Display mode: \(pdfView.displayMode.rawValue)")
        print("   - Display direction: \(pdfView.displayDirection.rawValue)")
        print("   - Auto scales: \(pdfView.autoScales)")
        print("   - Scale factor: \(pdfView.scaleFactor)")
        print("   - Can go previous: \(pdfView.canGoToPreviousPage)")
        print("   - Can go next: \(pdfView.canGoToNextPage)")
        print("   - Is user interaction enabled: \(pdfView.isUserInteractionEnabled)")
        
        print("📄 Navigation controls:")
        print("   - Page control pages: \(pageControl.numberOfPages)")
        print("   - Page control current: \(pageControl.currentPage)")
        print("   - Previous button enabled: \(prevButton.isEnabled)")
        print("   - Next button enabled: \(nextButton.isEnabled)")
    }
    
    private func showEmbeddingMatchingProgress() {
        // Create progress overlay for embedding matching
        let progressView = UIView()
        progressView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.tag = 301 // Different tag from analysis progress
        view.addSubview(progressView)
        
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = .white
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        progressView.addSubview(activityIndicator)
        
        let progressLabel = UILabel()
        progressLabel.text = "🤖 Using GPT Embedding for intelligent haptic pattern matching..."
        progressLabel.textColor = .white
        progressLabel.textAlignment = .center
        progressLabel.font = .systemFont(ofSize: 16, weight: .medium)
        progressLabel.numberOfLines = 0
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressView.addSubview(progressLabel)
        
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            activityIndicator.centerXAnchor.constraint(equalTo: progressView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: progressView.centerYAnchor, constant: -20),
            
            progressLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            progressLabel.centerXAnchor.constraint(equalTo: progressView.centerXAnchor),
            progressLabel.leadingAnchor.constraint(equalTo: progressView.leadingAnchor, constant: 20),
            progressLabel.trailingAnchor.constraint(equalTo: progressView.trailingAnchor, constant: -20)
        ])
    }
    
    private func hideEmbeddingMatchingProgress() {
        if let progressView = view.viewWithTag(301) {
            progressView.removeFromSuperview()
        }
    }
    
    /// Show GPT Embedding match details
    private func showEmbeddingMatchDetails() {
        var details = "🤖 GPT Embedding Smart Match Details:\n\n"
        
        for (index, segment) in selectedContentSegments.enumerated() {
            details += "Region \(index + 1) (\(segment.contentType.displayName)):\n"
            details += "• Content: \(segment.content.prefix(50))...\n"
            
            if let emotion = segment.emotion {
                details += "• Detected Emotion: \(emotion)\n"
            }
            
            if let pattern = segment.hapticPattern {
                details += "• Matched Pattern: \(pattern.name)\n"
            }
            
            if let matchMethod = segment.metadata["match_method"] as? String {
                details += "• Match Method: \(matchMethod == "gpt_embedding" ? "🤖 GPT Embedding" : "🔄 Fallback Match")\n"
            }
            
            if let similarity = segment.metadata["embedding_similarity"] as? Float {
                details += "• Similarity: \(String(format: "%.3f", similarity))\n"
            }
            
            details += "\n"
        }
        
        // Add cache statistics
        let cacheStats = hapticLibrary.getCacheStats()
        details += "📦 Cache Statistics:\n"
        details += "• Cache Status: \(cacheStats.isValid ? "✅ Valid" : "❌ Invalid")\n"
        details += "• Pattern Count: \(cacheStats.patternCount)\n"
        details += "• Match Count: \(cacheStats.matchCount)\n"
        if let lastUpdate = cacheStats.lastUpdate {
            details += "• Last Update: \(lastUpdate.formatted())\n"
        }
        
        let alert = UIAlertController(title: "GPT Embedding Match Details", message: details, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - Analysis Methods
    
    /// Test image detection before GPT analysis
    private func testImageDetection(from url: URL) async {
        do {
            print("🧪 Starting unified image test pipeline for: \(url.lastPathComponent)")
            
            // Extract content using the same method as GPT pipeline
            print("🔄 Extracting content from PDF...")
            let content = try await PDFAnalysisManager.shared.extractContentForTesting(from: url)
            
            print("✅ Content extraction completed")
            print("📊 Extracted content:")
            print("   - Text pages: \(content.textContent.count)")
            print("   - Text positions: \(content.textPositions.map { $0.count })")
            print("   - Images: \(content.imageRegions.count)")
            print("   - Total pages: \(content.pageCount)")
            
            // Create fake ImageEmotionRegions for testing (simulate GPT analysis)
            let testImageRegions = content.imageRegions.map { imageRegion in
                return ImageEmotionRegion(
                    imageData: imageRegion.image.jpegData(compressionQuality: 0.8),
                    boundingBox: imageRegion.boundingBox,
                    emotion: generateRandomEmotion(), // Random emotion for testing
                    confidence: Float.random(in: 0.7...0.95),
                    description: "Test image: \(imageRegion.description)",
                    visualElements: ["test_element_1", "test_element_2"],
                    pageIndex: imageRegion.pageIndex
                )
            }
            
            // Create fake analysis result (simulate GPT result)
            let testAnalysisResult = PDFAnalysisResult(
                mode: .imageOnly,
                textRegions: [],
                imageRegions: testImageRegions,
                analysisTimestamp: Date(),
                processingTime: 0.0
            )
            
            print("🧪 Created test analysis result with \(testImageRegions.count) image regions")
            
            // Use the SAME displayAnalysisResults method as GPT pipeline
            DispatchQueue.main.async {
                self.displayAnalysisResults(testAnalysisResult)
            }
            
        } catch {
            print("❌ Unified image test failed: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            
            let errorMessage = """
            Unified Image Test Failed
            
            Error: \(error.localizedDescription)
            
            Possible causes:
            • PDF file is corrupted or empty
            • PDF file is password protected
            • PDF file contains no images
            • File access permissions issue
            
            Please try:
            • Using a different PDF file
            • Ensuring the PDF contains images
            • Checking file permissions
            """
            
            showAlert(title: "Unified Image Test Failed", message: errorMessage)
        }
    }
    
    // Note: displayImageRegionsOnCurrentPage removed - now using unified displayAnalysisResults pipeline
    
    // Note: displayTextRegionsOnCurrentPage removed - now using unified displayAnalysisResults pipeline
    
    // Note: saveDetectedImageRegions removed - now using unified displayAnalysisResults pipeline
    
    // Note: saveDetectedTextPositions removed - now using unified displayAnalysisResults pipeline
    
    // Note: showImageDetectionSummary removed - now using unified displayAnalysisResults pipeline
    
    /// Continue with actual GPT analysis
    private func continueWithImageAnalysis(_ imageRegions: [ImageRegion]) {
        // Convert ImageRegion to ImageEmotionRegion for analysis
        let emotionRegions = imageRegions.map { imageRegion in
            return ImageEmotionRegion(
                boundingBox: imageRegion.boundingBox,
                emotion: "neutral", // Will be filled by GPT
                confidence: 0.5,
                description: "Image analysis pending",
                visualElements: [],
                pageIndex: imageRegion.pageIndex
            )
        }
        
        // Continue with normal analysis flow
        let result = PDFAnalysisResult(
            mode: .imageOnly,
            textRegions: [],
            imageRegions: emotionRegions,
            analysisTimestamp: Date(),
            processingTime: 0.0
        )
        
        displayAnalysisResults(result)
    }
    
    /// Test text highlighting using unified search mechanism
    private func testTextHighlighting() async {
        print("📝 Starting unified text highlighting test...")
        
        // Generate random test text segments
        let testTextSegments = generateRandomTextSegmentsForTesting()
        
        if testTextSegments.isEmpty {
            showAlert(title: "No Text Found", message: "No suitable text content found for testing.")
            return
        }
        
        // Use unified search mechanism for test segments
        print("🧪 Processing \(testTextSegments.count) test text segments using unified search")
        let testContentSegments = searchAndCreateTextSegments(testTextSegments, isTestMode: true)
        
        if testContentSegments.isEmpty {
            showAlert(title: "Search Failed", message: "Could not find positions for test text segments.")
            return
        }
        
        // Update UI on main thread
        DispatchQueue.main.async {
            // Store test segments
            self.allEmotionSegments = testContentSegments
            self.selectedContentSegments = testContentSegments
            
            // Update current page display
            self.updateEmotionRegionsForCurrentPage()
            self.updateUI()
            
            // Show summary with detailed information
            let foundSegments = testContentSegments.count
            let totalSegments = testTextSegments.count
            let successRate = foundSegments > 0 ? (Float(foundSegments) / Float(totalSegments) * 100) : 0
            
            // Build detailed summary with found text segments
            var             detailedSummary = """
            🧪 Unified Text Highlighting Test Complete!
            
            📊 Test Results:
            • Generated Test Segments: \(totalSegments)
            • Successfully Found Positions: \(foundSegments)
            • Success Rate: \(String(format: "%.1f", successRate))%
            
            """
            
            // Add details about found segments
            if !testContentSegments.isEmpty {
                detailedSummary += "🔍 Found Test Segments:\n"
                for (index, segment) in testContentSegments.enumerated() {
                    let pageIndex = segment.metadata["page_index"] as? Int ?? 0
                    let searchMethod = segment.metadata["search_method"] as? String ?? "unknown"
                    let searchQuality = segment.metadata["search_quality"] as? Float ?? 0.0
                    
                    detailedSummary += """
                    
                    📄 Segment \(index + 1) (Page \(pageIndex + 1)):
                    📝 Original Text: "\(segment.content)"
                    🎭 Emotion: \(segment.emotion ?? "unknown")
                    🔍 Search Method: \(searchMethod)
                    📊 Match Quality: \(String(format: "%.2f", searchQuality))
                    """
                }
            }
            
            detailedSummary += """
            
            
            🎯 Verification Instructions:
            • Each segment is original text extracted directly from the PDF
            • Highlighted areas should precisely match actual text positions in the PDF
            • Switch pages to see test segments on different pages
            • Use Apple Pencil to touch highlighted areas to test haptic feedback
            """
            
            self.showAlert(title: "Unified Text Highlighting Test Complete", message: detailedSummary)
        }
    }
    
    /// Extract text positions from a PDF page using PDFKit's precise selection
    private func extractTextPositionsFromPage(_ page: PDFPage) -> [TextPosition] {
        var textPositions: [TextPosition] = []
        
        // Get page bounds
        let pageBounds = page.bounds(for: .mediaBox)
        
        // Method 1: Use PDFKit's precise text selection with character-level accuracy
        if let pageText = page.string, !pageText.isEmpty {
            // Split text into meaningful chunks (sentences or paragraphs)
            let sentences = pageText.components(separatedBy: [".", "!", "?"]).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            
            for sentence in sentences.prefix(5) { // Limit to first 5 sentences
                let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedSentence.count > 10 { // Only sentences with meaningful length
                    
                    // Use PDFKit's precise selection
                    if let selections = page.document?.findString(trimmedSentence, withOptions: []) {
                        for selection in selections {
                            if let selectionPage = selection.pages.first {
                                // Get the precise bounds for this selection
                                let bounds = selection.bounds(for: selectionPage)
                                
                                print("🔍 Raw PDF bounds for '\(trimmedSentence.prefix(30))...': \(bounds)")
                                print("📄 Page bounds: \(pageBounds)")
                                
                                        // Convert PDF coordinates to UI coordinates using PDFKit's conversion
        let uiBounds = convertPDFBoundsToUI(bounds, pageBounds: pageBounds, page: page)
        
        print("🎯 Final UI bounds for text: '\(trimmedSentence.prefix(30))...'")
        print("🎯 UI bounds: \(uiBounds)")
                                
                                let textPosition = TextPosition(
                                    text: trimmedSentence,
                                    boundingBox: uiBounds,
                                    confidence: 0.9
                                )
                                textPositions.append(textPosition)
                                print("📝 Found precise text position: '\(trimmedSentence.prefix(30))...' at \(uiBounds)")
                            }
                        }
                    }
                }
            }
        }
        
        // Method 2: If no sentences found, try individual words with precise selection
        if textPositions.isEmpty {
            if let pageText = page.string, !pageText.isEmpty {
                let words = pageText.components(separatedBy: .whitespacesAndNewlines).filter { $0.count > 3 }
                
                for word in words.prefix(10) {
                    if let selections = page.document?.findString(word, withOptions: []) {
                        for selection in selections {
                            if let selectionPage = selection.pages.first {
                                let bounds = selection.bounds(for: selectionPage)
                                let uiBounds = convertPDFBoundsToUI(bounds, pageBounds: pageBounds, page: page)
                                
                                let textPosition = TextPosition(
                                    text: word,
                                    boundingBox: uiBounds,
                                    confidence: 0.8
                                )
                                textPositions.append(textPosition)
                                print("📝 Found precise word position: '\(word)' at \(uiBounds)")
                            }
                        }
                    }
                }
            }
        }
        
        // Method 3: Fallback - create a simple text position for the entire page
        if textPositions.isEmpty {
            let pageText = page.string ?? ""
            if !pageText.isEmpty {
                let textPosition = TextPosition(
                    text: pageText,
                    boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
                    confidence: 0.5
                )
                textPositions.append(textPosition)
                print("📝 Fallback: Using entire page text")
            }
        }
        
        return textPositions
    }
    
    /// Convert PDF bounds to UI coordinates using PDFKit's conversion
    private func convertPDFBoundsToUI(_ pdfBounds: CGRect, pageBounds: CGRect, page: PDFPage) -> CGRect {
        // Use PDFKit's convert method for accurate coordinate conversion
        let convertedBounds = pdfView.convert(pdfBounds, from: page)
        
        // Get the view bounds
        let viewBounds = pdfView.bounds
        
        // Convert to normalized coordinates (0-1 range)
        let normalizedBounds = CGRect(
            x: convertedBounds.origin.x / viewBounds.width,
            y: convertedBounds.origin.y / viewBounds.height,
            width: convertedBounds.width / viewBounds.width,
            height: convertedBounds.height / viewBounds.height
        )
        
        print("🔍 PDF bounds: \(pdfBounds)")
        print("🔍 Converted bounds: \(convertedBounds)")
        print("🔍 View bounds: \(viewBounds)")
        print("🔍 Normalized bounds: \(normalizedBounds)")
        
        // FIX: Flip Y coordinate for PDF to UI conversion
        // PDF uses bottom-up Y axis, UI uses top-down Y axis
        let flippedBounds = CGRect(
            x: normalizedBounds.origin.x,
            y: 1.0 - (normalizedBounds.origin.y + normalizedBounds.height),
            width: normalizedBounds.width,
            height: normalizedBounds.height
        )
        
        print("🔍 Flipped bounds: \(flippedBounds)")
        
        // Clamp bounds to valid range
        let clampedBounds = CGRect(
            x: max(0, min(1, flippedBounds.origin.x)),
            y: max(0, min(1, flippedBounds.origin.y)),
            width: max(0, min(1, flippedBounds.width)),
            height: max(0, min(1, flippedBounds.height))
        )
        
        print("🔍 Final clamped bounds: \(clampedBounds)")
        
        return clampedBounds
    }
    
    // MARK: - Unified Text Search and Highlighting System
    
    /// Unified text search and highlighting method - used by both GPT and test pipelines
    /// - Parameters:
    ///   - textSegments: Array of text segments with emotion data
    ///   - isTestMode: Whether this is for testing (affects metadata)
    /// - Returns: Array of ContentSegments with precise positions
    private func searchAndCreateTextSegments(_ textSegments: [(text: String, emotion: String, confidence: Float, reasoning: String)], isTestMode: Bool = false) -> [ContentSegment] {
        var contentSegments: [ContentSegment] = []
        
        print("Starting unified text search for \(textSegments.count) text segments")
        
        for (index, textSegment) in textSegments.enumerated() {
            print("Searching for text \(index + 1): '\(textSegment.text.prefix(50))...'")
            
            // Search for this text across all pages
            if let foundPosition = searchTextAcrossAllPages(textSegment.text) {
                print("Found text on page \(foundPosition.pageIndex + 1)")
                
                // Get haptic pattern for this emotion
                let hapticPattern = hapticLibrary.getRecommendedPattern(
                    for: .text,
                    emotion: textSegment.emotion,
                    scene: nil
                )
                
                // Create content segment
                let segment = ContentSegment(
                    content: textSegment.text,
                    contentType: .text,
                    rect: foundPosition.boundingBox,
                    emotion: textSegment.emotion,
                    scene: nil,
                    hapticPattern: hapticPattern,
                    metadata: [
                        "page_index": foundPosition.pageIndex,
                        "confidence": textSegment.confidence,
                        "reasoning": textSegment.reasoning,
                        "search_quality": foundPosition.quality,
                        "search_method": foundPosition.method,
                        "test_mode": isTestMode,
                        "segment_index": index
                    ]
                )
                
                contentSegments.append(segment)
                print("Created content segment \(index + 1) for page \(foundPosition.pageIndex + 1)")
            } else {
                print("Could not find position for text: '\(textSegment.text.prefix(50))...'")
            }
        }
        
        print("Text search completed: \(contentSegments.count)/\(textSegments.count) segments found")
        return contentSegments
    }
    
    /// Search for text across all pages of the PDF
    /// - Parameter searchText: The text to search for
    /// - Returns: Found position with page index, bounding box, and quality score
    private func searchTextAcrossAllPages(_ searchText: String) -> (pageIndex: Int, boundingBox: CGRect, quality: Float, method: String)? {
        guard let document = pdfView.document else { return nil }
        
        let cleanSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var bestMatch: (pageIndex: Int, boundingBox: CGRect, quality: Float, method: String)?
        var bestQuality: Float = 0.0
        
        print("🔍 Searching for text across \(document.pageCount) pages: '\(cleanSearchText.prefix(30))...'")
        
        // Search each page
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            // Method 1: Try exact PDFKit search first (highest accuracy)
            if let exactMatch = searchTextInPageWithPDFKit(cleanSearchText, page: page, pageIndex: pageIndex) {
                if exactMatch.quality > bestQuality {
                    bestQuality = exactMatch.quality
                    bestMatch = exactMatch
                    print("✅ Found exact match on page \(pageIndex + 1) with quality \(exactMatch.quality)")
                }
            }
            
            // Method 2: Try fuzzy search if exact search didn't find good match
            if bestQuality < 0.8 {
                if let fuzzyMatch = searchTextInPageFuzzy(cleanSearchText, page: page, pageIndex: pageIndex) {
                    if fuzzyMatch.quality > bestQuality {
                        bestQuality = fuzzyMatch.quality
                        bestMatch = fuzzyMatch
                        print("✅ Found fuzzy match on page \(pageIndex + 1) with quality \(fuzzyMatch.quality)")
                    }
                }
            }
        }
        
        if let match = bestMatch {
            print("🎯 Best match found on page \(match.pageIndex + 1) using \(match.method) (quality: \(String(format: "%.2f", match.quality)))")
            return match
        } else {
            print("❌ No match found for text: '\(cleanSearchText.prefix(30))...'")
            return nil
        }
    }
    
    /// Search text in a specific page using PDFKit's native search (most accurate)
    private func searchTextInPageWithPDFKit(_ searchText: String, page: PDFPage, pageIndex: Int) -> (pageIndex: Int, boundingBox: CGRect, quality: Float, method: String)? {
        
        // Use PDFKit's native search for exact matches
        if let selections = page.document?.findString(searchText, withOptions: [.caseInsensitive]) {
            for selection in selections {
                if let selectionPage = selection.pages.first, selectionPage == page {
                    let pdfBounds = selection.bounds(for: page)
                    let pageBounds = page.bounds(for: .mediaBox)
                    
                    // Convert to UI coordinates
                    let uiBounds = convertPDFBoundsToUI(pdfBounds, pageBounds: pageBounds, page: page)
                    
                    print("📐 PDFKit exact match: PDF bounds \(pdfBounds) → UI bounds \(uiBounds)")
                    
                    return (pageIndex: pageIndex, boundingBox: uiBounds, quality: 1.0, method: "PDFKit_exact")
                }
            }
        }
        
        // Try searching for partial matches (first 50 characters)
        if searchText.count > 50 {
            let partialText = String(searchText.prefix(50))
            if let selections = page.document?.findString(partialText, withOptions: [.caseInsensitive]) {
                for selection in selections {
                    if let selectionPage = selection.pages.first, selectionPage == page {
                        let pdfBounds = selection.bounds(for: page)
                        let pageBounds = page.bounds(for: .mediaBox)
                        let uiBounds = convertPDFBoundsToUI(pdfBounds, pageBounds: pageBounds, page: page)
                        
                        print("📐 PDFKit partial match: PDF bounds \(pdfBounds) → UI bounds \(uiBounds)")
                        
                        return (pageIndex: pageIndex, boundingBox: uiBounds, quality: 0.8, method: "PDFKit_partial")
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Search text using fuzzy matching (fallback method)
    private func searchTextInPageFuzzy(_ searchText: String, page: PDFPage, pageIndex: Int) -> (pageIndex: Int, boundingBox: CGRect, quality: Float, method: String)? {
        guard let pageText = page.string else { return nil }
        
        // Try to find the text using string similarity
        let searchWords = searchText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let pageWords = pageText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        // Look for sequences of words that match
        for i in 0..<pageWords.count {
            let endIndex = min(i + searchWords.count, pageWords.count)
            let pageSequence = Array(pageWords[i..<endIndex])
            
            // Calculate similarity
            let similarity = calculateTextSimilarity(searchWords, pageSequence)
            
            if similarity > 0.6 { // Threshold for fuzzy match
                // Try to find the position of this sequence
                let sequenceText = pageSequence.joined(separator: " ")
                if let selections = page.document?.findString(sequenceText, withOptions: [.caseInsensitive]) {
                    for selection in selections {
                        if let selectionPage = selection.pages.first, selectionPage == page {
                            let pdfBounds = selection.bounds(for: page)
                            let pageBounds = page.bounds(for: .mediaBox)
                            let uiBounds = convertPDFBoundsToUI(pdfBounds, pageBounds: pageBounds, page: page)
                            
                            print("📐 Fuzzy match: similarity \(similarity), PDF bounds \(pdfBounds) → UI bounds \(uiBounds)")
                            
                            return (pageIndex: pageIndex, boundingBox: uiBounds, quality: similarity, method: "fuzzy_similarity")
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Calculate similarity between two arrays of words
    private func calculateTextSimilarity(_ words1: [String], _ words2: [String]) -> Float {
        let set1 = Set(words1.map { $0.lowercased() })
        let set2 = Set(words2.map { $0.lowercased() })
        
        let intersection = set1.intersection(set2)
        let union = set1.union(set2)
        
        return union.isEmpty ? 0.0 : Float(intersection.count) / Float(union.count)
    }
    
    /// Generate random text segments for testing (replaces current test logic)
    private func generateRandomTextSegmentsForTesting() -> [(text: String, emotion: String, confidence: Float, reasoning: String)] {
        guard let document = pdfView.document else { return [] }
        
        var testSegments: [(text: String, emotion: String, confidence: Float, reasoning: String)] = []
        let emotions = ["positive", "negative", "neutral", "excited", "calm"]
        
        print("🧪 Generating random text segments for testing...")
        
        // Generate page indices that are well distributed across the document
        let totalPages = document.pageCount
        let targetSegments = 3 // Only generate 3 segments for clarity
        var selectedPages: [Int] = []
        
        if totalPages <= 3 {
            // If document has 3 or fewer pages, use all pages
            selectedPages = Array(0..<totalPages)
        } else {
            // Distribute across the document: beginning, middle, end
            selectedPages = [
                0, // First page
                totalPages / 2, // Middle page
                min(totalPages - 1, totalPages * 3 / 4) // Near end page
            ]
        }
        
        print("🧪 Selected pages for testing: \(selectedPages.map { $0 + 1 }) out of \(totalPages) total pages")
        
        // Get text from selected pages
        for pageIndex in selectedPages {
            guard let page = document.page(at: pageIndex),
                  let pageText = page.string,
                  !pageText.isEmpty else { 
                print("⚠️ Page \(pageIndex + 1) has no text, skipping...")
                continue 
            }
            
            // Split into sentences with better filtering
            let sentences = pageText.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { sentence in
                    // Filter for good test sentences
                    let wordCount = sentence.components(separatedBy: .whitespaces).count
                    return wordCount >= 5 && wordCount <= 25 && // 5-25 words
                           sentence.count >= 30 && sentence.count <= 150 && // 30-150 characters
                           !sentence.contains("Figure") && // Avoid figure captions
                           !sentence.contains("Table") && // Avoid table captions
                           !sentence.contains("http") && // Avoid URLs
                           sentence.rangeOfCharacter(from: .letters) != nil // Must contain letters
                }
            
            // Pick a random sentence from this page
            if let randomSentence = sentences.randomElement() {
                let randomEmotion = emotions.randomElement() ?? "neutral"
                let testSegment = (
                    text: randomSentence,
                    emotion: randomEmotion,
                    confidence: Float.random(in: 0.7...0.95),
                    reasoning: "Test segment generated from page \(pageIndex + 1)"
                )
                testSegments.append(testSegment)
                
                print("📄 Page \(pageIndex + 1) test segment:")
                print("   📝 Original text: '\(randomSentence)'")
                print("   🎭 Assigned emotion: \(randomEmotion)")
                print("   📊 Text length: \(randomSentence.count) characters")
                print("   📊 Word count: \(randomSentence.components(separatedBy: .whitespaces).count) words")
                print("   ─────────────────────────────────────")
            } else {
                print("⚠️ No suitable sentences found on page \(pageIndex + 1)")
            }
        }
        
        print("🧪 Generated \(testSegments.count) test segments from \(selectedPages.count) pages")
        return testSegments
    }
    
    // MARK: - Test Helper Methods
    
    /// Generate random emotion for testing
    private func generateRandomEmotion() -> String {
        let emotions = [
            "joyful", "melancholic", "thrilling", "serene", "nostalgic", 
            "tense", "uplifting", "mysterious", "peaceful", "energetic",
            "contemplative", "dramatic", "whimsical", "somber", "inspiring"
        ]
        return emotions.randomElement() ?? "neutral"
    }
}

// MARK: - UIDocumentPickerDelegate
extension MainViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        print("📄 Selected PDF: \(url.lastPathComponent)")
        
        guard url.startAccessingSecurityScopedResource() else { 
            showAlert(title: "Access Error", message: "Unable to access the selected PDF file")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            title = "📄 \(url.lastPathComponent)"
            print("✅ Successfully loaded PDF: \(url.lastPathComponent)")
            print("📊 PDF has \(document.pageCount) pages")
            
            // Clear previous emotion regions
            allEmotionSegments.removeAll()
            selectedContentSegments.removeAll()
            contentSelectionView.clearSelections()
            
            // Update page controls immediately and then again after a delay
            updatePageControls()
            
            // Update page controls after a short delay to ensure PDFView is fully ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.updatePageControls()
                self.debugPDFViewState()
                print("🔄 Delayed page controls update completed")
            }
            
            // Show simple import success message
            showAlert(title: "PDF Import Successful", message: "Document loaded successfully. You can now click 'Analyze PDF' to analyze the PDF content, or manually select content areas and configure haptic feedback.")
        } else {
            print("❌ Failed to load PDF: \(url.lastPathComponent)")
            showAlert(title: "PDF Loading Failed", message: "Unable to load the selected PDF file. Please ensure the file format is correct and not corrupted.")
        }
    }
}

// MARK: - UIImagePickerControllerDelegate
extension MainViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = info[.originalImage] as? UIImage {
            imageView.image = image
            title = "🖼️ Image Loaded"
            print("🖼️ Loaded image")
        }
        picker.dismiss(animated: true)
    }
}

// MARK: - HapticContentSelectionDelegate
extension MainViewController: HapticContentSelectionDelegate {
    func didSelectContent(_ content: String, in rect: CGRect, contentType: ContentType) {
        // Create simple content segment without emotion analysis
        let segment = ContentSegment(
            content: content,
            contentType: contentType,
            rect: rect,
            emotion: nil, // No emotion analysis for now
            scene: nil,   // No scene analysis for now
            hapticPattern: nil // Set to nil for now, wait for user selection
        )
        
        selectedContentSegments.append(segment)
        updateUI()
        
        print("✅ Selected \(contentType.displayName): \(content.prefix(50))...")
        
        // Show simple haptic pattern selection interface
        showSimpleHapticPatternSelection(for: segment, at: selectedContentSegments.count - 1)
    }
    
    /// Show simple haptic pattern selection interface
    private func showSimpleHapticPatternSelection(for segment: ContentSegment, at index: Int) {
        let alert = UIAlertController(
            title: "Select Haptic Pattern",
            message: "Choose haptic feedback pattern for \(segment.contentType.displayName) content:",
            preferredStyle: .actionSheet
        )
        
        // Get available haptic patterns
        let availablePatterns = hapticLibrary.getAllPatterns().filter { pattern in
            pattern.contentTypes.contains(segment.contentType)
        }
        
        if availablePatterns.isEmpty {
            alert.message = "No haptic patterns found for \(segment.contentType.displayName)"
            alert.addAction(UIAlertAction(title: "OK", style: .default))
        } else {
            // Show available patterns
            for pattern in availablePatterns {
                alert.addAction(UIAlertAction(title: "📳 \(pattern.name)", style: .default) { _ in
                    self.selectedContentSegments[index].hapticPattern = pattern
                    self.updateUI()
                    print("✅ Selected pattern for \(segment.contentType.displayName): \(pattern.name)")
                })
            }
        }
        
        alert.addAction(UIAlertAction(title: "Skip", style: .cancel))
        presentAlert(alert)
    }
}

// MARK: - BLEControllerDelegate
extension MainViewController: BLEControllerDelegate {
    func bleControllerDidConnect() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let label = self.controlPanel.viewWithTag(100) as? UILabel {
                label.text = "MagicPen: Connected ✅"
                label.textColor = .systemGreen
            }
            
            // Configure haptic library with BLE controller
            self.hapticLibrary.configureBleController(self.bleController)
            
            print("🎉 MagicPen Connected")
        }
    }
    
    func bleControllerDidDisconnect() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let label = self.controlPanel.viewWithTag(100) as? UILabel {
                label.text = "MagicPen: Not Connected ❌"
                label.textColor = .systemRed
            }
            
            print("📱 MagicPen Disconnected")
        }
    }
    
    func bleControllerDidUpdatePenPosition(_ position: CGPoint) {
        // Pass pen position to haptic processing logic
        handlePenPosition(position)
        print("Pen position updated: (\(position.x), \(position.y))")
    }
} 