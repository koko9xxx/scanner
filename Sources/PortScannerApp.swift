import SwiftUI
import Network
import Darwin

@main
struct PortScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ScanResult: Identifiable {
    let id = UUID()
    let hostValue: UInt32
    let host: String
    let port: UInt16
}

struct ContentView: View {
    @State private var startIP = "192.168.1.1"
    @State private var endIP = "192.168.1.20"
    @State private var startPort = "22"
    @State private var endPort = "443"
    @State private var results: [ScanResult] = []
    @State private var scanned = 0
    @State private var total = 0
    @State private var outstanding = 0
    @State private var scanning = false
    @State private var errorMessage: String?
    @State private var scanTask: Task<Void, Never>?

    private let maxProbes = 100_000
    private let concurrency = 64
    private let timeoutSeconds = 1.0

    private var sortedResults: [ScanResult] {
        results.sorted {
            $0.hostValue == $1.hostValue ? $0.port < $1.port : $0.hostValue < $1.hostValue
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Network") {
                    LabeledContent("This device's IP") {
                        Text(localIPAddress() ?? "Unknown")
                            .foregroundStyle(.secondary)
                    }
                    TextField("Start IP", text: $startIP)
                        .keyboardType(.numbersAndPunctuation)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("End IP", text: $endIP)
                        .keyboardType(.numbersAndPunctuation)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section("Ports") {
                    TextField("Start Port", text: $startPort)
                        .keyboardType(.numberPad)
                    TextField("End Port", text: $endPort)
                        .keyboardType(.numberPad)
                }

                Section {
                    if scanning {
                        ProgressView(value: Double(scanned), total: Double(max(total, 1))) {
                            Text("Scanned \(scanned) of \(total)")
                        }
                        Button("Stop", role: .destructive) {
                            stopScan()
                        }
                    } else {
                        Button("Start Scan") {
                            startScan()
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if !sortedResults.isEmpty {
                    Section("Open ports (\(sortedResults.count))") {
                        ForEach(sortedResults) { result in
                            Text("\(result.host):\(result.port)")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .navigationTitle("Port Scanner")
        }
    }

    private func startScan() {
        guard !scanning else { return }
        errorMessage = nil
        results = []
        scanned = 0

        guard let first = parseIPv4(startIP.trimmingCharacters(in: .whitespaces)),
              let last = parseIPv4(endIP.trimmingCharacters(in: .whitespaces)),
              first <= last else {
            errorMessage = "Invalid IP range. Use IPv4 like 192.168.1.1 to 192.168.1.50."
            return
        }
        guard let p1 = UInt16(startPort), let p2 = UInt16(endPort), p1 >= 1, p2 >= p1 else {
            errorMessage = "Invalid port range. Ports must be 1-65535."
            return
        }

        total = Int(last - first + 1) * Int(p2 - p1 + 1)
        guard total <= maxProbes else {
            errorMessage = "Too many probes (\(total)). Keep the total at or below \(maxProbes)."
            return
        }

        scanning = true
        outstanding = total

        let limiter = ScanLimiter(limit: concurrency)
        let timeout = timeoutSeconds

        scanTask = Task { @MainActor in
            for hostValue in first...last {
                if Task.isCancelled { break }
                let host = formatIPv4(hostValue)
                for port in p1...p2 {
                    if Task.isCancelled { break }
                    await limiter.wait()
                    Task { @MainActor in
                        let isOpen = await checkPort(host, port, timeout: timeout)
                        if isOpen {
                            results.append(ScanResult(hostValue: hostValue, host: host, port: port))
                        }
                        scanned += 1
                        outstanding = max(0, outstanding - 1)
                        if outstanding == 0 {
                            scanning = false
                        }
                    }
                }
            }
        }
    }

    private func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        scanning = false
    }
}

// MARK: - Networking

func checkPort(_ host: String, _ port: UInt16, timeout: TimeInterval) async -> Bool {
    await withCheckedContinuation { continuation in
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            continuation.resume(returning: false)
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        var resumed = false
        func finish(_ isOpen: Bool) {
            if !resumed {
                resumed = true
                connection.cancel()
                continuation.resume(returning: isOpen)
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(true)
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            finish(false)
        }
    }
}

actor ScanLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func wait() async {
        if active < limit {
            active += 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func signal() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            active -= 1
        }
    }
}

// MARK: - IPv4 helpers

func parseIPv4(_ string: String) -> UInt32? {
    let parts = string.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }
    var result: UInt32 = 0
    for part in parts {
        guard let value = UInt8(part) else { return nil }
        result = (result << 8) | UInt32(value)
    }
    return result
}

func formatIPv4(_ value: UInt32) -> String {
    "\(value >> 24 & 255).\(value >> 16 & 255).\(value >> 8 & 255).\(value & 255)"
}

func localIPAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ptr.pointee
        guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
        guard String(cString: interface.ifa_name) == "en0" else { continue }
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(
            interface.ifa_addr,
            socklen_t(interface.ifa_addr.pointee.sa_len),
            &hostname,
            socklen_t(hostname.count),
            nil,
            socklen_t(0),
            NI_NUMERICHOST
        )
        address = String(cString: hostname)
    }
    freeifaddrs(ifaddr)
    return address
}
