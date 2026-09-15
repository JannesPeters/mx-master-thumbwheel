import XCTest
@testable import ThumbwheelRemapperCore

final class ConfigurationTests: XCTestCase {
    func testDefaultsDescribeThumbwheelAndSingleClicksOnly() {
        let defaults = ConfigurationDocument.defaults

        XCTAssertEqual(defaults.buttonClicks.count, 2)
        XCTAssertTrue(defaults.buttonHolds.isEmpty)
        XCTAssertEqual(defaults.wheelMappings.count, 1)
        XCTAssertEqual(defaults.buttonClicks.first?.button, .other(3))
        XCTAssertEqual(defaults.buttonClicks.first?.action.direction, .down)
        XCTAssertEqual(defaults.buttonClicks.last?.button, .other(4))
        XCTAssertEqual(defaults.buttonClicks.last?.action.direction, .up)
        XCTAssertEqual(defaults.wheelMappings.first?.source, .horizontalThumbwheel)
        XCTAssertTrue(defaults.buttonClicks.allSatisfy(\.isEnabled))
        XCTAssertTrue(defaults.wheelMappings.allSatisfy(\.isEnabled))
    }

    func testMappingsDefaultToEnabledAndCanBeDisabled() throws {
        let click = ButtonClickMapping(
            button: .other(5),
            action: ScrollActionOptions(direction: .up)
        )
        let hold = ButtonHoldMapping(
            button: .other(6),
            action: HoldActionOptions(mode: .scrollDown)
        )
        let wheel = WheelMapping()

        XCTAssertTrue(click.isEnabled)
        XCTAssertTrue(hold.isEnabled)
        XCTAssertTrue(wheel.isEnabled)

        let disabledClick = ButtonClickMapping(
            isEnabled: false,
            button: .other(5),
            action: ScrollActionOptions(direction: .up)
        )
        let decoded = try JSONDecoder().decode(
            ButtonClickMapping.self,
            from: JSONEncoder().encode(disabledClick)
        )
        XCTAssertFalse(decoded.isEnabled)
    }

    func testMappingsWithoutEnabledFieldLoadAsEnabled() throws {
        func removingEnabled<T: Encodable>(_ value: T) throws -> Data {
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(value)
                ) as? [String: Any]
            )
            object.removeValue(forKey: "isEnabled")
            return try JSONSerialization.data(withJSONObject: object)
        }

        let click = try JSONDecoder().decode(
            ButtonClickMapping.self,
            from: removingEnabled(
                ButtonClickMapping(
                    button: .other(5),
                    action: ScrollActionOptions(direction: .up)
                )
            )
        )
        let hold = try JSONDecoder().decode(
            ButtonHoldMapping.self,
            from: removingEnabled(
                ButtonHoldMapping(
                    button: .other(6),
                    action: HoldActionOptions(mode: .scrollDown)
                )
            )
        )
        let wheel = try JSONDecoder().decode(
            WheelMapping.self,
            from: removingEnabled(WheelMapping())
        )

        XCTAssertTrue(click.isEnabled)
        XCTAssertTrue(hold.isEnabled)
        XCTAssertTrue(wheel.isEnabled)
    }

    func testButtonNamesDescribeCommonQuartzButtons() {
        XCTAssertEqual(InputButton.other(2).displayName, "Middle button (2)")
        XCTAssertEqual(InputButton.other(3).displayName, "Back button (3)")
        XCTAssertEqual(InputButton.other(4).displayName, "Forward button (4)")
        XCTAssertEqual(InputButton.other(9).displayName, "Extra button 9")
    }

    func testHoldModesArePeerOptions() {
        XCTAssertEqual(HoldScrollMode.allCases, [.scrollUp, .scrollDown, .joystick])
        XCTAssertEqual(HoldScrollMode.scrollUp.direction, .up)
        XCTAssertEqual(HoldScrollMode.scrollDown.direction, .down)
        XCTAssertNil(HoldScrollMode.joystick.direction)
    }

    func testJoystickAxesDefaultToVerticalOnlyAndRoundTrip() throws {
        let defaults = HoldActionOptions(mode: .joystick)
        XCTAssertTrue(defaults.joystickVerticalEnabled)
        XCTAssertFalse(defaults.joystickHorizontalEnabled)
        XCTAssertTrue(defaults.joystickCapturesCursor)

        let configured = HoldActionOptions(
            mode: .joystick,
            joystickVerticalEnabled: false,
            joystickHorizontalEnabled: true,
            joystickCapturesCursor: false
        )
        let data = try JSONEncoder().encode(configured)
        let decoded = try JSONDecoder().decode(HoldActionOptions.self, from: data)
        XCTAssertEqual(decoded, configured)
    }

    func testDuplicateValidationAllowsIndependentClickKindsButRejectsSameGesture() {
        var document = ConfigurationDocument.defaults
        document.buttonClicks.append(
            ButtonClickMapping(
                button: .other(3),
                click: .double,
                action: ScrollActionOptions(direction: .up)
            )
        )
        XCTAssertTrue(MappingValidator.validate(document).isEmpty)

        document.buttonClicks.append(
            ButtonClickMapping(
                button: .other(3),
                click: .single,
                action: ScrollActionOptions(direction: .up)
            )
        )
        XCTAssertTrue(
            MappingValidator.validate(document).contains {
                if case .duplicateClick(.other(3), .single) = $0.kind {
                    return true
                }

                func testLeftAndRightButtonsAreRejected() {
                    let document = ConfigurationDocument(
                        buttonClicks: [
                            ButtonClickMapping(
                                button: .left,
                                action: ScrollActionOptions(direction: .up)
                            )
                        ],
                        buttonHolds: [
                            ButtonHoldMapping(
                                button: .right,
                                action: HoldActionOptions(mode: .scrollDown)
                            )
                        ],
                        wheelMappings: []
                    )

                    let issues = MappingValidator.validate(document)
                    XCTAssertTrue(issues.contains { $0.kind == .unsupportedButton(button: .left) })
                    XCTAssertTrue(issues.contains { $0.kind == .unsupportedButton(button: .right) })
                }
                return false
            }
        )
    }

    func testStoreUsesNewKeyAndFallsBackOnDecodeFailure() {
        let storage = TestStorage()
        var messages: [String] = []
        let store = ConfigurationStore(storage: storage, logger: { messages.append($0) })

        storage.values["BackButtonNumber"] = Data("3".utf8)
        XCTAssertEqual(store.load(), .defaults)
        XCTAssertTrue(store.save(.defaults))
        XCTAssertNotNil(storage.data(forKey: ConfigurationStore.storageKey))
        XCTAssertEqual(store.load(), .defaults)

        storage.values[ConfigurationStore.storageKey] = Data("not-json".utf8)
        XCTAssertEqual(store.load(), .defaults)
        XCTAssertTrue(messages.contains { $0.contains("could not decode") })
    }

    func testStoreLogsPersistenceFailure() {
        let storage = TestStorage()
        storage.error = TestError.writeFailed
        var messages: [String] = []
        let store = ConfigurationStore(storage: storage, logger: { messages.append($0) })

        XCTAssertFalse(store.save(.defaults))
        XCTAssertTrue(messages.contains { $0.contains("could not save") })
    }

    func testOlderActionDocumentsDefaultToEnabledEasing() throws {
        let decoder = JSONDecoder()
        let click = try decoder.decode(
            ScrollActionOptions.self,
            from: Data(
                """
                {
                  "direction": 1,
                  "amount": { "kind": "fixed", "points": 40 },
                  "duration": 0.18,
                  "easing": "quickInLongOut"
                }
                """.utf8
            )
        )
        let hold = try decoder.decode(
            HoldActionOptions.self,
            from: Data(
                """
                {
                  "direction": 1,
                  "pointsPerSecond": 800,
                  "accelerationDuration": 0.18,
                  "releaseDuration": 0.14,
                  "joystickEnabled": true
                }
                """.utf8
            )
        )

        XCTAssertTrue(click.easingEnabled)
        XCTAssertTrue(hold.easingEnabled)
        XCTAssertEqual(hold.mode, .joystick)
        XCTAssertTrue(hold.joystickVerticalEnabled)
        XCTAssertFalse(hold.joystickHorizontalEnabled)
        XCTAssertTrue(hold.joystickCapturesCursor)
    }
}

final class GestureTimingTests: XCTestCase {
    func testSingleClickIsImmediateWithoutDoubleMapping() {
        var recognizer = ButtonGestureRecognizer(
            timing: GestureTimingPolicy(doubleClickInterval: 0.5)
        )
        let outputs = recognizer.buttonDown(
            .other(3),
            at: 10,
            hasSingleMapping: true,
            hasDoubleMapping: false,
            hasHoldMapping: false
        )
        XCTAssertEqual(outputs, [.single(.other(3))])
        XCTAssertFalse(recognizer.isWaiting)
    }

    func testDoubleMappingDelaysSingleUntilIntervalAndRecognizesDouble() {
        var recognizer = ButtonGestureRecognizer(
            timing: GestureTimingPolicy(doubleClickInterval: 0.25)
        )
        XCTAssertTrue(
            recognizer.buttonDown(
                .other(3),
                at: 10,
                hasSingleMapping: true,
                hasDoubleMapping: true,
                hasHoldMapping: false
            ).isEmpty
        )
        XCTAssertEqual(recognizer.advance(to: 10.24), [])
        XCTAssertEqual(recognizer.advance(to: 10.25), [.single(.other(3))])

        XCTAssertTrue(
            recognizer.buttonDown(
                .other(3),
                at: 20,
                hasSingleMapping: true,
                hasDoubleMapping: true,
                hasHoldMapping: false
            ).isEmpty
        )
        XCTAssertEqual(
            recognizer.buttonDown(
                .other(3),
                at: 20.1,
                hasSingleMapping: true,
                hasDoubleMapping: true,
                hasHoldMapping: false
            ),
            [.double(.other(3))]
        )
    }

    func testHoldRemainsIndependentWhenDoubleMappingExists() {
        var recognizer = ButtonGestureRecognizer(
            timing: GestureTimingPolicy(doubleClickInterval: 0.2, holdDelay: 0.4)
        )
        XCTAssertTrue(
            recognizer.buttonDown(
                .other(3),
                at: 0,
                hasSingleMapping: true,
                hasDoubleMapping: true,
                hasHoldMapping: true
            ).isEmpty
        )
        XCTAssertEqual(recognizer.advance(to: 0.25), [])
        XCTAssertEqual(recognizer.advance(to: 0.4), [.hold(.other(3))])
        XCTAssertEqual(recognizer.buttonUp(.other(3), at: 0.45), [])
    }

    func testSingleStillArrivesAfterEarlyReleaseWhenDoubleAndHoldExist() {
        var recognizer = ButtonGestureRecognizer(
            timing: GestureTimingPolicy(doubleClickInterval: 0.2, holdDelay: 0.4)
        )
        _ = recognizer.buttonDown(
            .other(3),
            at: 0,
            hasSingleMapping: true,
            hasDoubleMapping: true,
            hasHoldMapping: true
        )
        XCTAssertEqual(recognizer.buttonUp(.other(3), at: 0.1), [])
        XCTAssertEqual(recognizer.advance(to: 0.2), [.single(.other(3))])
    }
}

final class RoutingTests: XCTestCase {
    func testRouterConsumesOnlyMappedButtons() {
        let router = EventRouter()
        XCTAssertEqual(
            router.route(.buttonDown(.other(3))),
            .consume
        )
        XCTAssertEqual(
            router.route(.buttonDown(.other(9))),
            .forward
        )
        XCTAssertEqual(
            router.route(.buttonDown(.left)),
            .forward
        )
    }

    func testDisabledMappingsAreIgnoredByRouter() {
        var document = ConfigurationDocument.defaults
        document.buttonClicks[0].isEnabled = false
        document.buttonHolds = [
            ButtonHoldMapping(
                isEnabled: false,
                button: .other(9),
                action: HoldActionOptions(mode: .scrollDown)
            )
        ]
        document.wheelMappings[0].isEnabled = false
        let router = EventRouter(document: document)

        XCTAssertEqual(
            router.route(.buttonDown(.other(3))),
            .forward
        )
        XCTAssertEqual(
            router.route(.buttonDown(.other(9))),
            .forward
        )
        XCTAssertEqual(
            router.route(
                .wheel(
                    WheelEvent(
                        horizontal: 4,
                        pointHorizontal: 4
                    )
                )
            ),
            .forward
        )
    }

    func testWheelRouterTransformsHorizontalNonContinuousEvents() {
        let router = EventRouter()
        let event = WheelEvent(
            integerHorizontal: 4,
            horizontal: 4,
            pointHorizontal: 4
        )
        guard case let .mapped(.wheel(_, transformed)) = router.route(.wheel(event)) else {
            return XCTFail("Expected a mapped wheel event")
        }
        XCTAssertEqual(transformed.vertical, 4)
        XCTAssertEqual(transformed.integerVertical, 4)
        XCTAssertEqual(transformed.horizontal, 0)
        XCTAssertEqual(transformed.pointVertical, 4)
    }

    func testWheelDetectorRejectsContinuousAndDiagonalEvents() {
        XCTAssertFalse(
            WheelSourceDetector.isHorizontalThumbwheel(
                WheelEvent(horizontal: 2, isContinuous: true)
            )
        )
        XCTAssertFalse(
            WheelSourceDetector.isHorizontalThumbwheel(
                WheelEvent(vertical: 1, horizontal: 2)
            )
        )
    }

    func testEventTapReenableIsolatedFromRouting() {
        let gate = EventTapReenableGate()
        XCTAssertTrue(gate.shouldReenable(for: .tapDisabled(.timeout)))
        XCTAssertTrue(gate.shouldReenable(for: .tapDisabled(.userInput)))
        XCTAssertFalse(gate.shouldReenable(for: .other))
    }
}

final class EngineTests: XCTestCase {
    func testDiscreteScrollAnimationIsDeterministic() {
        let animation = DiscreteScrollAnimation(
            distance: 100,
            duration: 1,
            easing: .linear
        )
        XCTAssertEqual(animation.position(at: 0.25), 25, accuracy: 0.0001)
        XCTAssertEqual(animation.delta(from: 0.25, to: 0.75), 50, accuracy: 0.0001)
        XCTAssertEqual(animation.position(at: 2), 100, accuracy: 0.0001)
    }

    func testJoystickStartsAtZeroForOneAndTwoDimensions() {
        var one = JoystickDisplacement1D()
        XCTAssertEqual(one.update(pointer: 100), 0)
        XCTAssertEqual(one.update(pointer: 125), 25)

        var two = JoystickDisplacement2D()
        XCTAssertEqual(two.update(pointer: Point2D(x: 10, y: 20)), .zero)
        XCTAssertEqual(two.update(pointer: Point2D(x: 13, y: 14)), Point2D(x: 3, y: -6))
    }

    func testContinuousAndDragEnginesProduceStableMotion() {
        var continuous = ContinuousScrollEngine(response: 100)
        let first = continuous.advance(targetVelocity: 100, deltaTime: 0.1)
        XCTAssertEqual(first, 10, accuracy: 0.0001)

        var drag = DragScrollMomentumEngine(friction: 1)
        XCTAssertEqual(drag.drag(delta: 20, deltaTime: 0.1), 20)
        drag.release()
        XCTAssertGreaterThan(drag.advance(deltaTime: 0.1), 0)
        XCTAssertGreaterThan(drag.velocity, 0)
    }

    func testJoystickSpeedHasNeutralAndDirectionZones() {
        let profile = JoystickSpeedProfile()
        XCTAssertEqual(profile.multiplier(for: 0), 1)
        XCTAssertEqual(profile.multiplier(for: -100), 0)
        XCTAssertGreaterThan(profile.multiplier(for: 300), 1)
        XCTAssertLessThan(profile.multiplier(for: -300), 0)
        XCTAssertEqual(profile.multiplier(for: 0, centeredMode: true), 0)
        XCTAssertGreaterThan(profile.multiplier(for: 300, centeredMode: true), 0)
        XCTAssertLessThan(profile.multiplier(for: -300, centeredMode: true), 0)
    }

    func testJoystickIntentStartsAtTheRequestedPauseZoneEdge() {
        let profile = JoystickSpeedProfile()
        var positiveIntent = JoystickIntentAxis()

        XCTAssertEqual(positiveIntent.multiplier(for: 0, profile: profile), 0)
        XCTAssertGreaterThan(positiveIntent.multiplier(for: 1, profile: profile), 0)
        XCTAssertEqual(positiveIntent.multiplier(for: -79, profile: profile), 0)
        XCTAssertLessThan(positiveIntent.multiplier(for: -81, profile: profile), 0)

        var negativeIntent = JoystickIntentAxis()
        XCTAssertLessThan(negativeIntent.multiplier(for: -1, profile: profile), 0)
        XCTAssertEqual(negativeIntent.multiplier(for: 79, profile: profile), 0)
        XCTAssertGreaterThan(negativeIntent.multiplier(for: 81, profile: profile), 0)

        positiveIntent.reset()
        XCTAssertLessThan(positiveIntent.multiplier(for: -1, profile: profile), 0)
    }
}

private enum TestError: Error {
    case writeFailed
}

private final class TestStorage: ConfigurationStorage {
    var values: [String: Data] = [:]
    var error: Error?

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func set(_ data: Data, forKey key: String) throws {
        if let error {
            throw error
        }
        values[key] = data
    }
}
