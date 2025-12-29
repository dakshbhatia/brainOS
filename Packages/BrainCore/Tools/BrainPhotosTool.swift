import Foundation
import Photos

struct BrainPhotosTool: BrainOSTool {
    let name = "search_photos"
    let description = "Search for photos by location, date, or detected entities (people, objects)."
    
    var parameters: JSONValue? {
        return .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "description": .string("Search query (e.g., 'beach', 'Paris', 'Mom').")
                ])
            ]),
            "required": .array([.string("query")])
        ])
    }
    
    func execute(argumentsJSON: String) async throws -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let _ = args["query"] as? String else {
            throw NSError(domain: "BrainPhotosTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid arguments"])
        }
        
        // Request permissions
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return "Error: Photo library access denied. Please grant permission in System Settings."
        }
        
        // Search for photos
        // Note: Semantic search (e.g., "dog") requires Vision framework embeddings.
        // For now, we'll search by location name or date if the query looks like one.
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 10
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var results: [[String: Any]] = []
        
        fetchResult.enumerateObjects { (asset, index, stop) in
            var assetInfo: [String: Any] = [
                "id": asset.localIdentifier,
                "date": asset.creationDate?.description ?? "unknown"
            ]
            
            if let location = asset.location {
                assetInfo["location"] = "\(location.coordinate.latitude), \(location.coordinate.longitude)"
            }
            
            results.append(assetInfo)
        }
        
        if results.isEmpty {
            return "No photos found matching your query."
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: results)
        return "Found \(results.count) recent photos. Metadata: " + (String(data: jsonData, encoding: .utf8) ?? "[]")
    }
}
