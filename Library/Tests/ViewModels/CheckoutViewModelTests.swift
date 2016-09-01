import XCTest
@testable import Library
@testable import KsApi
@testable import ReactiveExtensions_TestHelpers
import Result
import KsApi
import Prelude

final class CheckoutViewModelTests: TestCase {
  private let vm: CheckoutViewModelType = CheckoutViewModel()

  private let closeLoginTout = TestObserver<Void, NoError>()
  private let openLoginTout = TestObserver<Void, NoError>()
  private let goToSafariBrowser = TestObserver<NSURL, NoError>()
  private let goToThanks = TestObserver<Project, NoError>()
  private let goToWebModal = TestObserver<NSURLRequest, NoError>()
  private let popViewController = TestObserver<Void, NoError>()
  private let showFailureAlert = TestObserver<String, NoError>()
  private let webViewLoadRequestIsPrepared = TestObserver<Bool, NoError>()
  private let webViewLoadRequestURL = TestObserver<String, NoError>()

  override func setUp() {
    super.setUp()

    self.vm.outputs.closeLoginTout.observe(self.closeLoginTout.observer)
    self.vm.outputs.openLoginTout.observe(self.openLoginTout.observer)
    self.vm.outputs.goToSafariBrowser.observe(self.goToSafariBrowser.observer)
    self.vm.outputs.goToThanks.observe(self.goToThanks.observer)
    self.vm.outputs.goToWebModal.observe(self.goToWebModal.observer)
    self.vm.outputs.popViewController.observe(self.popViewController.observer)
    self.vm.outputs.showFailureAlert.observe(self.showFailureAlert.observer)
    self.vm.outputs.webViewLoadRequest
      .map { AppEnvironment.current.apiService.isPrepared(request: $0) }
      .observe(self.webViewLoadRequestIsPrepared.observer)
    self.vm.outputs.webViewLoadRequest
      .map { request -> String? in
        // Trim query parameters
        guard let url = request.URL else { return nil }
        guard let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: false) else { return nil }
        components.query = nil
        return components.string
      }
      .ignoreNil()
      .observe(self.webViewLoadRequestURL.observer)
  }

  func testCancelButtonPopsViewController() {
    let project = Project.template

    self.vm.inputs.configureWith(project: project, reward: nil, intent: .new)
    self.vm.inputs.viewDidLoad()

    // 1: Show reward and shipping form
    self.webViewLoadRequestIsPrepared.assertValues([true])
    self.webViewLoadRequestURL.assertValues([newPledgeURL(project: project)])

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(
        withRequest: newPledgeRequest(project: project).prepared(),
        navigationType: .Other
      )
    )
    XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

    // 2: Cancel button tapped
    self.popViewController.assertDidNotEmitValue()
    XCTAssertEqual([], self.trackingClient.events)

    self.vm.inputs.cancelButtonTapped()
    self.popViewController.assertValueCount(1)
    XCTAssertEqual(["Checkout Cancel", "Canceled Checkout"],
                   self.trackingClient.events, "Cancel event and its deprecated version are tracked")
  }

  func testCancelPledge() {
    let project = Project.template
    withEnvironment(currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      self.vm.inputs.configureWith(project: project, reward: nil, intent: .manage)
      self.vm.inputs.viewDidLoad()

      // 1: Show reward and shipping form
      self.webViewLoadRequestIsPrepared.assertValues([true])
      self.webViewLoadRequestURL.assertValues([editPledgeURL(project: project)])

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: editPledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Click cancel link
      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: cancelPledgeRequest(project: project),
          navigationType: .LinkClicked
        ),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [editPledgeURL(project: project), cancelPledgeURL(project: project)]
      )
      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: cancelPledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 3: Confirm cancellation
      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project),
          navigationType: .FormSubmitted
        ),
        "Not prepared"
      )
      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [editPledgeURL(project: project), cancelPledgeURL(project: project), pledgeURL(project: project)]
      )

      // 4: Redirect to project, view controller popped
      self.popViewController.assertDidNotEmitValue()
      XCTAssertEqual([], self.trackingClient.events)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: projectRequest(project: project), navigationType: .Other)
      )
      XCTAssertEqual(["Checkout Cancel", "Canceled Checkout"], self.trackingClient.events)
      self.popViewController.assertValueCount(1)
    }
  }

  func testChangePaymentMethod() {
    let project = Project.template
    withEnvironment(currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      self.vm.inputs.configureWith(project: project, reward: nil, intent: .manage)
      self.vm.inputs.viewDidLoad()

      // 1: Show reward and shipping form
      self.webViewLoadRequestIsPrepared.assertValues([true])
      self.webViewLoadRequestURL.assertValues([editPledgeURL(project: project)])

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: editPledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Click change payment method button
      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: changePaymentMethodRequest(project: project),
          navigationType: .FormSubmitted
        ),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [editPledgeURL(project: project), changePaymentMethodURL(project: project)]
      )
      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: changePaymentMethodRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 3: Redirect to new payments form
      self.webViewLoadRequestURL.assertValueCount(2)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [editPledgeURL(project: project), changePaymentMethodURL(project: project), newPaymentsURL()]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest().prepared(), navigationType: .Other)
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 4: Pledge with new card
      self.webViewLoadRequestURL.assertValueCount(3)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: paymentsRequest(), navigationType: .FormSubmitted),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [
          editPledgeURL(project: project),
          changePaymentMethodURL(project: project),
          newPaymentsURL(),
          paymentsURL()
        ]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: paymentsRequest().prepared(), navigationType: .Other)
      )

      // 5: Redirect to thanks
      self.goToThanks.assertDidNotEmitValue()
      self.webViewLoadRequestURL.assertValueCount(4)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(
            project: project, racing: false),
            navigationType: .Other
        ),
        "Not prepared"
      )
      self.goToThanks.assertValueCount(1)
    }
  }

  func testLoggedInUserPledgingWithNewCard() {
    let project = Project.template
    withEnvironment(currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      self.vm.inputs.configureWith(project: project, reward: nil, intent: .new)
      self.vm.inputs.viewDidLoad()

      // 1: Show reward and shipping form
      self.webViewLoadRequestIsPrepared.assertValues([true])
      self.webViewLoadRequestURL.assertValues([newPledgeURL(project: project)])

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: newPledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Submit reward and shipping form
      self.webViewLoadRequestURL.assertValueCount(1)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project),
          navigationType: .FormSubmitted
        ),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPledgeURL(project: project), pledgeURL(project: project)]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )

      // 3: Redirect to new payments form
      self.webViewLoadRequestURL.assertValueCount(2)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPledgeURL(project: project), pledgeURL(project: project), newPaymentsURL()]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest().prepared(), navigationType: .Other)
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 4: Pledge with new card
      self.webViewLoadRequestURL.assertValueCount(3)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: paymentsRequest(), navigationType: .FormSubmitted),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [
          newPledgeURL(project: project),
          pledgeURL(project: project),
          newPaymentsURL(),
          paymentsURL()
        ]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: paymentsRequest().prepared(), navigationType: .Other)
      )

      // 5: Redirect to thanks
      self.goToThanks.assertDidNotEmitValue()
      self.webViewLoadRequestURL.assertValueCount(4)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(project: project, racing: false),
          navigationType: .Other
        ),
        "Not prepared"
      )
      self.goToThanks.assertValueCount(1)
    }
  }

  func testLoggedInUserPledgingWithStoredCard() {
    let project = Project.template
    withEnvironment(currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      self.vm.inputs.configureWith(project: project, reward: nil, intent: .new)
      self.vm.inputs.viewDidLoad()

      // 1: Show reward and shipping form
      self.webViewLoadRequestIsPrepared.assertValues([true])
      self.webViewLoadRequestURL.assertValues([newPledgeURL(project: project)])

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: newPledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Submit reward and shipping form
      self.webViewLoadRequestURL.assertValueCount(1)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project),
          navigationType: .FormSubmitted
        ),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPledgeURL(project: project), pledgeURL(project: project)]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )

      // 3: Redirect to new payments form
      self.webViewLoadRequestURL.assertValueCount(2)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPledgeURL(project: project), pledgeURL(project: project), newPaymentsURL()]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest().prepared(), navigationType: .Other)
      )

      // 4: Pledge with stored card
      self.webViewLoadRequestURL.assertValueCount(3)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: useStoredCardRequest(), navigationType: .FormSubmitted),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [
          newPledgeURL(project: project),
          pledgeURL(project: project),
          newPaymentsURL(),
          useStoredCardURL()
        ]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: useStoredCardRequest().prepared(), navigationType: .Other)
      )

      // 5: Redirect to thanks
      self.goToThanks.assertDidNotEmitValue()
      self.webViewLoadRequestURL.assertValueCount(4)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(project: project, racing: false),
          navigationType: .Other
        ),
        "Not prepared"
      )
      self.goToThanks.assertValueCount(1)
    }
  }

  func testLoginDuringCheckout() {
    let project = Project.template

    self.vm.inputs.configureWith(project: project, reward: nil, intent: .new)
    self.vm.inputs.viewDidLoad()

    // 1: Show reward and shipping form
    self.webViewLoadRequestIsPrepared.assertValues([true])
    self.webViewLoadRequestURL.assertValues([newPledgeURL(project: project)])

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(
        withRequest: newPledgeRequest(project: project).prepared(),
        navigationType: .Other
      )
    )
    XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

    // 2: Submit reward and shipping form
    self.webViewLoadRequestURL.assertValueCount(1)

    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(
        withRequest: pledgeRequest(project: project),
        navigationType: .FormSubmitted
      ),
      "Not prepared"
    )

    self.webViewLoadRequestIsPrepared.assertValues([true, true])
    self.webViewLoadRequestURL.assertValues(
      [newPledgeURL(project: project), pledgeURL(project: project)]
    )

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(
        withRequest: pledgeRequest(project: project).prepared(),
        navigationType: .Other
      )
    )

    // 3: Interrupt checkout for login/signup
    self.openLoginTout.assertDidNotEmitValue()

    XCTAssertFalse(self.vm.inputs.shouldStartLoad(withRequest: signupRequest(), navigationType: .Other))
    self.openLoginTout.assertValueCount(1)

    // 4: Login
    AppEnvironment.login(.init(accessToken: "deadbeef", user: User.template))
    self.closeLoginTout.assertDidNotEmitValue()

    self.vm.inputs.userSessionStarted()
    self.closeLoginTout.assertValueCount(1)

    // 5: Attempt pledge request again
    self.webViewLoadRequestURL.assertValues(
      [newPledgeURL(project: project), pledgeURL(project: project), pledgeURL(project: project)],
      "Attempt pledge request again, now that user is logged in"
    )

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(
        withRequest: pledgeRequest(project: project).prepared(),
        navigationType: .Other
      )
    )
    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
      "Not prepared"
    )
    self.webViewLoadRequestURL.assertValues(
      [
        newPledgeURL(project: project),
        pledgeURL(project: project),
        pledgeURL(project: project),
        newPaymentsURL()
      ]
    )
    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest().prepared(), navigationType: .Other)
    )

    // The rest of the checkout flow is the same as if the user had been logged in at the beginning,
    // so no need for further tests.
  }

  func testManagePledge() {
    let project = Project.template
    withEnvironment(currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      self.vm.inputs.configureWith(project: project, reward: nil, intent: .manage)
      self.vm.inputs.viewDidLoad()

      // 1: Show reward and shipping form
      self.webViewLoadRequestIsPrepared.assertValues([true])
      self.webViewLoadRequestURL.assertValues([editPledgeURL(project: project)])

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: editPledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Submit reward and shipping form
      self.webViewLoadRequestURL.assertValueCount(1)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project),
          navigationType: .FormSubmitted
        ),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [editPledgeURL(project: project), pledgeURL(project: project)]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )

      // 3: Redirect to thanks
      self.goToThanks.assertDidNotEmitValue()

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(project: project, racing: false),
          navigationType: .Other
        ),
        "Not prepared"
      )
      self.goToThanks.assertValueCount(1)
    }
  }

  func testModalRequests() {
    let project = Project.template
    self.vm.inputs.configureWith(project: project, reward: nil, intent: .new)
    self.vm.inputs.viewDidLoad()

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(withRequest: newPledgeRequest(project: project).prepared(),
        navigationType: .Other)
    )
    self.goToWebModal.assertValueCount(0)

    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(withRequest: creatorRequest(project: project),
        navigationType: .LinkClicked)
    )
    self.goToSafariBrowser.assertValueCount(0)
    self.goToWebModal.assertValueCount(1)

    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(withRequest: privacyPolicyRequest(project: project),
        navigationType: .LinkClicked)
    )
    self.goToSafariBrowser.assertValueCount(1)
    self.goToWebModal.assertValueCount(1)
  }

  func testRacingFailure() {
    let failedEnvelope = CheckoutEnvelope.failed
    let project = Project.template
    withEnvironment(apiService: MockService(fetchCheckoutResponse: failedEnvelope), currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      self.vm.inputs.configureWith(project: project, reward: nil, intent: .new)
      self.vm.inputs.viewDidLoad()

      // 1: Show reward and shipping form
      self.webViewLoadRequestIsPrepared.assertValues([true])
      self.webViewLoadRequestURL.assertValues([newPledgeURL(project: project)])

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: newPledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Submit reward and shipping form
      self.webViewLoadRequestURL.assertValueCount(1)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project),
          navigationType: .FormSubmitted
        ),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPledgeURL(project: project), pledgeURL(project: project)]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )

      // 3: Redirect to new payments form
      self.webViewLoadRequestURL.assertValueCount(2)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPledgeURL(project: project), pledgeURL(project: project), newPaymentsURL()]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest().prepared(), navigationType: .Other)
      )

      // 4: Pledge with stored card
      self.webViewLoadRequestURL.assertValueCount(3)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: useStoredCardRequest(), navigationType: .FormSubmitted),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [
          newPledgeURL(project: project),
          pledgeURL(project: project),
          newPaymentsURL(),
          useStoredCardURL()
        ]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: useStoredCardRequest().prepared(), navigationType: .Other)
      )

      // 5: Checkout is racing, delay a second to check status (failed!), then display failure alert.
      self.goToThanks.assertDidNotEmitValue()
      self.webViewLoadRequestURL.assertValueCount(4)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(project: project, racing: true),
          navigationType: .Other
        )
      )
      self.showFailureAlert.assertValueCount(0)

      self.scheduler.advanceByInterval(1)
      self.goToThanks.assertValueCount(0)
      self.showFailureAlert.assertValues([failedEnvelope.stateReason])

      // 6: Alert dismissed, pop view controller
      self.popViewController.assertValueCount(0)

      self.vm.inputs.failureAlertButtonTapped()
      self.popViewController.assertValueCount(1)
    }
  }

  func testRacingSuccess() {
    let envelope = CheckoutEnvelope.successful
    let project = Project.template
    withEnvironment(apiService: MockService(fetchCheckoutResponse: envelope), currentUser: .template) {
      self.webViewLoadRequestURL.assertDidNotEmitValue()

      self.vm.inputs.configureWith(project: project, reward: nil, intent: .new)
      self.vm.inputs.viewDidLoad()

      // 1: Show reward and shipping form
      self.webViewLoadRequestIsPrepared.assertValues([true])
      self.webViewLoadRequestURL.assertValues([newPledgeURL(project: project)])

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: newPledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )
      XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

      // 2: Submit reward and shipping form
      self.webViewLoadRequestURL.assertValueCount(1)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project),
          navigationType: .FormSubmitted
        ),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPledgeURL(project: project), pledgeURL(project: project)]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(
          withRequest: pledgeRequest(project: project).prepared(),
          navigationType: .Other
        )
      )

      // 3: Redirect to new payments form
      self.webViewLoadRequestURL.assertValueCount(2)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest(), navigationType: .Other),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [newPledgeURL(project: project), pledgeURL(project: project), newPaymentsURL()]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: newPaymentsRequest().prepared(), navigationType: .Other)
      )

      // 4: Pledge with stored card
      self.webViewLoadRequestURL.assertValueCount(3)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(withRequest: useStoredCardRequest(), navigationType: .FormSubmitted),
        "Not prepared"
      )

      self.webViewLoadRequestIsPrepared.assertValues([true, true, true, true])
      self.webViewLoadRequestURL.assertValues(
        [
          newPledgeURL(project: project),
          pledgeURL(project: project),
          newPaymentsURL(),
          useStoredCardURL()
        ]
      )

      XCTAssertTrue(
        self.vm.inputs.shouldStartLoad(withRequest: useStoredCardRequest().prepared(), navigationType: .Other)
      )

      // 5: Checkout is racing, delay a second to check status (successful!), then go to thanks.
      self.goToThanks.assertDidNotEmitValue()
      self.webViewLoadRequestURL.assertValueCount(4)

      XCTAssertFalse(
        self.vm.inputs.shouldStartLoad(
          withRequest: thanksRequest(project: project, racing: true),
          navigationType: .Other
        )
      )

      self.scheduler.advanceByInterval(1)
      self.showFailureAlert.assertValueCount(0)
      self.goToThanks.assertValueCount(1)
    }
  }

  func testProjectRequestPopsViewController() {
    let project = Project.template

    self.vm.inputs.configureWith(project: project, reward: nil, intent: .new)
    self.vm.inputs.viewDidLoad()

    // 1: Show reward and shipping form
    self.webViewLoadRequestIsPrepared.assertValues([true])
    self.webViewLoadRequestURL.assertValues([newPledgeURL(project: project)])

    XCTAssertTrue(
      self.vm.inputs.shouldStartLoad(
        withRequest: newPledgeRequest(project: project).prepared(),
        navigationType: .Other
      )
    )
    XCTAssertTrue(self.vm.inputs.shouldStartLoad(withRequest: stripeRequest(), navigationType: .Other))

    // 2: Project link clicked
    self.popViewController.assertDidNotEmitValue()
    XCTAssertEqual([], self.trackingClient.events)

    XCTAssertFalse(
      self.vm.inputs.shouldStartLoad(
        withRequest: projectRequest(project: project),
        navigationType: .LinkClicked
      )
    )

    self.popViewController.assertValueCount(1)
    XCTAssertEqual(["Checkout Cancel", "Canceled Checkout"],
                   self.trackingClient.events, "Cancel event and its deprecated version are tracked")
  }
}

internal extension NSURLRequest {
  internal func prepared() -> NSURLRequest {
    return AppEnvironment.current.apiService.preparedRequest(forRequest: self)
  }
}

private func cancelPledgeRequest(project project: Project) -> NSURLRequest {
  return NSURLRequest(URL: NSURL(string: cancelPledgeURL(project: project))!)
}

private func cancelPledgeURL(project project: Project) -> String {
  return "\(project.urls.web.project)/pledge/destroy"
}

private func changePaymentMethodRequest(project project: Project) -> NSURLRequest {
  return NSURLRequest(URL: NSURL(string: changePaymentMethodURL(project: project))!)
}

private func changePaymentMethodURL(project project: Project) -> String {
  return "\(project.urls.web.project)/pledge/change_method"
}

private func creatorRequest(project project: Project) -> NSURLRequest {
  return NSURLRequest(URL: NSURL(string: creatorURL(project: project))!)
}

private func creatorURL(project project: Project) -> String {
  return "\(project.urls.web.project)/pledge/big_print?modal=true#creator"
}

private func editPledgeRequest(project project: Project) -> NSURLRequest {
  return NSURLRequest(URL: NSURL(string: editPledgeURL(project: project))!)
}

private func editPledgeURL(project project: Project) -> String {
  return "\(project.urls.web.project)/pledge/edit"
}

private func newPaymentsRequest() -> NSURLRequest {
  return NSURLRequest(URL: NSURL(string: newPaymentsURL())!)
}

private func newPaymentsURL() -> String {
  return "https://www.kickstarter.com/checkouts/1/payments/new"
}

private func newPledgeRequest(project project: Project) -> NSURLRequest {
  return NSURLRequest(URL: NSURL(string: newPledgeURL(project: project))!)
}

private func newPledgeURL(project project: Project) -> String {
  return "\(project.urls.web.project)/pledge/new"
}

private func paymentsRequest() -> NSURLRequest {
  let request = NSMutableURLRequest(URL: NSURL(string: paymentsURL())!)
  request.HTTPMethod = "POST"
  return request
}

private func paymentsURL() -> String {
  return "https://www.kickstarter.com/checkouts/1/payments"
}

private func pledgeRequest(project project: Project) -> NSURLRequest {
  let request = NSMutableURLRequest(URL: NSURL(string: pledgeURL(project: project))!)
  request.HTTPMethod = "POST"
  return request
}

private func pledgeURL(project project: Project) -> String {
  return "\(project.urls.web.project)/pledge"
}

private func privacyPolicyRequest(project project: Project) -> NSURLRequest {
  return NSURLRequest(URL:
    NSURL(string: privacyPolicyURL(project: project))!
  )
}

private func privacyPolicyURL(project project: Project) -> String {
  return "\(project.urls.web.project)/privacy?modal=true&ref=checkout_payment_sources_page"
}

private func projectRequest(project project: Project) -> NSURLRequest {
  return NSURLRequest(URL: NSURL(string: project.urls.web.project)!)
}

private func signupRequest() -> NSURLRequest {
  return NSURLRequest(URL: NSURL(string: "https://www.kickstarter.com/signup?context=checkout&then=%2Ffoo")!)
}

private func stripeRequest() -> NSURLRequest {
  return NSURLRequest(URL: NSURL(string: stripeURL())!)
}

private func stripeURL() -> String {
  return "https://js.stripe.com/v2/channel.html"
}

private func thanksRequest(project project: Project, racing: Bool) -> NSURLRequest {
  return NSURLRequest(URL: NSURL(string: thanksURL(project: project, racing: racing))!)
}

private func thanksURL(project project: Project, racing: Bool) -> String {
  return "\(project.urls.web.project)/checkouts/1/thanks\(racing ? "?racing=1" : "")"
}

private func useStoredCardRequest() -> NSURLRequest {
  return NSURLRequest(URL: NSURL(string: useStoredCardURL())!)
}

private func useStoredCardURL() -> String {
  return "https://www.kickstarter.com/checkouts/1/payments/use_stored_card"
}
