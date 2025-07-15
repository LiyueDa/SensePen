import UIKit
import PDFKit

// MARK: - Granularity Test View Controller
class GranularityTestViewController: UIViewController {
    
    // MARK: - UI Components
    private var pdfView: PDFView!
    private var granularitySegment: UISegmentedControl!
    private var modeSegment: UISegmentedControl!
    private var modeLabel: UILabel!
    private var granularityLabel: UILabel!
    private var loadButton: UIButton!
    private var analyzeButton: UIButton!
    private var resultTextView: UITextView!
    private var progressView: UIProgressView!
    private var statusLabel: UILabel!
    
    // MARK: - Properties
    private var pdfURL: URL?
    private let analysisManager = PDFAnalysisManager.shared
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "Granularity Analysis Test"
        
        // PDF View
        pdfView = PDFView()
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        view.addSubview(pdfView)
        
        // Mode Selection
        modeLabel = UILabel()
        modeLabel.text = "Analysis Mode:"
        modeLabel.font = .systemFont(ofSize: 16, weight: .medium)
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeLabel)
        
        modeSegment = UISegmentedControl(items: PDFAnalysisMode.allCases.map { "\($0.icon) \($0.displayName)" })
        modeSegment.selectedSegmentIndex = 0
        modeSegment.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeSegment)
        
        // Granularity Selection
        granularityLabel = UILabel()
        granularityLabel.text = "Text Granularity:"
        granularityLabel.font = .systemFont(ofSize: 16, weight: .medium)
        granularityLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(granularityLabel)
        
        granularitySegment = UISegmentedControl(items: TextGranularityLevel.allCases.map { "\($0.icon) \($0.displayName)" })
        granularitySegment.selectedSegmentIndex = 1 // Default to sentence
        granularitySegment.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(granularitySegment)
        
        // Analyze Button
        analyzeButton = UIButton(type: .system)
        analyzeButton.setTitle("Analyze PDF", for: .normal)
        analyzeButton.backgroundColor = .systemBlue
        analyzeButton.setTitleColor(.white, for: .normal)
        analyzeButton.layer.cornerRadius = 8
        analyzeButton.addTarget(self, action: #selector(analyzeButtonTapped), for: .touchUpInside)
        analyzeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(analyzeButton)
        
        // Load PDF Button
        loadButton = UIButton(type: .system)
        loadButton.setTitle("Load PDF", for: .normal)
        loadButton.backgroundColor = .systemGreen
        loadButton.setTitleColor(.white, for: .normal)
        loadButton.layer.cornerRadius = 8
        loadButton.addTarget(self, action: #selector(loadPDFButtonTapped), for: .touchUpInside)
        loadButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadButton)
        
        // Progress View
        progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.isHidden = true
        view.addSubview(progressView)
        
        // Status Label
        statusLabel = UILabel()
        statusLabel.text = "Ready to analyze"
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .systemGray
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        
        // Result Text View
        resultTextView = UITextView()
        resultTextView.translatesAutoresizingMaskIntoConstraints = false
        resultTextView.font = .systemFont(ofSize: 12)
        resultTextView.isEditable = false
        resultTextView.backgroundColor = .systemGray6
        resultTextView.layer.cornerRadius = 8
        resultTextView.text = "Analysis results will appear here..."
        view.addSubview(resultTextView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Mode Label
            modeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            modeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            // Mode Segment
            modeSegment.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 8),
            modeSegment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            modeSegment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Granularity Label
            granularityLabel.topAnchor.constraint(equalTo: modeSegment.bottomAnchor, constant: 16),
            granularityLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            // Granularity Segment
            granularitySegment.topAnchor.constraint(equalTo: granularityLabel.bottomAnchor, constant: 8),
            granularitySegment.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            granularitySegment.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Load PDF Button
            loadButton.topAnchor.constraint(equalTo: granularitySegment.bottomAnchor, constant: 16),
            loadButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            loadButton.widthAnchor.constraint(equalToConstant: 100),
            loadButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Analyze Button
            analyzeButton.topAnchor.constraint(equalTo: granularitySegment.bottomAnchor, constant: 16),
            analyzeButton.leadingAnchor.constraint(equalTo: loadButton.trailingAnchor, constant: 16),
            analyzeButton.widthAnchor.constraint(equalToConstant: 120),
            analyzeButton.heightAnchor.constraint(equalToConstant: 40),
            
            // Progress View
            progressView.topAnchor.constraint(equalTo: analyzeButton.bottomAnchor, constant: 16),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Status Label
            statusLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // PDF View
            pdfView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            pdfView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.4),
            
            // Result Text View
            resultTextView.topAnchor.constraint(equalTo: pdfView.bottomAnchor, constant: 16),
            resultTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            resultTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            resultTextView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }
    
    // MARK: - Actions
    @objc private func loadPDFButtonTapped() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf])
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }
    
    @objc private func analyzeButtonTapped() {
        guard let pdfURL = pdfURL else {
            showAlert(title: "No PDF Loaded", message: "Please load a PDF file first.")
            return
        }
        
        let mode = PDFAnalysisMode.allCases[modeSegment.selectedSegmentIndex]
        let granularity = TextGranularityLevel.allCases[granularitySegment.selectedSegmentIndex]
        
        // Only allow granularity for text modes
        if (mode == .imageOnly) && (granularity != .sentence) {
            showAlert(title: "Invalid Selection", message: "Text granularity only applies to text analysis modes.")
            return
        }
        
        startAnalysis(pdfURL: pdfURL, mode: mode, granularity: granularity)
    }
    
    // MARK: - Analysis
    private func startAnalysis(pdfURL: URL, mode: PDFAnalysisMode, granularity: TextGranularityLevel) {
        // Update UI
        analyzeButton.isEnabled = false
        progressView.isHidden = false
        progressView.progress = 0.0
        statusLabel.text = "Starting analysis..."
        resultTextView.text = "Analyzing..."
        
        Task {
            do {
                let result = try await analysisManager.analyzePDFWithGranularity(
                    from: pdfURL,
                    mode: mode,
                    granularity: granularity
                ) { progress in
                    DispatchQueue.main.async {
                        self.statusLabel.text = progress
                        self.progressView.progress += 0.1
                    }
                }
                
                // Display results
                DispatchQueue.main.async {
                    self.displayResults(result)
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.showAlert(title: "Analysis Failed", message: error.localizedDescription)
                    self.resetUI()
                }
            }
        }
    }
    
    private func displayResults(_ result: PDFAnalysisResult) {
        var resultText = "📊 Analysis Results\n"
        resultText += "==================\n\n"
        resultText += "Mode: \(result.mode.displayName)\n"
        resultText += "Processing Time: \(String(format: "%.2f", result.processingTime))s\n"
        resultText += "Total Regions: \(result.totalRegions)\n\n"
        
        // Text Regions
        if !result.textRegions.isEmpty {
            resultText += "📝 Text Regions (\(result.textRegions.count)):\n"
            resultText += "-------------------\n"
            
            for (index, region) in result.textRegions.enumerated() {
                resultText += "\(index + 1). \(region.granularityLevel.displayName)\n"
                resultText += "   Text: \"\(region.text.prefix(50))...\"\n"
                resultText += "   Emotion: \(region.emotion.capitalized)\n"
                resultText += "   Confidence: \(String(format: "%.2f", region.confidence))\n"
                resultText += "   Keywords: \(region.keywords.joined(separator: ", "))\n"
                resultText += "   Reasoning: \(region.reasoning.prefix(100))...\n"
                resultText += "   Position: (\(Int(region.boundingBox.origin.x)), \(Int(region.boundingBox.origin.y)))\n\n"
            }
        }
        
        // Image Regions
        if !result.imageRegions.isEmpty {
            resultText += "🖼️ Image Regions (\(result.imageRegions.count)):\n"
            resultText += "-------------------\n"
            
            for (index, region) in result.imageRegions.enumerated() {
                resultText += "\(index + 1). Image\n"
                resultText += "   Emotion: \(region.emotion.capitalized)\n"
                resultText += "   Confidence: \(String(format: "%.2f", region.confidence))\n"
                resultText += "   Description: \(region.description.prefix(100))...\n"
                resultText += "   Visual Elements: \(region.visualElements.joined(separator: ", "))\n\n"
            }
        }
        
        resultTextView.text = resultText
        statusLabel.text = "Analysis completed successfully"
        progressView.progress = 1.0
        analyzeButton.isEnabled = true
        
        // Generate haptic patterns
        let patterns = analysisManager.generateHapticPatterns(for: result)
        resultText += "\n🎯 Generated \(patterns.count) haptic patterns\n"
        resultTextView.text = resultText
    }
    
    private func resetUI() {
        analyzeButton.isEnabled = true
        progressView.isHidden = true
        statusLabel.text = "Ready to analyze"
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UIDocumentPickerDelegate
extension GranularityTestViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            pdfURL = url
            title = "📄 \(url.lastPathComponent)"
            statusLabel.text = "PDF loaded: \(url.lastPathComponent)"
            print("📄 Loaded PDF: \(url.lastPathComponent)")
        }
    }
} 