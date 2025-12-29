import Foundation
import AppKit
import Vision

/// Monitors the Desktop for new screenshots and ingests them into semantic memory.
@MainActor
public class ScreenshotWatcherService {
    public static let shared = ScreenshotWatcherService()
    
    private var query: NSMetadataQuery?
    private let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    
    private init() {}
    
    public func start() {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == YES")
        query.searchScopes = [desktopURL]
        
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.processQueryUpdates()
            }
        }
        
        query.start()
        self.query = query
        BrainLogger.info("Screenshot watcher started on Desktop", category: .knowledge)
    }
    
    private func processQueryUpdates() async {
        guard let query = self.query else { return }
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: kMDItemPath as String) as? String,
                  let date = item.value(forAttribute: kMDItemContentCreationDate as String) as? Date else {
                continue
            }
            
            // Only process if it's new (within last 5 minutes)
            if abs(date.timeIntervalSinceNow) < 300 {
                await ingestScreenshot(at: URL(fileURLWithPath: path))
            }
        }
    }
    
    private func ingestScreenshot(at url: URL) async {
        BrainLogger.info("Ingesting new screenshot: \(url.lastPathComponent)", category: .knowledge)
        
        // Check if vision model is available
        let hasVisionModel = await BrainVisionManager.shared.isAvailable()
        
        if !hasVisionModel {
            // Attempt to load vision model if not already loaded
            await BrainVisionManager.shared.loadModel()
        }
        
        // 1. Perform OCR using Vision framework
        let requestHandler = VNImageRequestHandler(url: url)
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            
            Task { @MainActor in
                // 2. Get Visual Description from VLM (if available)
                let hasVision = await BrainVisionManager.shared.isAvailable()
                let visualDescription: String
                
                if hasVision {
                    visualDescription = await BrainVisionManager.shared.describeImage(at: url)
                } else {
                    visualDescription = "[Vision analysis unavailable - no vision model installed]"
                    BrainLogger.info("Screenshot ingested without vision analysis (no model)", category: .knowledge)
                }
                
                let fullContent = """
                Screenshot OCR: \(recognizedText)
                Visual Description: \(visualDescription)
                """
                
                // Publish to Event Bus for cross-vital correlation
                LifeEventBus.shared.publish(.screenshotCaptured(url: url, ocrText: recognizedText))
                
                await BrainKnowledgeManager.shared.addMemory(
                    text: fullContent,
                    metadata: [
                        "source": "screenshot",
                        "path": url.path,
                        "timestamp": Date().description,
                        "has_vision_analysis": hasVision ? "true" : "false"
                    ]
                )
            }
        }
        
        try? requestHandler.perform([request])
    }
}
