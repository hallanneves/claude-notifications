// Approval dialog for approval-hook.sh, as a native NSAlert.
//
// Why not AppleScript's `display dialog`: it caps at three buttons (we need
// four actions), has no per-button key equivalents, and cannot underline a
// mnemonic letter. NSAlert does all three.
//
// usage: osascript -l JavaScript approval-dialog.js "<body text>" ["<icon path>"]
// Prints exactly one token on stdout: approve | deny | editor | ignore
// Anything else (crash, kill, unknown response) means "no decision" and the
// caller must fall back to Claude Code's normal interactive prompt. The
// caller also owns the timeout: an NSTimer would never fire, because the
// modal run loop runs in NSModalPanelRunLoopMode and a scheduled timer only
// joins the default mode.
ObjC.import('Cocoa');

// [label, index of the letter to underline (-1 = none), key equivalent, token]
var BUTTONS = [
  ['Aprovar', 0, 'a', 'approve'],
  ['Negar', 0, 'n', 'deny'],
  ['Abrir no editor', 9, 'e', 'editor'],
  ['Fechar (Esc)', -1, '\u001b', 'ignore'],
];

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

function run(argv) {
  var body = argv[0] || '';
  var iconPath = argv[1] || '';

  var app = $.NSApplication.sharedApplication;
  // Accessory keeps the notifier out of the Dock while still allowing the
  // alert to become key — without a key window the letter shortcuts are dead.
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  var alert = $.NSAlert.alloc.init;
  alert.messageText = 'Claude Code — aprovação';
  alert.informativeText = body;

  // Without an explicit icon the alert borrows osascript's, which renders as
  // a generic document badged with a caution triangle.
  if (iconPath) {
    var image = $.NSImage.alloc.initWithContentsOfFile(iconPath);
    if (!image.isNil()) alert.icon = image;
  }

  var buttons = [];
  BUTTONS.forEach(function (spec) {
    buttons.push(alert.addButtonWithTitle(spec[0]));
  });

  // Lay out first: NSAlert rebuilds its buttons' titles while laying out, which
  // would drop an attributed title set any earlier.
  alert.layout;

  buttons.forEach(function (button, i) {
    var spec = BUTTONS[i];
    // Set on every button: this also strips Return from the first one, so a
    // stray Enter can never approve anything. Every action here is a
    // deliberate click or letter.
    button.keyEquivalent = spec[2];
    button.keyEquivalentModifierMask = 0;
    if (spec[1] >= 0) button.attributedTitle = underlined(spec[0], spec[1]);
  });

  app.activateIgnoringOtherApps(true);
  var response = alert.runModal;

  var index = response - $.NSAlertFirstButtonReturn;
  if (index >= 0 && index < BUTTONS.length) return BUTTONS[index][3];
  return 'ignore';
}
