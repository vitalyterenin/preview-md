import Foundation

@main
enum ExtensionMain {
    @_silgen_name("NSExtensionMain")
    private static func extensionMain(
        _ argumentCount: Int32,
        _ arguments: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
    ) -> Int32

    static func main() {
        exit(extensionMain(CommandLine.argc, CommandLine.unsafeArgv))
    }
}
