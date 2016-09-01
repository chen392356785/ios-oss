import KsApi
import Prelude
import ReactiveCocoa
import ReactiveExtensions
import Result

internal struct CheckoutData {
  internal let intent: CheckoutIntent
  internal let project: Project
  internal let reward: Reward?
}

internal struct RequestData {
  internal let request: NSURLRequest
  internal let navigation: Navigation?
  internal let shouldStartLoad: Bool
  internal let webViewNavigationType: UIWebViewNavigationType
}

public protocol CheckoutViewModelInputs {
  /// Call when the back button is tapped.
  func cancelButtonTapped()

  /// Call to set the project, reward, and why the user is checking out.
  func configureWith(project project: Project, reward: Reward?, intent: CheckoutIntent)

  /// Call when the failure alert OK button is tapped.
  func failureAlertButtonTapped()

  /// Call when the webview decides whether to load a request.
  func shouldStartLoad(withRequest request: NSURLRequest, navigationType: UIWebViewNavigationType) -> Bool

  /// Call when a user session has started.
  func userSessionStarted()

  /// Call when the view loads.
  func viewDidLoad()
}

public protocol CheckoutViewModelOutputs {
  /// Emits when the login tout should be closed.
  var closeLoginTout: Signal<Void, NoError> { get }

  /// Emits when we should open a safari browser with the URL.
  var goToSafariBrowser: Signal<NSURL, NoError> { get }

  /// Emits when the thanks screen should be loaded.
  var goToThanks: Signal<Project, NoError> { get }

  /// Emits when the web modal should be loaded.
  var goToWebModal: Signal<NSURLRequest, NoError> { get }

  /// Emits when the login tout should be opened.
  var openLoginTout: Signal<Void, NoError> { get }

  /// Emits when the view controller should be popped.
  var popViewController: Signal<Void, NoError> { get }

  /// Emits when an alert should be shown indicating the pledge was not successful.
  var showFailureAlert: Signal<String, NoError> { get }

  /// Emits a request that should be loaded into the webview.
  var webViewLoadRequest: Signal<NSURLRequest, NoError> { get }
}

public protocol CheckoutViewModelType: CheckoutViewModelInputs, CheckoutViewModelOutputs {
  var inputs: CheckoutViewModelInputs { get }
  var outputs: CheckoutViewModelOutputs { get }
}

public final class CheckoutViewModel: CheckoutViewModelType {

  private let checkoutRacingViewModel: CheckoutRacingViewModelType = CheckoutRacingViewModel()

  // swiftlint:disable function_body_length
  public init() {
    let checkoutData = self.checkoutDataProperty.signal.ignoreNil()
    let failureAlertButtonTapped = self.failureAlertButtonTappedProperty.signal
    let userSessionStarted = self.userSessionStartedProperty.signal

    let initialRequest = checkoutData
      .takeWhen(self.viewDidLoadProperty.signal)
      .map(buildInitialRequest)
      .ignoreNil()

    let requestData = self.shouldStartLoadProperty.signal.ignoreNil()
      .map { request, navigationType -> RequestData in
        let navigation = Navigation.match(request)

        let shouldStartLoad = isLoadableByWebView(request: request, navigation: navigation)

        return RequestData(request: request,
          navigation: navigation,
          shouldStartLoad: shouldStartLoad,
          webViewNavigationType: navigationType)
    }

    let projectRequest = requestData
      .filter { requestData in
        if let navigation = requestData.navigation,
          case .project(_, .root, _) = navigation { return true }
        return false
      }
      .ignoreValues()

    let webViewRequest = requestData
      .filter { requestData in
        // Allow through requests that the web view can load once they're prepared.
        !requestData.shouldStartLoad && isNavigationLoadedByWebView(navigation: requestData.navigation)
      }
      .map { $0.request }

    let modalRequestOrSafariRequest = requestData
      .filter(isModal)
      .map { requestData -> Either<NSURLRequest, NSURLRequest> in
        if let navigation = requestData.navigation,
          case .project(_, .pledge(.bigPrint), _) = navigation { return Either.left(requestData.request) }
        return Either.right(requestData.request)
    }

    let retryAfterSessionStartedRequest = requestData
      .combinePrevious()
      .takeWhen(userSessionStarted)
      .map { previous, _ in previous.request }

    let thanksRequestOrRacingRequest = requestData
      .map { requestData -> Either<NSURLRequest, NSURLRequest>? in
        guard let navigation = requestData.navigation else { return nil }
        if case .project(_, .checkout(_, .thanks(let racing)), _) = navigation {
          guard let r = racing else { return Either.left(requestData.request) }
          return r ? Either.right(requestData.request) : Either.left(requestData.request)
        }
        return nil
      }
      .ignoreNil()

    let thanksRequest = thanksRequestOrRacingRequest
      .map { $0.left }
      .ignoreNil()
      .ignoreValues()

    let racingRequest = thanksRequestOrRacingRequest
      .map { $0.right }
      .ignoreNil()

    self.closeLoginTout = userSessionStarted

    self.goToSafariBrowser = modalRequestOrSafariRequest
      .map { $0.right?.URL }
      .ignoreNil()

    let thanksRequestOrRacingSuccessful = Signal.merge(
      thanksRequest,
      self.checkoutRacingViewModel.outputs.goToThanks
    )

    self.goToThanks = checkoutData
      .map { $0.project }
      .takeWhen(thanksRequestOrRacingSuccessful)

    self.goToWebModal = modalRequestOrSafariRequest
      .map { $0.left }
      .ignoreNil()

    self.openLoginTout = requestData
      .filter { $0.navigation == .signup }
      .ignoreValues()

    let checkoutCancelled = Signal.merge(
      projectRequest,
      self.cancelButtonTappedProperty.signal
      )

    self.popViewController = Signal.merge(checkoutCancelled, failureAlertButtonTapped)

    self.shouldStartLoadResponseProperty <~ requestData
      .map { $0.shouldStartLoad }

    self.webViewLoadRequest = Signal.merge(
      initialRequest,
      retryAfterSessionStartedRequest,
      webViewRequest
      )
      .map { AppEnvironment.current.apiService.preparedRequest(forRequest: $0) }

    racingRequest
      .observeNext { [weak self] request in
        guard let url = request.URL?.URLByDeletingLastPathComponent else { return }
        self?.checkoutRacingViewModel.inputs.configureWith(url: url)
    }

    checkoutCancelled.observeNext { AppEnvironment.current.koala.trackCheckoutCancel() }
  }
  // swiftlint:enable function_body_length

  private let cancelButtonTappedProperty = MutableProperty()
  public func cancelButtonTapped() { self.cancelButtonTappedProperty.value = () }

  private let checkoutDataProperty = MutableProperty<(CheckoutData)?>(nil)
  public func configureWith(project project: Project, reward: Reward?, intent: CheckoutIntent) {
    self.checkoutDataProperty.value = CheckoutData(intent: intent, project: project, reward: reward)
  }

  private let failureAlertButtonTappedProperty = MutableProperty()
  public func failureAlertButtonTapped() { self.failureAlertButtonTappedProperty.value = () }

  private let shouldStartLoadProperty = MutableProperty<(NSURLRequest, UIWebViewNavigationType)?>(nil)
  private let shouldStartLoadResponseProperty = MutableProperty(false)
  public func shouldStartLoad(withRequest request: NSURLRequest,
                                          navigationType: UIWebViewNavigationType) -> Bool {
    self.shouldStartLoadProperty.value = (request, navigationType)
    return self.shouldStartLoadResponseProperty.value
  }

  private let userSessionStartedProperty = MutableProperty()
  public func userSessionStarted() { self.userSessionStartedProperty.value = () }

  private let viewDidLoadProperty = MutableProperty()
  public func viewDidLoad() { self.viewDidLoadProperty.value = () }

  public let closeLoginTout: Signal<Void, NoError>
  public let openLoginTout: Signal<Void, NoError>
  public let goToSafariBrowser: Signal<NSURL, NoError>
  public let goToThanks: Signal<Project, NoError>
  public let goToWebModal: Signal<NSURLRequest, NoError>
  public let popViewController: Signal<Void, NoError>
  public var showFailureAlert: Signal<String, NoError> {
    return self.checkoutRacingViewModel.outputs.showFailureAlert
  }
  public let webViewLoadRequest: Signal<NSURLRequest, NoError>

  public var inputs: CheckoutViewModelInputs { return self }
  public var outputs: CheckoutViewModelOutputs { return self }
}

private func buildInitialRequest(checkoutData: CheckoutData) -> NSURLRequest? {
  guard let baseURL = NSURL(string: checkoutData.project.urls.web.project) else { return nil }
  var pathToAppend: String
  switch checkoutData.intent {
  case .manage:
    pathToAppend = "pledge/edit"
  case .new:
    pathToAppend = "pledge/new"
  }
  return NSURLRequest(URL: baseURL.URLByAppendingPathComponent(pathToAppend))
}

private func isLoadableByWebView(request request: NSURLRequest, navigation: Navigation?) -> Bool {
  let preparedWebViewRequest = isNavigationLoadedByWebView(navigation: navigation)
    && AppEnvironment.current.apiService.isPrepared(request: request)
  return preparedWebViewRequest || isStripeRequest(request: request)
}

private func isModal(requestData requestData: RequestData) -> Bool {
  guard let url = requestData.request.URL else { return false }
  guard let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: false) else { return false }
  guard let queryItems = components.queryItems else { return false }

  return queryItems.filter { $0.name == "modal" }.first?.value == "true"
}

private func isNavigationLoadedByWebView(navigation navigation: Navigation?) -> Bool {
  guard let nav = navigation else { return false }
  switch nav {
  case
    .checkout(_, .payments(.new)),
    .checkout(_, .payments(.root)),
    .checkout(_, .payments(.useStoredCard)),
    .project(_, .pledge(.changeMethod), _),
    .project(_, .pledge(.destroy), _),
    .project(_, .pledge(.edit), _),
    .project(_, .pledge(.new), _),
    .project(_, .pledge(.root), _):
    return true
  default:
    return false
  }
}

private func isStripeRequest(request request: NSURLRequest) -> Bool {
  return request.URL?.host?.hasSuffix("stripe.com") == true
}
