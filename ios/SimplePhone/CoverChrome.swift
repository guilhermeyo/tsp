import UIKit

/// Every pixel the cover draws: the line, the badge that counts it down, the
/// controls that appear once it is pinned or missed, and the picture you can
/// share.
///
/// Split from `QuoteScreen` so that file is about WHEN the cover exists and
/// this one about what it looks like. A constraint has no business sitting next
/// to the runloop timing of a handoff.
///
/// Nothing here owns state and nothing here knows what a button does: targets
/// and selectors arrive as arguments. That is the seam. `QuoteScreen` decides
/// behaviour, this decides appearance.
enum CoverChrome {
  /// Marks the controls a pinned cover or a return card adds, so they can be
  /// taken off again as a group. Any value that is not a tag anyone else uses;
  /// zero is every view's default and would match the whole screen.
  static let cardChromeTag = 0x5150

  /// Strips them. Safe on a cover that never had any.
  static func removeCardChrome(from container: UIView) {
    container.subviews.filter { $0.tag == cardChromeTag }.forEach { $0.removeFromSuperview() }
  }

  /// The countdown at the top of the cover: how long the phrase has left, and
  /// what a finger is doing about it.
  ///
  /// One ring with three things to say, in sequence and never at once, which is
  /// what lets it carry two opposite meanings without ambiguity:
  ///
  /// - **Draining.** The ring empties over the configured duration with the
  ///   seconds left written inside it. Time leaving, nobody doing anything.
  /// - **Held.** It freezes where the eye last saw it and the number gives way
  ///   to a pause. Time stopped, and it stays stopped for as long as the finger
  ///   is down. Nothing is being committed to yet.
  /// - **Closing.** Drag down and a second ring fills with the DISTANCE the
  ///   finger has travelled, thickening as it goes. It is a ruler, not a clock:
  ///   drag back up and it unwinds. Whole means pinned.
  /// - **Pinned.** Both rings go and the pause stays.
  ///
  /// BOTH RINGS SWEEP CLOCKWISE. Draining is the natural place to get that
  /// wrong: animating `strokeEnd` down from whole retracts the arc's leading
  /// edge ANTICLOCKWISE, which against a pin that fills clockwise reads as two
  /// unrelated animations arguing. `strokeStart` up from nothing eats the ring
  /// away from the same end the pin grows from, so both boundaries travel the
  /// same way and the second gesture looks like it continues the first.
  ///
  /// No disc behind it. The ring and the number are the whole of it, over the
  /// cover's own colour.
  ///
  /// Pause and not a padlock, deliberately. A padlock says you cannot leave,
  /// which is false: a tap, a drag sideways and the button all still work. A
  /// pause says nothing happens until you say so, which is what is actually
  /// true, and it is the same word the frozen ring is already saying.
  ///
  /// Takes no touches. It sits over the cover, and the cover is the thing
  /// listening for a finger.
  final class Badge: UIView {
    private static let ringRadius: CGFloat = 25
    /// Everything inside is laid out against this ONCE, at init: the ring's
    /// centre, the number's frame and the pause's centre. `addBadge` constrains
    /// the view to the same number, so the two must not drift apart.
    fileprivate static let side: CGFloat = 58
    private static let thin: CGFloat = 2
    private static let thick: CGFloat = 3.5

    /// The faint outline the two rings run along.
    private let track = CAShapeLayer()
    /// The countdown: starts whole, is eaten away clockwise.
    private let countdown = CAShapeLayer()
    /// The pin: starts at nothing, fills clockwise.
    private let pin = CAShapeLayer()
    private let pause = UIImageView()
    /// Shown in the pause's place once a sideways drag has gone far enough that
    /// lifting will go straight to the app.
    private let forward = UIImageView()
    private let number = UILabel()
    private var skipping = false

    /// When the countdown reaches nothing, on the same clock CoreAnimation uses.
    private var endsAt: CFTimeInterval = 0
    private var ticker: CADisplayLink?
    private let separator = Locale.current.decimalSeparator ?? "."

    init(config: QuoteCatalog.Config) {
      super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
      isUserInteractionEnabled = false

      let colour: UIColor = config.isDark ? .white : .black
      let centre = CGPoint(x: Self.side / 2, y: Self.side / 2)

      let circle = UIBezierPath(arcCenter: centre, radius: Self.ringRadius,
                                startAngle: -.pi / 2, endAngle: 1.5 * .pi,
                                clockwise: true).cgPath
      let rings: [(CAShapeLayer, CGFloat, CGFloat)] = [
        (track, 0.10, 1), (countdown, 0.30, 1), (pin, 0.75, 0),
      ]
      for (layer, alpha, end) in rings {
        layer.frame = bounds
        layer.path = circle
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = colour.withAlphaComponent(alpha).cgColor
        layer.lineWidth = Self.thin
        layer.lineCap = .round
        layer.strokeEnd = end
        self.layer.addSublayer(layer)
      }

      number.font = font(for: config, size: 14)
      number.textColor = colour.withAlphaComponent(0.75)
      number.textAlignment = .center
      number.frame = bounds
      // The full duration, standing still, which is what the snapshot carries
      // for the stretch before the app is drawing. Instant has nothing to count.
      number.text = config.holdSeconds > 0 ? text(config.holdSeconds) : nil
      addSubview(number)

      let symbol = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
      // Coloured into the image rather than left to `tintColor`, which a plain
      // UIImageView only honours for a template image. See `docs/native-notes.md`,
      // "SF Symbols in a UIImageView".
      for (view, name) in [(pause, "pause.fill"), (forward, "forward.fill")] {
        view.image = UIImage(systemName: name, withConfiguration: symbol)?
          .withTintColor(colour.withAlphaComponent(0.75), renderingMode: .alwaysOriginal)
        view.sizeToFit()
        view.center = centre
        view.alpha = 0
        addSubview(view)
      }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    deinit { ticker?.invalidate() }

    /// The phrase's own clock has started. Called when the cover becomes
    /// touchable, not when the relay began: see `docs/native-notes.md`,
    /// "A countdown that cannot lie".
    /// `total` is what the countdown was to begin with. It differs from
    /// `seconds` only when a relay is being resumed after an interruption, and
    /// the ring then picks the sweep up where it stopped rather than starting
    /// it over on a whole ring that has no time behind it.
    func drain(over seconds: TimeInterval, of total: TimeInterval) {
      guard seconds > 0, total > 0 else { return }
      // Before anything else. A resumed relay drains twice, and the link from
      // the first one would otherwise go on ticking forever with nothing to
      // stop it: `stopTicking` only ever holds the newest.
      stopTicking()
      countdown.removeAnimation(forKey: "sweep")
      countdown.opacity = 1
      number.alpha = 1
      skipping = false
      pause.alpha = 0
      forward.alpha = 0
      // Model value at the destination, so it simply stays there when the
      // animation ends rather than needing to be kept alive past its own life.
      countdown.strokeStart = 1
      let sweep = CABasicAnimation(keyPath: "strokeStart")
      sweep.fromValue = 1 - min(CGFloat(seconds / total), 1)
      sweep.toValue = 1
      sweep.duration = seconds
      // Linear, because it is a clock. Any easing here would be the ring
      // disagreeing with the timer it is drawing.
      sweep.timingFunction = CAMediaTimingFunction(name: .linear)
      countdown.add(sweep, forKey: "sweep")

      endsAt = CACurrentMediaTime() + seconds
      showRemaining()
      let link = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.tick))
      link.add(to: .main, forMode: .common)
      ticker = link
    }

    /// A finger arrived. Freeze, and wait to see whether it means anything by
    /// it. Nothing starts closing here: the pin is driven by the drag.
    func hold() {
      stopTicking()
      // Where the eye last saw it, not where the model says. Mid-animation the
      // two are a whole countdown apart. Removing the sweep is unconditional:
      // leaving it running whenever `presentation` came back nil would let the
      // ring carry on emptying behind a pause that says it stopped.
      let shown = countdown.presentation()?.strokeStart ?? countdown.strokeStart
      countdown.removeAnimation(forKey: "sweep")
      countdown.strokeStart = shown
      // A crossfade rather than a cut: the pin starts at nothing, so cutting
      // the countdown would leave the badge ringless for the first moments of
      // the very gesture it is meant to be reporting.
      let handover = CABasicAnimation(keyPath: "opacity")
      handover.fromValue = 1
      handover.toValue = 0
      handover.duration = 0.15
      countdown.opacity = 0
      countdown.add(handover, forKey: "handover")

      skipping = false
      pause.alpha = 0
      forward.alpha = 0
      UIView.animate(withDuration: 0.18) {
        self.pause.alpha = 1
        self.number.alpha = 0
      }

      pinProgress(0)
    }

    /// The drag has gone far enough sideways that lifting means go, or has come
    /// back from it. The glyph is the only feedback this gesture gets, which is
    /// the point: nothing is being built up, so there is nothing to watch fill.
    func showSkip(_ on: Bool) {
      guard skipping != on else { return }
      skipping = on
      UIView.animate(withDuration: 0.15) {
        self.pause.alpha = on ? 0 : 1
        self.forward.alpha = on ? 1 : 0
      }
    }

    /// How far down the drag has got, from nothing to whole.
    ///
    /// Set outright with implicit animation off, because the ring is tracking a
    /// finger. CoreAnimation's default quarter-second fade on a layer property
    /// would put the ring a quarter of a second behind the thumb drawing it,
    /// which is the difference between a control and a progress bar.
    func pinProgress(_ fraction: CGFloat) {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      // Both rings are brought back, which matters only on a cover that is
      // ALREADY pinned: `pinned` retired them, and the drag that leaves reuses
      // this so the way out looks like the way in.
      for layer in [track, pin] {
        layer.removeAnimation(forKey: "retire")
        layer.opacity = 1
      }
      pin.strokeEnd = fraction
      pin.lineWidth = Self.thin + (Self.thick - Self.thin) * fraction
      CATransaction.commit()
    }

    /// The finger left before the pin closed. Neither the ring nor the number is
    /// set going again: a press hands off the moment it lifts, so the cover is
    /// already on its way out and a clock starting to move would be describing
    /// time nobody is going to spend.
    func releaseHold() {
      pinProgress(0)
      countdown.removeAnimation(forKey: "handover")
      countdown.opacity = 1
      skipping = false
      pause.alpha = 0
      forward.alpha = 0
      number.alpha = 1
    }

    /// Pinned. The rings have nothing left to count, so they go and leave the
    /// pause holding the state on its own.
    func pinned() {
      stopTicking()
      // Whole, and held whole for the length of the fade. Snapping it back to
      // nothing would undraw the ring at the exact instant it earned its point.
      pinProgress(1)
      countdown.opacity = 0

      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 1
      fade.toValue = 0
      fade.duration = 0.3
      for layer in [track, pin] {
        layer.opacity = 0
        layer.add(fade, forKey: "retire")
      }
      // The pin is the last word, so the badge says only what it means. Leaving
      // the forward arrow up put it over the pause on any cover pinned by a
      // drag that had gone sideways first, and it is drawn later, so it won.
      skipping = false
      forward.alpha = 0
      pause.alpha = 1
      number.alpha = 0
    }

    fileprivate func showRemaining() {
      let left = max(0, endsAt - CACurrentMediaTime())
      // Only when the rendered string actually changes. At one decimal that is
      // ten writes a second rather than sixty, without asking the display link
      // for a frame rate the platform may or may not honour.
      let next = text(left)
      if number.text != next { number.text = next }
      if left <= 0 { stopTicking() }
    }

    private func stopTicking() {
      ticker?.invalidate()
      ticker = nil
    }

    /// A comma where a comma belongs. `String(format:)` writes the C locale.
    private func text(_ seconds: TimeInterval) -> String {
      String(format: "%.1f", seconds).replacingOccurrences(of: ".", with: separator)
    }

    /// `CADisplayLink` retains its target, so the badge cannot be its own: the
    /// runloop would keep it alive and `deinit`, the only place the link is
    /// invalidated, would never run.
    private final class Ticker: NSObject {
      private weak var badge: Badge?
      init(_ badge: Badge) { self.badge = badge }
      @objc func tick() { badge?.showRemaining() }
    }
  }

  /// The badge, centred at the top, on the same line as the copy and share
  /// controls and as the system's own back breadcrumb.
  @discardableResult
  static func addBadge(to container: UIView, config: QuoteCatalog.Config) -> Badge {
    let badge = Badge(config: config)
    badge.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(badge)
    NSLayoutConstraint.activate([
      badge.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      badge.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 2),
      badge.widthAnchor.constraint(equalToConstant: Badge.side),
      badge.heightAnchor.constraint(equalToConstant: Badge.side),
    ])
    return badge
  }

  /// The line as a picture, without any of the card's furniture.
  ///
  /// What the card needs on screen and what belongs in something you post are
  /// different things. A count of how many times a phrase has come up is a fact
  /// about YOUR phone, and a button labelled "Open The Simple Phone" is a
  /// control, not content. Both are dropped here, and what replaces them is a
  /// small wordmark, so the image says where it came from without asking
  /// anything of whoever sees it.
  ///
  /// Rendered from a view that was never on screen, through `layer.render`
  /// rather than `drawHierarchy`, because the latter needs the view to be in a
  /// window and this one deliberately is not.
  static func cardImage(config: QuoteCatalog.Config, phrase: QuoteCatalog.Quote,
                        size: CGSize) -> UIImage? {
    guard size.width > 0, size.height > 0 else { return nil }

    let canvas = UIView(frame: CGRect(origin: .zero, size: size))
    fill(canvas, config: config, phrase: phrase)

    let mark = UILabel()
    mark.text = "The Simple Phone"
    // Fainter than the attribution on the card, which is already secondary.
    // A signature, not a caption.
    mark.textColor = (config.isDark ? UIColor.white : .black).withAlphaComponent(0.3)
    mark.font = font(for: config, size: 13)
    mark.textAlignment = .center
    mark.translatesAutoresizingMaskIntoConstraints = false
    canvas.addSubview(mark)
    NSLayoutConstraint.activate([
      mark.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
      mark.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -56),
    ])

    canvas.setNeedsLayout()
    canvas.layoutIfNeeded()

    let renderer = UIGraphicsImageRenderer(bounds: canvas.bounds)
    return renderer.image { context in canvas.layer.render(in: context.cgContext) }
  }

  /// The phrase as text, the way a person would write it down.
  static func cardText(_ phrase: QuoteCatalog.Quote) -> String {
    guard let author = phrase.author, !author.isEmpty else { return phrase.text }
    return "\(phrase.text)\n\u{2014}\u{2009}\(author)"
  }

  /// A glyph you can find but not trip over: dimmed to the same weight as the
  /// attribution, with a touch target far larger than the icon it draws.
  static func chromeButton(symbol: String, label: String, target: AnyObject,
                           action: Selector, tint: UIColor) -> UIButton {
    let button = UIButton(type: .system)
    let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
    button.tintColor = tint.withAlphaComponent(0.45)
    button.accessibilityLabel = label
    button.addTarget(target, action: action, for: .touchUpInside)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 44).isActive = true
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    return button
  }

  /// The count and the way back, under the line.
  @discardableResult
  static func addCardChrome(to container: UIView, below stack: UIStackView?,
                            config: QuoteCatalog.Config, count: Int,
                            target: AnyObject, copy: Selector, share: Selector,
                            open: Selector) -> UILabel {
    let foreground: UIColor = config.isDark ? .white : .black
    let strings = QuoteCatalog.relayStrings(language: config.language)

    let tally = UILabel()
    tally.text = count == 1
      ? (strings["shownOnce"] ?? "shown once")
      : String(format: strings["shownTimes"] ?? "shown %@ times", "\(count)")
    // Dimmer than the attribution, which is already secondary. This is a
    // footnote about a phrase, not part of it.
    tally.textColor = foreground.withAlphaComponent(0.35)
    tally.font = font(for: config, size: 13)
    tally.textAlignment = .center
    tally.translatesAutoresizingMaskIntoConstraints = false

    let back = UIButton(type: .system)
    back.setTitle(strings["openApp"] ?? "Open The Simple Phone", for: .normal)
    back.setTitleColor(foreground.withAlphaComponent(0.5), for: .normal)
    back.titleLabel?.font = font(for: config, size: 15)
    back.addTarget(target, action: open, for: .touchUpInside)
    back.translatesAutoresizingMaskIntoConstraints = false

    let copyButton = chromeButton(symbol: "doc.on.doc", label: strings["copy"] ?? "Copy",
                                  target: target, action: copy, tint: foreground)
    let shareButton = chromeButton(symbol: "square.and.arrow.up", label: strings["share"] ?? "Share",
                                   target: target, action: share, tint: foreground)

    // Tagged so `QuoteScreen` can take them off again without knowing what they
    // are. A pinned cover that is walked away from is left standing on purpose,
    // and the next relay reuses it: without this, its Copy, Share and "Open The
    // Simple Phone" came along, and that last one silently cancels the launch
    // the user just asked for.
    for view in [tally, back, copyButton, shareButton] as [UIView] {
      view.tag = cardChromeTag
      container.addSubview(view)
    }
    NSLayoutConstraint.activate([
      shareButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
      shareButton.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
      copyButton.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor, constant: -4),
      copyButton.centerYAnchor.constraint(equalTo: shareButton.centerYAnchor),
    ])
    NSLayoutConstraint.activate([
      tally.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      // Under the LINE, not under the middle of the screen. A four line phrase
      // reaches well past centre, and anchoring to the centre printed the count
      // straight through the attribution.
      tally.topAnchor.constraint(equalTo: stack?.bottomAnchor ?? container.centerYAnchor,
                                 constant: 28),
      back.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      back.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -28),
    ])

    return tally
  }

  /// Paints `container` as the cover, and hands back the stack holding the line
  /// so a caller can hang the badge and the card's chrome off the bottom of it.
  /// Nil means no phrase -- deliberately still a plain themed field, because
  /// that is not the app list.
  ///
  /// `cardImage` wants the painting and not the stack, hence discardable.
  @discardableResult
  static func fill(_ container: UIView, config: QuoteCatalog.Config, phrase: QuoteCatalog.Quote?) -> UIStackView? {
    let background: UIColor = config.isDark ? .black : .white
    container.backgroundColor = background
    container.isOpaque = true
    guard let phrase, !phrase.text.isEmpty else { return nil }

    let foreground: UIColor = config.isDark ? .white : .black

    let label = UILabel()
    label.text = phrase.text
    label.textColor = foreground
    label.font = font(for: config)
    label.numberOfLines = 0
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.6

    // A STACK, not a second free-floating label, so the pair stays optically
    // centred: with no author the line sits exactly where it always did, and
    // with one the two centre together rather than the phrase shifting up by
    // however tall the credit happens to be.
    let stack = UIStackView(arrangedSubviews: [label])
    stack.axis = .vertical
    stack.alignment = .fill
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false

    if let author = phrase.author, !author.isEmpty {
      let credit = UILabel()
      // An en dash and a thin space, which is how a printed attribution is set.
      credit.text = "\u{2013}\u{2009}\(author)"
      // Dimmed as well as smaller. At 55 percent it reads as secondary at a
      // glance, which matters when the whole thing is on screen for under a
      // second and the phrase is what should be read first.
      credit.textColor = foreground.withAlphaComponent(0.55)
      credit.font = font(for: config, size: 15)
      credit.numberOfLines = 1
      credit.textAlignment = .center
      credit.adjustsFontSizeToFitWidth = true
      credit.minimumScaleFactor = 0.6
      stack.addArrangedSubview(credit)
    }

    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
    ])
    return stack
  }

  /// Mirrors the widget's `Theme.widgetFont`: same family choice, one size
  /// down, because this is a full screen holding one line rather than a widget
  /// holding six.
  static func font(for config: QuoteCatalog.Config, size: CGFloat = 30) -> UIFont {
    let base = UIFont.systemFont(ofSize: size, weight: .semibold)
    let design: UIFontDescriptor.SystemDesign
    switch config.font {
    case "monospaced": design = .monospaced
    case "rounded": design = .rounded
    case "serif": design = .serif
    default: return base
    }
    guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
    return UIFont(descriptor: descriptor, size: size)
  }
}
