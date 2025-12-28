import Foundation
import AppKit
import Vision

/// Monitors the Desktop for new screenshots and ingests them into semantic memory.
public actor ScreenshotWatcherService {
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
        ) { [weak self] notification in
            Task {
                await self?.processQueryUpdates(query)
            }
        }
        
        query.start()
        self.query = query
        BrainLogger.info("Screenshot watcher started on Desktop", category: .knowledge)
    }
    
    private func processQueryUpdates(_ query: NSMetadataQuery) async {
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
        
        // 1. Perform OCR using Vision framework
        let requestHandler = VNImageRequestHandler(url: url)
        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            
            Task {
                // 2. Get Visual Description from VLM
                let visualDescription = await BrainVisionManager.shared.describeImage(at: url)
                
                let fullContent = """
                Screenshot OCR: \(recognizedText)
                Visual Description: \(visualDescription)
                """
                
                await BrainKnowledgeManager.shared.addMemory(
                    text: fullContent,
                    metadata: [
                        "source": "screenshot",
                        "path": url.path,
                        "timestamp": Date().description
                    ]
                )
            }
        }
        
        try? requestHandler.perform([request])
    }
}
