// Native NSAlert used by the skill's dialogs (approval, update).
//
// Why not AppleScript's `display dialog`: it caps at three buttons, and has
// neither per-button key equivalents nor underlined mnemonics. NSAlert has all
// three.
//
// usage: osascript -l JavaScript dialog.js <title> <body> <icon> <buttons> [detail]
//   <buttons> is "Label:key:token|Label:key:token|..." where key is a single
//   letter (underlined in the label, and its keyboard shortcut), "esc", or
//   empty for a button that only a click can press.
//   <detail> is shown verbatim in a scrollable monospaced box under the body.
//
// Prints exactly one token on stdout. Anything else (crash, kill, unknown
// response) means "no answer" and the caller must treat it as a no-op. The
// caller also owns the timeout: an NSTimer scheduled in the default mode
// never fires inside runModal, whose loop runs in NSModalPanelRunLoopMode.
//
// Test modes, which never open a window:
//   dialog.js --visible <text>          what the detail box would display
//   dialog.js --parse-buttons <buttons> the parsed button specs, as JSON
ObjC.import('Cocoa');

// Shortcut letters only start working this long after the alert appears: it
// takes keyboard focus from whatever app you were typing in, and the rest of
// a word in flight must not press a button.
var KEY_GRACE_SECS = 0.7;

// Control, zero-width and bidi characters print as nothing, or silently
// reorder the text after them, so the approver could read a different command
// from the one that runs. Each becomes a visible <U+XXXX> marker instead.
// Newline and tab are kept: they are just layout.
var INVISIBLE = /[\u0000-\u0008\u000B-\u001F\u007F-\u009F­؜᠎​-‏‪-‮⁠-⁩﻿]/g;

function visible(text) {
  return String(text).replace(INVISIBLE, function (c) {
    var hex = ('000' + c.charCodeAt(0).toString(16).toUpperCase()).slice(-4);
    return '⟨U+' + hex + '⟩';
  });
}

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
    var letter = key === 'esc' ? '' : key;
    return {
      label: label,
      token: parts[2] || '',
      keyEquivalent: letter,
      // The shortcut letter is underlined wherever it first appears; a
      // button without one has nothing to underline.
      underlineAt: letter ? label.toLowerCase().indexOf(letter) : -1,
    };
  });
}

// The exact command, read-only but selectable, scrolling past a few lines.
function detailView(detail) {
  var width = 480;
  var maxHeight = 220;
  var scroll = $.NSScrollView.alloc.initWithFrame($.NSMakeRect(0, 0, width, 60));
  scroll.hasVerticalScroller = true;
  scroll.borderType = $.NSBezelBorder;

  // The usual text-in-a-scroll-view wiring: wrap at the box's width and grow
  // downwards, so long commands scroll instead of being clipped.
  var inner = scroll.contentSize;
  var text = $.NSTextView.alloc.initWithFrame($.NSMakeRect(0, 0, inner.width, inner.height));
  text.minSize = $.NSMakeSize(0, inner.height);
  text.maxSize = $.NSMakeSize(1e7, 1e7);
  text.verticallyResizable = true;
  text.horizontallyResizable = false;
  text.autoresizingMask = $.NSViewWidthSizable;
  text.textContainer.containerSize = $.NSMakeSize(inner.width, 1e7);
  text.textContainer.widthTracksTextView = true;
  text.editable = false;
  text.selectable = true;
  text.font = $.NSFont.userFixedPitchFontOfSize(11);
  text.textContainerInset = $.NSMakeSize(4, 4);
  text.string = visible(detail);
  scroll.documentView = text;

  // Fit the box to the text, up to maxHeight; longer commands scroll.
  text.layoutManager.ensureLayoutForTextContainer(text.textContainer);
  var used = text.layoutManager.usedRectForTextContainer(text.textContainer).size.height;
  var height = Math.max(36, Math.min(maxHeight, used + 14));
  scroll.setFrameSize($.NSMakeSize(width, height));
  return scroll;
}

// Builds the alert without showing it. Every key equivalent starts disarmed:
// run() arms them after the grace period.
function buildAlert(title, body, iconPath, buttons, detail) {
  var alert = $.NSAlert.alloc.init;
  alert.messageText = title;
  alert.informativeText = body;

  // Without an explicit icon the alert borrows osascript's, which renders as
  // a generic document badged with a caution triangle.
  if (iconPath) {
    var image = $.NSImage.alloc.initWithContentsOfFile(iconPath);
    if (!image.isNil()) alert.icon = image;
  }

  if (detail) alert.accessoryView = detailView(detail);

  var views = buttons.map(function (spec) {
    return alert.addButtonWithTitle(spec.label);
  });

  // Lay out first: NSAlert rebuilds its buttons' titles while laying out,
  // which would drop an attributed title set any earlier.
  alert.layout;

  views.forEach(function (view, i) {
    var spec = buttons[i];
    // Cleared on every button: this also strips Return from the first one, so
    // a stray Enter can never pick an action. Every choice here is a
    // deliberate click or letter.
    view.keyEquivalent = '';
    view.keyEquivalentModifierMask = 0;
    if (spec.underlineAt >= 0) {
      view.attributedTitle = underlined(spec.label, spec.underlineAt);
    }
  });

  return { alert: alert, views: views };
}

function run(argv) {
  if (argv[0] === '--visible') return visible(argv[1] || '');
  if (argv[0] === '--parse-buttons') return JSON.stringify(parseButtons(argv[1] || ''));

  var title = argv[0] || 'Claude Code';
  var body = argv[1] || '';
  var iconPath = argv[2] || '';
  var buttons = parseButtons(argv[3] || 'OK:o:ok');
  var detail = argv[4] || '';

  var app = $.NSApplication.sharedApplication;
  // Accessory keeps the notifier out of the Dock while still allowing the
  // alert to become key — without a key window the letter shortcuts are dead.
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  var built = buildAlert(title, body, iconPath, buttons, detail);

  // Added for the modal mode, where runModal's loop actually runs.
  var grace = $.NSTimer.timerWithTimeIntervalRepeatsBlock(KEY_GRACE_SECS, false, function () {
    built.views.forEach(function (view, i) {
      view.keyEquivalent = buttons[i].keyEquivalent;
    });
  });
  $.NSRunLoop.currentRunLoop.addTimerForMode(grace, $.NSModalPanelRunLoopMode);

  app.activateIgnoringOtherApps(true);
  var response = built.alert.runModal;
  grace.invalidate;

  var index = response - $.NSAlertFirstButtonReturn;
  if (index >= 0 && index < buttons.length) return buttons[index].token;
  return '';
}
