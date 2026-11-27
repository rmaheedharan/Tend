// The microphone capture life cycle (WI-M2-M3; review PR #42 M1, m1, round 2 M1-r2, m6). The rules
// `MicrophoneAudioSource` keeps under its lock, tested without audio. Mutating calls are made outside `#expect`.

import Testing
@testable import TendAI

@Suite("Microphone capture state (WI-M2-M3; review PR #42 M1, m1, M1-r2, m6)")
struct MicrophoneCaptureStateTests {

    private func started(_ state: inout MicrophoneCaptureState) throws -> UInt64 {
        let begun = state.begin()
        return try #require(begun)
    }

    @Test("M1: a stop while the capture is starting is remembered; the session is never activated")
    func stopBeforeActivation() throws {
        var state = MicrophoneCaptureState()
        let token = try started(&state)
        let stopped = state.stop()
        #expect(stopped == .wasStarting)
        let activate = state.mayActivate(token)
        #expect(activate == false)
        #expect(state.phase == .idle)
    }

    @Test("M1-r2: a stop during engine prepare/start is seen after start; the engine is never published, and the start path tears down")
    func stopDuringEngineStart() throws {
        var state = MicrophoneCaptureState()
        let token = try started(&state)
        let activate = state.mayActivate(token)
        #expect(activate)
        // engine.prepare() / engine.start() are running on the start path now.
        let stopped = state.stop()
        #expect(stopped == .wasStarting)            // nobody else gets the engine to tear down
        let published = state.markRunning(token)  // after start() returned
        #expect(published == false)
        #expect(state.phase == .stopping(token))
        let during = state.begin()
        #expect(during == nil)                       // m6: nothing starts during the teardown
        state.finishTeardown(token)
        #expect(state.phase == .idle)
    }

    @Test("M1-r2: a stream termination during engine start acts as a stop; only the start path tears down")
    func terminationDuringEngineStart() throws {
        var state = MicrophoneCaptureState()
        let token = try started(&state)
        let activate = state.mayActivate(token)
        #expect(activate)
        let owned = state.end(token)
        #expect(owned == false)
        #expect(state.phase == .stopRequested(token))
        let published = state.markRunning(token)
        #expect(published == false)
        #expect(state.phase == .stopping(token))
        state.finishTeardown(token)
        #expect(state.phase == .idle)
    }

    @Test("A stop while running hands the token to one caller; the source stays busy until finishTeardown (m6)")
    func stopWhileRunning() throws {
        var state = MicrophoneCaptureState()
        let token = try started(&state)
        _ = state.mayActivate(token)
        let published = state.markRunning(token)
        #expect(published)
        let first = state.stop()
        #expect(first == .wasRunning(token))
        let second = state.stop()
        #expect(second == .nothing)
        let owned = state.end(token)
        #expect(owned == false)
        let during = state.begin()
        #expect(during == nil)
        state.finishTeardown(token)
        let after = state.begin()
        #expect(after != nil)
    }

    @Test("m6: a new capture cannot begin while the old one's teardown runs, after a termination too")
    func noOverlapAfterTermination() throws {
        var state = MicrophoneCaptureState()
        let token = try started(&state)
        _ = state.mayActivate(token)
        _ = state.markRunning(token)
        let owned = state.end(token)
        #expect(owned)
        #expect(state.phase == .stopping(token))
        let during = state.begin()
        #expect(during == nil)
        state.finishTeardown(token)
        let next = try started(&state)
        #expect(next != token)
    }

    @Test("A start that gives up (session, converter or engine) holds the source until its teardown is done")
    func startGaveUp() throws {
        var state = MicrophoneCaptureState()
        let token = try started(&state)
        _ = state.mayActivate(token)
        state.startGaveUp(token)
        #expect(state.phase == .stopping(token))
        let during = state.begin()
        #expect(during == nil)
        state.finishTeardown(token)
        #expect(state.phase == .idle)
    }

    @Test("m1: a second capture is refused while one is starting or running")
    func oneAtATime() throws {
        var state = MicrophoneCaptureState()
        let first = try started(&state)
        let whileStarting = state.begin()
        #expect(whileStarting == nil)
        _ = state.mayActivate(first)
        _ = state.markRunning(first)
        let whileRunning = state.begin()
        #expect(whileRunning == nil)
    }

    @Test("m1: another capture's token never ends, stops or finishes this one")
    func perToken() throws {
        var state = MicrophoneCaptureState()
        let first = try started(&state)
        _ = state.mayActivate(first)
        _ = state.markRunning(first)
        _ = state.end(first)
        state.finishTeardown(first)
        let second = try started(&state)
        _ = state.mayActivate(second)
        _ = state.markRunning(second)
        let stale = state.end(first)
        #expect(stale == false)
        state.finishTeardown(first)
        #expect(state.phase == .running(second))
        let staleActivate = state.mayActivate(first)
        let stalePublish = state.markRunning(first)
        #expect(staleActivate == false && stalePublish == false)
    }

    @Test("A stop with nothing running does nothing")
    func idleStop() {
        var state = MicrophoneCaptureState()
        let result = state.stop()
        #expect(result == .nothing)
        let begun = state.begin()
        #expect(begun != nil)
    }
}
