import XCTest
@testable import Library
@testable import KsApi
@testable import ReactiveExtensions_TestHelpers
import Prelude
import Result

final class CheckoutRacingViewModelTests: TestCase {
  private let vm: CheckoutRacingViewModelType = CheckoutRacingViewModel()

  private let goToThanks = TestObserver<Void, NoError>()
  private let showFailureAlert = TestObserver<String, NoError>()

  override func setUp() {
    super.setUp()

    self.vm.outputs.goToThanks.observe(self.goToThanks.observer)
    self.vm.outputs.showFailureAlert.observe(self.showFailureAlert.observer)
  }

  func testApiError() {
    withEnvironment(apiService: MockService(fetchCheckoutError: .couldNotParseJSON)) {
      self.vm.inputs.configureWith(url: racingURL())
      self.goToThanks.assertDidNotEmitValue()
      self.showFailureAlert.assertDidNotEmitValue()

      // Attempts up to 10 times, with one second delay before each attempt
      self.scheduler.advanceByInterval(9)
      self.goToThanks.assertDidNotEmitValue()
      self.showFailureAlert.assertDidNotEmitValue()

      self.scheduler.advanceByInterval(1)
      self.goToThanks.assertDidNotEmitValue()
      self.showFailureAlert.assertValues([Strings.project_checkout_finalizing_timeout_message()])
    }
  }

  func testAuthorizingThenSuccessful() {
    withEnvironment(apiService: MockService(fetchCheckoutResponse: .authorizing)) {
      self.vm.inputs.configureWith(url: racingURL())
      self.goToThanks.assertDidNotEmitValue()
      self.showFailureAlert.assertDidNotEmitValue()

      self.scheduler.advanceByInterval(1)
      self.goToThanks.assertDidNotEmitValue()
      self.showFailureAlert.assertDidNotEmitValue()

      withEnvironment(apiService: MockService(fetchCheckoutResponse: .successful)) {
        self.scheduler.advanceByInterval(1)
        self.goToThanks.assertValueCount(1)
        self.showFailureAlert.assertDidNotEmitValue()
      }
    }
  }

  func testFailed() {
    let envelope = CheckoutEnvelope.failed
    withEnvironment(apiService: MockService(fetchCheckoutResponse: envelope)) {
      self.vm.inputs.configureWith(url: racingURL())
      self.goToThanks.assertDidNotEmitValue()
      self.showFailureAlert.assertDidNotEmitValue()

      self.scheduler.advanceByInterval(1)
      self.goToThanks.assertDidNotEmitValue()
      self.showFailureAlert.assertValues([envelope.stateReason])
    }
  }

  func testStuckVerifying() {
    withEnvironment(apiService: MockService(fetchCheckoutResponse: .verifying)) {
      self.vm.inputs.configureWith(url: racingURL())

      // Attempts up to 10 times, with one second delay before each attempt
      self.scheduler.advanceByInterval(9)
      self.goToThanks.assertDidNotEmitValue()
      self.showFailureAlert.assertDidNotEmitValue()

      self.scheduler.advanceByInterval(1)
      self.goToThanks.assertDidNotEmitValue()
      self.showFailureAlert.assertValues([Strings.project_checkout_finalizing_timeout_message()])
    }
  }

  func testVerifyingThenSuccessful() {
    withEnvironment(apiService: MockService(fetchCheckoutResponse: .verifying)) {
      self.vm.inputs.configureWith(url: racingURL())
      self.goToThanks.assertDidNotEmitValue()
      self.showFailureAlert.assertDidNotEmitValue()

      self.scheduler.advanceByInterval(1)
      self.goToThanks.assertDidNotEmitValue()
      self.showFailureAlert.assertDidNotEmitValue()

      withEnvironment(apiService: MockService(fetchCheckoutResponse: .successful)) {
        self.scheduler.advanceByInterval(1)
        self.goToThanks.assertValueCount(1)
        self.showFailureAlert.assertDidNotEmitValue()
      }
    }
  }

  func testSuccessful() {
    withEnvironment(apiService: MockService(fetchCheckoutResponse: .successful)) {
      self.vm.inputs.configureWith(url: racingURL())
      self.goToThanks.assertDidNotEmitValue()
        self.showFailureAlert.assertDidNotEmitValue()

      self.scheduler.advanceByInterval(1)
      self.goToThanks.assertValueCount(1)
      self.showFailureAlert.assertDidNotEmitValue()
    }
  }
}

private func racingURL() -> NSURL {
  return NSURL(string: "https://www.kickstarter.com/projects/creator/project/checkouts/1")!
}
