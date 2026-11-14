// Platform code is isolated; the scheduler itself never starts a thread.
#if os(Windows)
import WinSDK
func threadIdentity() -> UInt64 { UInt64(GetCurrentThreadId()) }
#else
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
func threadIdentity() -> UInt64 {
    #if canImport(Darwin)
    UInt64(UInt(bitPattern: pthread_self()))
    #else
    UInt64(pthread_self())
    #endif
}
#endif
