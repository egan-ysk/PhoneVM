import Foundation

struct ProcessOutput: Equatable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

final class ProcessRunner {
    func runAndCapture(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 10
    ) throws -> ProcessOutput {
        try validateExecutable(at: executableURL)

        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        if let environment {
            process.environment = environment
        }

        try process.run()

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw VirtualMachineProviderError.processFailed("执行超时：\(executableURL.lastPathComponent)")
        }

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

        return ProcessOutput(
            exitCode: process.terminationStatus,
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? ""
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
            process.environment = environment
        }

        try process.run()
    }

    private func validateExecutable(at url: URL) throws {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw VirtualMachineProviderError.executableNotFound(url.lastPathComponent)
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw VirtualMachineProviderError.executableNotFound(url.lastPathComponent)
        }
    }
}
