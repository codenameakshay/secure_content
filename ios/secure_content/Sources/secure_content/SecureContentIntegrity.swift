import Darwin
import Foundation

enum SecureContentIntegrity {
  static var riskDetected: Bool {
    isRunningOnSimulator || isJailbroken || isDebuggerAttached
  }

  private static var isRunningOnSimulator: Bool {
    #if targetEnvironment(simulator)
      true
    #else
      false
    #endif
  }

  private static var isJailbroken: Bool {
    #if targetEnvironment(simulator)
      return false
    #else
      let suspiciousPaths = [
        "/Applications/Cydia.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt/",
      ]
      if suspiciousPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
        return true
      }

      let probeURL = URL(fileURLWithPath: "/private")
        .appendingPathComponent("secure-content-\(UUID().uuidString)")
      do {
        try Data().write(to: probeURL, options: .withoutOverwriting)
        try? FileManager.default.removeItem(at: probeURL)
        return true
      } catch {
        return false
      }
    #endif
  }

  private static var isDebuggerAttached: Bool {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    let result = name.withUnsafeMutableBufferPointer { buffer in
      sysctl(buffer.baseAddress, u_int(buffer.count), &info, &size, nil, 0)
    }
    return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
  }
}
