// The microphone capture life cycle (WI-M2-M3 round 2; review PR #42 M1, m1). The rules `MicrophoneAudioSource` keeps
// under its lock, tested without audio.

import Testing
@testable import TendAI

@Suite("Microphone capture state (WI-M2-M3; review PR #42 M1, m1)")
struct MicrophoneCaptureStateTests {

    @Test("M1: a stop while the capture is starting is remembered; the session is never activated")
    func stopBeforeActivation() throws {
        var state = MicrophoneCaptureState()
        let begunToken = state.begin()
        let token = try #require(begunToken)
        let r1 = state.stop()
        #expect(r1 == .wasStarting)
        let r2 = state.mayActivate(token)
        #expect(r2 == false)
        #expect(state.phase == .idle)
        let r3 = state.markRunning(token)
        #expect(r3 == false)
    }

    @Test("M1: a stop after activation but before the engine is stored stops it from ever running")
    func stopDuringStart() throws {
        var state = MicrophoneCaptureState()
        let begunToken = state.begin()
        let token = try #require(begunToken)
        let r4 = state.mayActivate(token)
        #expect(r4)
        let r5 = state.stop()
        #expect(r5 == .wasStarting)
        let r6 = state.markRunning(token)
        #expect(r6 == false)
        #expect(state.phase == .idle)
    }

    @Test("A stop while running hands back that capture's token for teardown, once")
    func stopWhileRunning() throws {
        var state = MicrophoneCaptureState()
        let begunToken = state.begin()
        let token = try #require(begunToken)
        let r7 = state.mayActivate(token)
        #expect(r7)
        let r8 = state.markRunning(token)
        #expect(r8)
        #expect(state.phase == .running(token))
        let r9 = state.stop()
        #expect(r9 == .wasRunning(token))
        let r10 = state.stop()
        #expect(r10 == .nothing)
        let r11 = state.end(token)
        #expect(r11 == false)
    }

    @Test("m1: a second capture is refused while one is starting or running, and allowed after it ends")
    func oneAtATime() throws {
        var state = MicrophoneCaptureState()
        let begunFirst = state.begin()
        let first = try #require(begunFirst)
        let r12 = state.begin()
        #expect(r12 == nil)
        let r13 = state.mayActivate(first)
        #expect(r13)
        let r14 = state.markRunning(first)
        #expect(r14)
        let r15 = state.begin()
        #expect(r15 == nil)
        let r16 = state.end(first)
        #expect(r16)
        let begunSecond = state.begin()
        let second = try #require(begunSecond)
        #expect(second != first)
    }

    @Test("m1: ending one capture never ends another (teardown is per token)")
    func endIsPerToken() throws {
        var state = MicrophoneCaptureState()
        let begunFirst = state.begin()
        let first = try #require(begunFirst)
        let r17 = state.end(first)
        #expect(r17)
        let begunSecond = state.begin()
        let second = try #require(begunSecond)
        let r18 = state.mayActivate(second)
        #expect(r18)
        let r19 = state.markRunning(second)
        #expect(r19)
        // The first stream's late termination must not stop the second capture.
        let r20 = state.end(first)
        #expect(r20 == false)
        #expect(state.phase == .running(second))
        let r21 = state.mayActivate(first)
        #expect(r21 == false)
        let r22 = state.markRunning(first)
        #expect(r22 == false)
    }

    @Test("A stop with nothing running does nothing, and leaves the next capture free to start")
    func idleStop() throws {
        var state = MicrophoneCaptureState()
        let r23 = state.stop()
        #expect(r23 == .nothing)
        let r24 = state.begin()
        #expect(r24 != nil)
    }
}
