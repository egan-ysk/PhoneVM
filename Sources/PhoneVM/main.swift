import Foundation

if #available(macOS 15.0, *) {
    PhoneVMApp.main()
} else {
    fatalError("PhoneVM requires macOS 15.0 or newer.")
}
