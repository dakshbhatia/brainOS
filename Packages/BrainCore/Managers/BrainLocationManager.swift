import Foundation
import CoreLocation

/// Periodically polls the user's location and logs it to the brain database.
@MainActor
public class BrainLocationManager: NSObject, CLLocationManagerDelegate {
    public static let shared = BrainLocationManager()
    
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 500 // Only log if moved 500m
    }
    
    public func start() {
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        Task { @MainActor in
            let geocoder = CLGeocoder()
            let placemarks = try? await geocoder.reverseGeocodeLocation(location)
            let address = placemarks?.first?.name ?? placemarks?.first?.locality
            
            await BrainDatabaseManager.shared.logLocation(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                address: address
            )
            
            BrainLogger.debug("Logged location: \(address ?? "Unknown")", category: .core)
        }
    }
}
