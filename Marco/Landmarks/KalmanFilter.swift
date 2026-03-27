import Foundation

struct KalmanFilter {
    var estimate: Double
    var errorEstimate: Double
    var processNoise: Double
    var measurementNoise: Double
    private var isInitialized = false

    init(processNoise: Double = 0.008, measurementNoise: Double = 3.0) {
        self.estimate = 0
        self.errorEstimate = 1.0
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
    }

    mutating func update(measurement: Double) -> Double {
        if !isInitialized {
            estimate = measurement
            isInitialized = true
            return estimate
        }

        // Predict
        let predictedEstimate = estimate
        let predictedError = errorEstimate + processNoise

        // Update
        let kalmanGain = predictedError / (predictedError + measurementNoise)
        estimate = predictedEstimate + kalmanGain * (measurement - predictedEstimate)
        errorEstimate = (1 - kalmanGain) * predictedError

        return estimate
    }

    mutating func reset() {
        estimate = 0
        errorEstimate = 1.0
        isInitialized = false
    }
}
