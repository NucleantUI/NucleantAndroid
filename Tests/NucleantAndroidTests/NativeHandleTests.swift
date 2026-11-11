import Testing
@testable import AndroidCore

@Suite struct NativeHandleTests {
    final class Owner {}

    @Test func handleFindsItsOwnerWhileItLives() {
        let owner = Owner()
        let handle = NativeHandle.retain(owner)
        defer { NativeHandle<Owner>.release(handle) }
        #expect(NativeHandle<Owner>.owner(handle) === owner)
    }

    @Test func handleOutlivingItsOwnerFindsNil() {
        var owner: Owner? = Owner()
        let handle = NativeHandle.retain(owner!)
        defer { NativeHandle<Owner>.release(handle) }
        owner = nil
        // What a Java callback arriving late sees.
        #expect(NativeHandle<Owner>.owner(handle) == nil)
    }

    @Test func zeroHandleHasNoOwner() {
        #expect(NativeHandle<Owner>.owner(0) == nil)
    }
}
