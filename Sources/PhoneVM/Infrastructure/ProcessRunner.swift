import Darwin
import Foundation

struct ProcessOutput: Equatable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

struct ProcessBinaryOutput: Equatable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: String
}

protocol ProcessRunning: AnyObject {
    func runAndCapture(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) throws -> ProcessOutput

    func runAndCaptureBinary(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) throws -> ProcessBinaryOutput

    func launchDetached(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?
    ) throws
}

extension ProcessRunning {
    func runAndCapture(
        executableURL: URL,
        arguments: [String] = [],
        timeout: TimeInterval = 10
    ) throws -> ProcessOutput {
        try runAndCapture(
            executableURL: executableURL,
            arguments: arguments,
            environment: nil,
            timeout: timeout
        )
    }

    func runAndCaptureBinary(
        executableURL: URL,
        arguments: [String] = [],
        timeout: TimeInterval = 10
    ) throws -> ProcessBinaryOutput {
        try runAndCaptureBinary(
            executableURL: executableURL,
            arguments: arguments,
            environment: nil,
            timeout: timeout
        )
    }

    func launchDetached(executableURL: URL, arguments: [String] = []) throws {
        try launchDetached(executableURL: executableURL, arguments: arguments, environment: nil)
    }
}

final class ProcessRunner: ProcessRunning {
    func runAndCapture(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 10
    ) throws -> ProcessOutput {
        let raw = try execute(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            timeout: timeout
        )

        return ProcessOutput(
            exitCode: raw.exitCode,
            standardOutput: String(data: raw.standardOutput, encoding: .utf8) ?? "",
            standardError: String(data: raw.standardError, encoding: .utf8) ?? ""
        )
    }

    func runAndCaptureBinary(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 10
    ) throws -> ProcessBinaryOutput {
        let raw = try execute(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            timeout: timeout
        )

        return ProcessBinaryOutput(
            exitCode: raw.exitCode,
            standardOutput: raw.standardOutput,
            standardError: String(data: raw.standardError, encoding: .utf8) ?? ""
        )
    }

    func launchDetached(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) throws {
        try validateExecutable(at: executableURL)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, replacement in replacement }
        }

        try process.run()
    }

    private func execute(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) throws -> (exitCode: Int32, standardOutput: Data, standardError: Data) {
        try validateExecutable(at: executableURL)

        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        let outputCollector = DataCollector()
        let errorCollector = DataCollector()
        let readerGroup = DispatchGroup()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = standardOutput
        process.standardError = standardError
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, replacement in replacement }
        }

        defer {
            standardOutput.fileHandleForReading.closeFile()
            standardError.fileHandleForReading.closeFile()
        }

        try process.run()
        standardOutput.fileHandleForWriting.closeFile()
        standardError.fileHandleForWriting.closeFile()

        readerGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outputCollector.set(standardOutput.fileHandleForReading.readDataToEndOfFile())
            readerGroup.leave()
        }

        readerGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            errorCollector.set(standardError.fileHandleForReading.readDataToEndOfFile())
            readerGroup.leave()
        }

        let terminationSemaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            terminationSemaphore.signal()
        }

        if terminationSemaphore.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning {
                process.terminate()
            }

            if terminationSemaphore.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
                _ = terminationSemaphore.wait(timeout: .now() + 2)
            }

            readerGroup.wait()
            throw VirtualMachineProviderError.processFailed("执行超时：\(executableURL.lastPathComponent)")
        }

        readerGroup.wait()
        return (
            process.terminationStatus,
            outputCollector.value,
            errorCollector.value
        )
    }

    private func validateExecutable(at url: URL) throws {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path),
              FileManager.default.isExecutableFile(atPath: path) else {
            throw VirtualMachineProviderError.executableNotFound(url.lastPathComponent)
        }
    }
}

private final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }
}
