import Foundation
import LinkPresentation

/// Manages extraction of metadata from URLs to provide "clean" links.
public actor LinkMetadataManager {
    public static let shared = LinkMetadataManager()
    
    private var cache: [URL: String] = [:]
    
    private init() {}
    
    /// Extract a human-readable title for a URL
    /// Returns the host or a "dirty" URL fallback if metadata extraction fails
    public func getTitle(for urlString: String) async -> String {
        guard let url = URL(string: urlString) else { return urlString }
        
        if let cached = cache[url] {
            return cached
        }
        
        let provider = LPMetadataProvider()
        // Shorter timeout for responsiveness
        provider.timeout = 5.0
        
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            let title = metadata.title ?? url.host ?? urlString
            cache[url] = title
            return title
        } catch {
            BrainLogger.debug("Failed to fetch metadata for \(urlString): \(error)", category: .core)
            let fallback = url.host ?? urlString
            return fallback
        }
    }
    
    /// Identify if a string contains a link
    public func extractLinks(from text: String) -> [String] {
        let types: NSTextCheckingResult.CheckingType = .link
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return [] }
        let matches = detector.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { $0.url?.absoluteString }
    }
}
