import Foundation

nonisolated enum DexterityAnalyzer {
    nonisolated static func analyze(_ trial: DexterityTrial) -> DexterityMetrics {
        let errors: [Double]?
        let pathInvalidReason: String?
        if !isCalculationValid(route: trial.route) {
            pathInvalidReason = "route is invalid"
            errors = nil
        } else if !trial.coordinateSpace.isCalculationValid {
            pathInvalidReason = "coordinate space is invalid"
            errors = nil
        } else {
            errors = pathErrors(from: trial)
            pathInvalidReason = errors == nil ? "path samples are invalid" : nil
        }

        let speeds = speedSamples(from: trial)
        let speedInvalidReason: String?
        if !trial.coordinateSpace.isCalculationValid {
            speedInvalidReason = "coordinate space is invalid"
        } else {
            speedInvalidReason = speeds == nil ? "speed samples are invalid" : nil
        }

        let speedStats = speeds.flatMap(SummaryStats.compute)
        let cv = coefficientOfVariation(from: speedStats)

        return DexterityMetrics(
            numSequences: trial.sequences.count,
            doneSequences: trial.sequences.filter(\.completed).count,
            liftCount: trial.sequences.filter(\.endedByLift).count,
            rmsError: errors.flatMap(rootMeanSquare),
            maxPointError: errors.flatMap { $0.max() },
            swipeSpeedStats: speedStats,
            cvSwipeSpeed: cv,
            pathInvalidReason: pathInvalidReason,
            speedInvalidReason: speedInvalidReason
        )
    }

    static func isCalculationValid(route: DexterityRoute) -> Bool {
        guard route.points.count >= 2, route.points.allSatisfy(\.hasFiniteCoordinates) else {
            return false
        }

        for index in 1..<route.points.count where route.points[index - 1] == route.points[index] {
            return false
        }
        return true
    }

    /// Returns nil for non-finite coordinates or a non-finite derived result.
    /// A degenerate primitive is defined as distance to its single endpoint.
    static func distance(
        from point: DexterityRoutePoint,
        toSegmentFrom start: DexterityRoutePoint,
        to end: DexterityRoutePoint
    ) -> Double? {
        guard point.hasFiniteCoordinates, start.hasFiniteCoordinates, end.hasFiniteCoordinates else {
            return nil
        }

        let vectorX = end.x - start.x
        let vectorY = end.y - start.y
        let lengthSquared = vectorX * vectorX + vectorY * vectorY
        guard lengthSquared.isFinite else {
            return nil
        }

        let closest: DexterityRoutePoint
        if lengthSquared == 0 {
            closest = start
        } else {
            let projection = ((point.x - start.x) * vectorX + (point.y - start.y) * vectorY) / lengthSquared
            guard projection.isFinite else {
                return nil
            }
            let clamped = min(max(projection, 0), 1)
            closest = DexterityRoutePoint(
                x: start.x + clamped * vectorX,
                y: start.y + clamped * vectorY
            )
        }

        let deltaX = point.x - closest.x
        let deltaY = point.y - closest.y
        let result = sqrt(deltaX * deltaX + deltaY * deltaY)
        return result.isFinite ? result : nil
    }

    /// Returns one error per raw trace point, preserving sequence and sample order.
    /// The trace point's captured `segmentIndex` is the sole segment-selection mechanism.
    static func pathErrors(from trial: DexterityTrial) -> [Double]? {
        guard isCalculationValid(route: trial.route), trial.coordinateSpace.isCalculationValid else {
            return nil
        }

        var errors: [Double] = []
        for sequence in trial.sequences {
            for sample in sequence.samples {
                guard sample.hasFiniteCoordinates,
                      sample.segmentIndex >= 0,
                      sample.segmentIndex < trial.route.points.count - 1,
                      let canonical = trial.coordinateSpace.canonicalPoint(localX: sample.x, localY: sample.y),
                      let error = distance(
                        from: canonical,
                        toSegmentFrom: trial.route.points[sample.segmentIndex],
                        to: trial.route.points[sample.segmentIndex + 1]
                      ) else {
                    return nil
                }
                errors.append(error)
            }
        }
        return errors
    }

    /// Returns one canonical-route-unit speed per valid consecutive pair within each sequence.
    /// A malformed pair invalidates the entire speed output; no pair is silently discarded.
    static func speedSamples(from trial: DexterityTrial) -> [Double]? {
        guard trial.coordinateSpace.isCalculationValid else {
            return nil
        }

        var speeds: [Double] = []

        for sequence in trial.sequences {
            guard sequence.samples.allSatisfy({ $0.t.isFinite && $0.hasFiniteCoordinates }) else {
                return nil
            }

            guard sequence.samples.count >= 2 else {
                continue
            }

            for index in 1..<sequence.samples.count {
                let previous = sequence.samples[index - 1]
                let current = sequence.samples[index]
                let deltaTime = current.t - previous.t
                guard deltaTime.isFinite, deltaTime > 0 else {
                    return nil
                }

                guard let canonicalPrevious = trial.coordinateSpace.canonicalPoint(localX: previous.x, localY: previous.y),
                      let canonicalCurrent = trial.coordinateSpace.canonicalPoint(localX: current.x, localY: current.y) else {
                    return nil
                }

                let deltaX = canonicalCurrent.x - canonicalPrevious.x
                let deltaY = canonicalCurrent.y - canonicalPrevious.y
                let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
                guard distance.isFinite else {
                    return nil
                }

                let speed = distance / deltaTime
                guard speed.isFinite else {
                    return nil
                }
                speeds.append(speed)
            }
        }

        return speeds
    }

    static func coefficientOfVariation(from stats: SummaryStats?) -> Double? {
        guard let stats,
              stats.mean.isFinite,
              stats.stdev.isFinite,
              stats.mean != 0 else {
            return nil
        }

        let result = (stats.stdev / stats.mean) * 100
        return result.isFinite ? result : nil
    }

    private static func rootMeanSquare(_ values: [Double]) -> Double? {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else {
            return nil
        }

        let meanSquare = values.reduce(0) { partial, value in
            partial + value * value
        } / Double(values.count)
        let result = sqrt(meanSquare)
        return result.isFinite ? result : nil
    }
}
