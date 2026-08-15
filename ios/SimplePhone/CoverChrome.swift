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
  /// The padlock, opposite the copy and share controls, saying the cover is
  /// pinned rather than merely slow.
  static func addPadlock(to container: UIView, config: QuoteCatalog.Config) {
    let colour: UIColor = config.isDark ? .white : .black
    let symbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    // Coloured into the image rather than left to `tintColor`, which a plain
    // UIImageView only honours for a template image. See `docs/native-notes.md`,
    // "SF Symbols in a UIImageView".
    let glyph = UIImage(systemName: "lock.fill", withConfiguration: symbol)?
      .withTintColor(colour.withAlphaComponent(0.4), renderingMode: .alwaysOriginal)
    let lock = UIImageView(image: glyph)
    lock.alpha = 0
    lock.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(lock)
    NSLayoutConstraint.activate([
      lock.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
      lock.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 22),
    ])
    UIView.animate(withDuration: 0.28) { lock.alpha = 1 }
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
