import Foundation
import Darwin

/// Runs Apple private actuator calls ONLY in a separate, disposable process.
/// A framework ABI crash can terminate the helper without killing the UI.
/// Enhanced mode is deliberately never persisted across app launches.
final class EnhancedHapticBridge {
    private var child: Process?
    private var writer: Pipe?
    private var reader: Pipe?
    private var pending = Data()
    private var ready = false
    private var stopped = false
    private var callback: ((Bool) -> Void)?
    private var lastSend = 0.0

    func start(onStatus: @escaping (Bool) -> Void) {
        stop()
        stopped = false
        callback = onStatus
        guard let path = Bundle.main.path(forResource: "MenuMagnetActuator", ofType: nil) else {
            onStatus(false)
            return
        }
        // Prevent a dying child from terminating the parent with SIGPIPE.
        _ = Darwin.signal(SIGPIPE, SIG_IGN)
        let process = Process()
        let writePipe = Pipe()
        let readPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.standardInput = writePipe
        process.standardOutput = readPipe
        process.standardError = Pipe()
        process.terminationHandler = { [weak self, weak process] _ in
            DispatchQueue.main.async {
                guard let self = self, !self.stopped, self.child === process else { return }
                self.ready = false
                self.callback?(false)
            }
        }
        reader = readPipe
        writer = writePipe
        child = process
        readPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                self?.receive(data)
            }
        }
        do {
            try process.run()
        } catch {
            stop()
            onStatus(false)
        }
    }

    private func receive(_ data: Data) {
        guard !stopped, !data.isEmpty else { return }
        pending.append(data)
        while let end = pending.firstIndex(of: 10) {
            let line = String(decoding: pending[..<end], as: UTF8.self)
            pending.removeSubrange(...end)
            if line == "READY" {
                ready = true
                callback?(true)
            } else if line.hasPrefix("UNAVAILABLE") || line.hasPrefix("ERROR") {
                ready = false
                callback?(false)
            }
        }
        if pending.count > 4096 { pending.removeAll() }
    }

    @discardableResult
    func send(level: Int) -> Bool {
        guard level >= 1, level <= 4, ready, !stopped,
              let process = child, process.isRunning,
              let handle = writer?.fileHandleForWriting else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        // Prevent firing too rapidly when AX hit-testing oscillates at boundaries.
        guard now - lastSend >= 0.095 else { return true }
        lastSend = now
        let message = Array("\(level)\n".utf8)
        let count = message.withUnsafeBytes { bytes in
            Darwin.write(handle.fileDescriptor, bytes.baseAddress, bytes.count)
        }
        if count != message.count {
            ready = false
            callback?(false)
            return false
        }
        return true
    }

    func stop() {
        stopped = true
        ready = false
        reader?.fileHandleForReading.readabilityHandler = nil
        if let process = child, process.isRunning {
            process.terminate()
        }
        writer?.fileHandleForWriting.closeFile()
        reader?.fileHandleForReading.closeFile()
        writer = nil
        reader = nil
        child = nil
        callback = nil
        pending.removeAll()
    }
    deinit { stop() }
}
