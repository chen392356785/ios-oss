import Argo
import FirebaseAnalytics
import FirebaseDatabase
import Prelude
import ReactiveCocoa
import Result
import UIKit

public protocol LiveStreamViewControllerDelegate: class {
  func liveStreamStateChanged(controller: LiveStreamViewController, state: LiveStreamViewControllerState)

  func numberOfPeopleWatchingChanged(controller: LiveStreamViewController, numberOfPeople: Int)
}

public final class LiveStreamViewController: UIViewController {
  private var viewModel: LiveStreamViewModelType = LiveStreamViewModel()
  private var firebaseRef: FIRDatabaseReference?
  private var videoViewController: LiveVideoViewController?
  public weak var delegate: LiveStreamViewControllerDelegate?
  private var forceHLSTimerProducer: Disposable?

  public init(event: LiveStreamEvent, delegate: LiveStreamViewControllerDelegate) {
    super.init(nibName: nil, bundle: nil)

    self.delegate = delegate
    self.bindVM()
    self.viewModel.inputs.configureWith(event: event)
    self.viewModel.inputs.configureFirebaseApp(app: KsLiveApp.firebaseApp())
  }

  public required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
    return [.Portrait, .Landscape]
  }

  //swiftlint:disable function_body_length
  public func bindVM() {
    self.viewModel.outputs.createVideoViewController
      .observeForUI()
      .observeNext { [weak self] in
      self?.createVideoViewController($0)
    }

    self.viewModel.outputs.removeVideoViewController
      .observeForUI()
      .observeNext { [weak self] in
      self?.videoViewController?.destroy()
      self?.videoViewController = nil
    }

    self.viewModel.outputs.firebaseApp.observeNext { [weak self] in
      guard let firebaseRef = ($0 as? FIRApp).flatMap({
        FIRDatabase.database(app: $0).reference()
      }) else { return }

      firebaseRef.keepSynced(true)
      self?.viewModel.inputs.configureFirebaseDatabaseRef(ref: firebaseRef)
    }

    let refMapClosure: ((FirebaseDatabaseRefType, FirebaseRefConfig) ->
      (FIRDatabaseReference, FirebaseRefConfig)?) = {
        (ref, refConfig) -> (FIRDatabaseReference, FirebaseRefConfig)? in
        guard let ref = ref as? FIRDatabaseReference else { return nil }
        return (ref, refConfig)
    }

    self.viewModel.outputs.numberOfPeopleWatching.observeNext { [weak self] in
      guard let _self = self else { return }
      _self.forceHLSTimerProducer?.dispose()
      _self.delegate?.numberOfPeopleWatchingChanged(_self, numberOfPeople: $0)
    }

    self.viewModel.outputs.createGreenRoomObservers
      .map(refMapClosure)
      .ignoreNil()
      .observeNext { [weak self] in self?.createFirebaseGreenRoomObservers($0, refConfig: $1) }

    self.viewModel.outputs.createHLSObservers
      .map(refMapClosure)
      .ignoreNil()
      .observeNext { [weak self] in self?.createFirebaseHLSObservers($0, refConfig: $1) }

    self.viewModel.outputs.createNumberOfPeopleWatchingObservers
      .map(refMapClosure)
      .ignoreNil()
      .observeNext { [weak self] in self?.createFirebaseNumberOfPeopleWatchingObservers($0, refConfig: $1) }

    self.viewModel.outputs.createScaleNumberOfPeopleWatchingObservers
      .map(refMapClosure)
      .ignoreNil()
      .observeNext { [weak self] in
        self?.createFirebaseScaleNumberOfPeopleWatchingObservers($0, refConfig: $1) }

    self.viewModel.outputs.isReplayState.observeNext { [weak self] in
      if $0 { self?.viewModel.inputs.setGreenRoomActive(active: false) }
    }

    self.viewModel.outputs.liveStreamViewControllerState.observeNext { [weak self] in
      guard let _self = self else { return }
      self?.delegate?.liveStreamStateChanged(_self, state: $0)
    }

    self.forceHLSTimerProducer = timer(10, onScheduler: QueueScheduler(queue: dispatch_get_main_queue()))
      .take(1)
      .startWithNext { [weak self] in
        _ = $0
        self?.viewModel.inputs.forceUseHLS()
    }
  }
  //swiftlint:enable function_body_length

  public override func viewDidLoad() {
    super.viewDidLoad()

    self.viewModel.inputs.viewDidLoad()
  }

  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()

    guard let videoView = self.videoViewController?.view else { return }

    self.layoutVideoView(videoView)
  }

  deinit {
    self.videoViewController?.destroy()
    self.firebaseRef?.removeAllObservers()
  }

  // MARK: Firebase

  private func createFirebaseGreenRoomObservers(ref: FIRDatabaseReference, refConfig: FirebaseRefConfig) {
    let query = ref.child(refConfig.ref).queryOrderedByKey()

    query.observeEventType(.Value, withBlock: { [weak self] (snapshot) in
      guard let value = snapshot.value as? Bool else { return }
      self?.viewModel.inputs.setGreenRoomActive(active: !value)
    })
  }

  private func createFirebaseHLSObservers(ref: FIRDatabaseReference, refConfig: FirebaseRefConfig) {
    let query = ref.child(refConfig.ref).queryOrderedByKey()

    query.observeEventType(.Value, withBlock: { [weak self] (snapshot) in
      guard let value = snapshot.value as? String else { return }
      self?.viewModel.inputs.setHLSUrl(value)
    })
  }

  private func createFirebaseNumberOfPeopleWatchingObservers(ref: FIRDatabaseReference,
                                                             refConfig: FirebaseRefConfig) {
    let query = ref.child(refConfig.ref).queryOrderedByKey()

    query.observeEventType(.Value, withBlock: { [weak self] (snapshot) in
      guard let value = snapshot.value as? NSDictionary else { return }
      self?.viewModel.inputs.setNumberOfPeopleWatching(numberOfPeople: value.allKeys.count)
    })
  }

  private func createFirebaseScaleNumberOfPeopleWatchingObservers(ref: FIRDatabaseReference,
                                                             refConfig: FirebaseRefConfig) {
    let query = ref.child(refConfig.ref).queryOrderedByKey()

    query.observeEventType(.Value, withBlock: { [weak self] (snapshot) in
      guard let value = snapshot.value as? Int else { return }
      self?.viewModel.inputs.setScaleNumberOfPeopleWatching(numberOfPeople: value)
    })
  }

  // MARK: Video

  private func addChildVideoViewController(controller: UIViewController) {
    self.addChildViewController(controller)
    controller.didMoveToParentViewController(self)
    self.view.addSubview(controller.view)
  }

  private func layoutVideoView(view: UIView) {
    view.frame = self.view.bounds
  }

  private func createVideoViewController(liveStreamType: LiveStreamType) {
    let videoViewController = LiveVideoViewController(
      liveStreamType: liveStreamType, delegate: self)

    self.videoViewController = videoViewController
    self.addChildVideoViewController(videoViewController)
  }
}

extension LiveStreamViewController: LiveVideoViewControllerDelegate {
  public func playbackStateChanged(controller: LiveVideoViewController, state: LiveVideoPlaybackState) {
    self.viewModel.inputs.videoPlaybackStateChanged(state: state)
  }
}
