import UIKit

/// Every pixel the cover draws: the line, the controls that appear once it is
/// pinned or missed, the padlock, and the picture you can share.
///
/// Split from `QuoteScreen` so that file is about WHEN the cover exists and
/// this one about what it looks like. A constraint has no business sitting next
/// to the runloop timing of a handoff.
///
/// Nothing here owns state and nothing here knows what a button does: targets
/// and selectors arrive as arguments. That is the seam. `QuoteScreen` decides
/// behaviour, this decides appearance.
enum CoverChrome {
  /// The disc at the top of the cover: how long the phrase has left, and what a
  /// finger is doing about it.
  ///
  /// One circle with three things to say, in sequence and never at once, which
  /// is what lets a single ring carry two opposite meanings:
  ///
  /// - **Draining.** The ring empties over the configured duration. Time
  ///   leaving, nobody doing anything.
  /// - **Held.** The ring freezes where the eye last saw it, a pause appears in
  ///   the middle, and a second ring fills the other way, thickening as it
  ///   closes. Time stopped, someone building something.
  /// - **Pinned.** Both rings go and the pause stays.
  ///
  /// Pause and not a padlock, deliberately. A padlock says you cannot leave,
  /// which is false: a tap, a drag sideways and the button all still work. A
  /// pause says nothing happens until you say so, which is what is actually
  /// true, and it is the same word the frozen ring is already saying.
  ///
  /// Takes no touches. It sits over the cover, and the cover is the thing
  /// listening for a finger.
  final class Badge: UIView {
    private static let disc: CGFloat = 44
    private static let ringRadius: CGFloat = 25
    private static let side: CGFloat = 58
    private static let thin: CGFloat = 2
    private static let thick: CGFloat = 3.5

    /// The faint outline the two rings run along.
    private let track = CAShapeLayer()
    /// The countdown: starts whole, empties.
    private let countdown = CAShapeLayer()
    /// The pin: starts at nothing, fills.
    private let pin = CAShapeLayer()
    private let pause = UIImageView()

    init(config: QuoteCatalog.Config) {
      super.init(frame: CGRect(x: 0, y: 0, width: Self.side, height: Self.side))
      isUserInteractionEnabled = false

      let colour: UIColor = config.isDark ? .white : .black
      let centre = CGPoint(x: Self.side / 2, y: Self.side / 2)

      let disc = UIView(frame: CGRect(x: centre.x - Self.disc / 2, y: centre.y - Self.disc / 2,
                                      width: Self.disc, height: Self.disc))
      disc.backgroundColor = colour.withAlphaComponent(0.10)
      disc.layer.cornerRadius = Self.disc / 2
      addSubview(disc)

      // From twelve o'clock, clockwise, so the countdown retracts back towards
      // the top the way any dial does.
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

      let symbol = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
      // Coloured into the image rather than left to `tintColor`, which a plain
      // UIImageView only honours for a template image. See `docs/native-notes.md`,
      // "SF Symbols in a UIImageView".
      pause.image = UIImage(systemName: "pause.fill", withConfiguration: symbol)?
        .withTintColor(colour.withAlphaComponent(0.75), renderingMode: .alwaysOriginal)
      pause.sizeToFit()
      pause.center = centre
      pause.alpha = 0
      addSubview(pause)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// The phrase's own clock has started. Called when the cover becomes
    /// touchable, not when the relay began: see `docs/native-notes.md`,
    /// "A countdown that cannot lie".
    func drain(over seconds: TimeInterval) {
      guard seconds > 0 else { return }
      countdown.removeAnimation(forKey: "sweep")
      // Model value at the destination, so it simply stays there when the
      // animation ends rather than needing to be kept alive past its own life.
      countdown.strokeEnd = 0
      let sweep = CABasicAnimation(keyPath: "strokeEnd")
      sweep.fromValue = 1
      sweep.toValue = 0
      sweep.duration = seconds
      // Linear, because it is a clock. Any easing here would be the ring
      // disagreeing with the timer it is drawing.
      sweep.timingFunction = CAMediaTimingFunction(name: .linear)
      countdown.add(sweep, forKey: "sweep")
    }

    /// A finger arrived. Freeze, and start closing the pin.
    func hold(over seconds: TimeInterval) {
      // Where the eye last saw it, not where the model says. Mid-animation the
      // two are a whole countdown apart.
      if let shown = countdown.presentation()?.strokeEnd {
        countdown.removeAnimation(forKey: "sweep")
        countdown.strokeEnd = shown
      }
      // A crossfade rather than a cut: the pin starts at nothing, so cutting
      // the countdown would leave the badge ringless for the first moments of
      // the very gesture it is meant to be reporting.
      let handover = CABasicAnimation(keyPath: "opacity")
      handover.fromValue = 1
      handover.toValue = 0
      handover.duration = 0.15
      countdown.opacity = 0
      countdown.add(handover, forKey: "handover")

      pause.alpha = 0
      UIView.animate(withDuration: 0.18) { self.pause.alpha = 1 }

      pin.strokeEnd = 1
      pin.lineWidth = Self.thick
      let sweep = CABasicAnimation(keyPath: "strokeEnd")
      sweep.fromValue = 0
      sweep.toValue = 1
      let weight = CABasicAnimation(keyPath: "lineWidth")
      weight.fromValue = Self.thin
      weight.toValue = Self.thick
      let group = CAAnimationGroup()
      group.animations = [sweep, weight]
      group.duration = seconds
      group.timingFunction = CAMediaTimingFunction(name: .linear)
      pin.add(group, forKey: "close")
    }

    /// The finger left before the pin closed. The countdown is deliberately not
    /// resumed: a press hands off the moment it lifts, so the cover is already
    /// on its way out and a ring starting to move again would be describing time
    /// nobody is going to spend.
    func releaseHold() {
      pin.removeAnimation(forKey: "close")
      pin.strokeEnd = 0
      pin.lineWidth = Self.thin
      countdown.removeAnimation(forKey: "handover")
      countdown.opacity = 1
      pause.alpha = 0
    }

    /// Pinned. The rings have nothing left to count, so they go and leave the
    /// pause holding the state on its own.
    func pinned() {
      pin.removeAnimation(forKey: "close")
      // Whole, and held whole for the length of the fade. Snapping it back to
      // nothing would undraw the ring at the exact instant it earned its point.
      pin.strokeEnd = 1
      pin.lineWidth = Self.thick
      countdown.opacity = 0

      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 1
      fade.toValue = 0
      fade.duration = 0.3
      for layer in [track, pin] {
        layer.opacity = 0
        layer.add(fade, forKey: "retire")
      }
      pause.alpha = 1
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
      badge.widthAnchor.constraint(equalToConstant: 58),
      badge.heightAnchor.constraint(equalToConstant: 58),
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

    container.addSubview(tally)
    container.addSubview(back)
    container.addSubview(copyButton)
    container.addSubview(shareButton)
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
