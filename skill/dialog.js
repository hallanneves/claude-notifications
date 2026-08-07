// Native NSAlert used by the skill's dialogs (approval, update).
//
// Why not AppleScript's `display dialog`: it caps at three buttons, and has
// neither per-button key equivalents nor underlined mnemonics. NSAlert has all
// three.
//
// usage: osascript -l JavaScript dialog.js <title> <body> <icon> <buttons>
//   <buttons> is "Label:key:token|Label:key:token|..." where key is a single
//   letter (underlined in the label, and its keyboard shortcut) or "esc".
//
// Prints exactly one token on stdout. Anything else (crash, kill, unknown
// response) means "no answer" and the caller must treat it as a no-op. The
// caller also owns the timeout: an NSTimer would never fire, because the modal
// run loop runs in NSModalPanelRunLoopMode and a scheduled timer only joins
// the default mode.
ObjC.import('Cocoa');

// JXA's bridge does not expose -initWithString: on NSMutableAttributedString,
// so build the string empty and fill it through its mutableString.
function underlined(text, index) {
  var attributed = $.NSMutableAttributedString.alloc.init;
  attributed.mutableString.setString(text);
  attributed.addAttributeValueRange(
    $.NSUnderlineStyleAttributeName,
    $.NSNumber.numberWithInt(1),
    $.NSMakeRange(index, 1)
  );
  return attributed;
}

function parseButtons(spec) {
  return spec.split('|').map(function (entry) {
    var parts = entry.split(':');
    var label = parts[0];
    var key = (parts[1] || '').toLowerCase();
    return {
      label: label,
      token: parts[2] || '',
      keyEquivalent: key === 'esc' ? '' : key,
      // The shortcut letter is underlined wherever it first appears.
      underlineAt: key === 'esc' ? -1 : label.toLowerCase().indexOf(key),
    };
  });
}

function run(argv) {
  var title = argv[0] || 'Claude Code';
  var body = argv[1] || '';
  var iconPath = argv[2] || '';
  var buttons = parseButtons(argv[3] || 'OK:o:ok');

  var app = $.NSApplication.sharedApplication;
  // Accessory keeps the notifier out of the Dock while still allowing the
  // alert to become key — without a key window the letter shortcuts are dead.
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  var alert = $.NSAlert.alloc.init;
  alert.messageText = title;
  alert.informativeText = body;

  // Without an explicit icon the alert borrows osascript's, which renders as
  // a generic document badged with a caution triangle.
  if (iconPath) {
    var image = $.NSImage.alloc.initWithContentsOfFile(iconPath);
    if (!image.isNil()) alert.icon = image;
  }

  var views = buttons.map(function (spec) {
    return alert.addButtonWithTitle(spec.label);
  });

  // Lay out first: NSAlert rebuilds its buttons' titles while laying out,
  // which would drop an attributed title set any earlier.
  alert.layout;

  views.forEach(function (view, i) {
    var spec = buttons[i];
    // Set on every button: this also strips Return from the first one, so a
    // stray Enter can never pick an action. Every choice here is a deliberate
    // click or letter.
    view.keyEquivalent = spec.keyEquivalent;
    view.keyEquivalentModifierMask = 0;
    if (spec.underlineAt >= 0) {
      view.attributedTitle = underlined(spec.label, spec.underlineAt);
    }
  });

  app.activateIgnoringOtherApps(true);
  var response = alert.runModal;

  var index = response - $.NSAlertFirstButtonReturn;
  if (index >= 0 && index < buttons.length) return buttons[index].token;
  return '';
}
