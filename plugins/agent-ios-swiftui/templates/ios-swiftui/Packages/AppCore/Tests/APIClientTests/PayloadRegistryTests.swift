// PayloadRegistry: what each policy seals, and the generated registry's shape.
import Testing

@testable import APIClient

@Suite("PayloadRegistry")
struct PayloadRegistryTests {
    @Test(
        "seals the sides each policy names",
        arguments: [
            (PayloadPolicy.strict, true, true), (.requestOnly, true, false), (.responseOnly, false, true),
            (.none, false, false),
        ]
    )
    func policies(policy: PayloadPolicy, request: Bool, response: Bool) {
        #expect(policy.sealsRequest == request)
        #expect(policy.sealsResponse == response)
    }

    @Test("the generated registry: upper-case methods, patterns from the root, a handshake that seals nothing")
    func generated() {
        let registry = PayloadRegistry.generated
        for (operation, endpoint) in registry.entries {
            #expect(endpoint.method == endpoint.method.uppercased(), "\(operation)")
            #expect(endpoint.pattern.hasPrefix("/"), "\(operation)")
        }
        if let handshake = registry.handshake {
            #expect(handshake.method == "GET")
            #expect(!handshake.policy.sealsRequest)
            #expect(!handshake.policy.sealsResponse)
        }
    }
}
