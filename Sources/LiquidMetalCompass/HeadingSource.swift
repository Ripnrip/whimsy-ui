//  HeadingSource.swift
//  LiquidMetalCompass
//
//  Where headings come from. The compass only needs "degrees from north, clockwise" on the
//  main actor, so the sensor sits behind a tiny protocol: Core Location's compass heading,
//  Core Motion's north-referenced attitude, or a manual source for previews and tests.

#if canImport(SwiftUI)
import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(CoreMotion)
import CoreMotion
#endif

/// Something that reports the device heading: degrees from north, clockwise, 0..<360.
@MainActor
public protocol HeadingSource: AnyObject {
    /// Whether this source can deliver headings on this device.
    var isAvailable: Bool { get }
    /// Starts delivering headings to `handler` (on the main actor) until ``stop()``.
    func start(_ handler: @escaping @MainActor (Double) -> Void)
    func stop()
}

/// A heading you set yourself: previews, tests, or your own sensor fusion.
@MainActor
public final class ManualHeadingSource: HeadingSource {
    private var handler: (@MainActor (Double) -> Void)?
    public private(set) var heading: Double
    public init(heading: Double = 0) { self.heading = heading }
    public var isAvailable: Bool { true }
    public func start(_ handler: @escaping @MainActor (Double) -> Void) {
        self.handler = handler
        handler(heading)
    }
    public func stop() { handler = nil }
    /// Publishes a new heading.
    public func send(_ degrees: Double) {
        heading = degrees
        handler?(degrees)
    }
}

#if canImport(CoreLocation) && os(iOS)
/// `CLLocationManager` compass heading. Uses true north when location access has been
/// granted (so declination is corrected) and magnetic north otherwise; heading updates
/// themselves need no permission.
@MainActor
public final class LocationHeadingSource: NSObject, HeadingSource, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var handler: (@MainActor (Double) -> Void)?

    /// - Parameter filter: minimum change (degrees) before a new heading is delivered.
    public init(filter: CLLocationDegrees = 1) {
        super.init()
        manager.delegate = self
        manager.headingFilter = filter
        manager.headingOrientation = .portrait
    }

    public var isAvailable: Bool { CLLocationManager.headingAvailable() }

    public func start(_ handler: @escaping @MainActor (Double) -> Void) {
        self.handler = handler
        manager.startUpdatingHeading()
    }

    public func stop() {
        manager.stopUpdatingHeading()
        handler = nil
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        // The manager was created on the main thread, so its delegate calls arrive there.
        MainActor.assumeIsolated { self.handler?(degrees) }
    }

    nonisolated public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }
}
#endif

#if canImport(CoreMotion) && os(iOS)
/// `CMMotionManager` device-motion heading (north-referenced attitude), at 60 Hz. Smoother
/// than the Core Location compass and fused with the gyro; prefers true north when the
/// device can provide it.
@MainActor
public final class MotionHeadingSource: HeadingSource {
    private let manager = CMMotionManager()

    public init(updateInterval: TimeInterval = 1.0 / 60) {
        manager.deviceMotionUpdateInterval = updateInterval
    }

    public var isAvailable: Bool {
        manager.isDeviceMotionAvailable
            && !CMMotionManager.availableAttitudeReferenceFrames()
                .intersection([.xTrueNorthZVertical, .xMagneticNorthZVertical]).isEmpty
    }

    public func start(_ handler: @escaping @MainActor (Double) -> Void) {
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical)
            ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        manager.startDeviceMotionUpdates(using: frame, to: .main) { motion, _ in
            guard let degrees = motion?.heading, degrees >= 0 else { return }
            MainActor.assumeIsolated { handler(degrees) }
        }
    }

    public func stop() { manager.stopDeviceMotionUpdates() }
}
#endif

/// Picks a sensor for this device, or nil (Mac, simulator, no magnetometer).
@MainActor
public enum HeadingSources {
    public static func automatic() -> (any HeadingSource)? {
        #if os(iOS) && !targetEnvironment(simulator)
        let motion = MotionHeadingSource()
        if motion.isAvailable { return motion }
        let location = LocationHeadingSource()
        if location.isAvailable { return location }
        #endif
        return nil
    }
}
#endif
