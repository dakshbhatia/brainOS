import Foundation
import HealthKit

@MainActor
public class BrainHealthManager {
    public static let shared = BrainHealthManager()
    
    private let healthStore = HKHealthStore()
    
    private init() {}
    
    public func requestPermissions() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "BrainHealthManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device"])
        }
        
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        
        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
    }
    
    public func fetchStepCount(days: Int = 7) async throws -> [Double] {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: DateComponents(day: 1)
            )
            
            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                var steps: [Double] = []
                results?.enumerateStatistics(from: startDate, to: now) { statistics, _ in
                    let sum = statistics.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                    steps.append(sum)
                }
                continuation.resume(returning: steps)
            }
            
            healthStore.execute(query)
        }
    }
}
