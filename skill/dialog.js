// The native dialog used by the skill (approval, update): a floating panel
// that does NOT take the keyboard.
//
// Why a non-activating panel and not NSAlert: an alert activates its app and
// becomes the key window, so whatever you were typing in Slack lands in it,
// and a stray letter can press a button. This panel floats above every window
// (and every Space) while the app you were using keeps the keyboard; you
// decide with a click. Letter shortcuts work only after you click into the
// panel yourself. Approve never has one.
//
// Why not AppleScript's `display dialog`: three buttons at most, and no
// per-button shortcuts.
//
// usage: osascript -l JavaScript dialog.js <title> <body> <icon> <buttons> [detail]
//   <buttons> is "Label:key:token|Label:key:token|..." where key is a single
//   letter (underlined in the label, and its keyboard shortcut), "esc", or
//   empty for a button that only a click can press.
//   <detail> is shown verbatim in a scrollable monospaced box under the body.
//
// Prints exactly one token on stdout. Anything else (closed, killed, crashed)
// means "no answer" and the caller must treat it as a no-op. The caller also
// owns the timeout, and kills this process when it expires.
//
// Test modes, which never open a window:
//   dialog.js --visible <text>          what the detail box would display
//   dialog.js --parse-buttons <buttons> the parsed button specs, as JSON
ObjC.import('Cocoa');

var WIDTH = 520;
var MARGIN = 20;
var ICON = 64;
var GAP = 12;
var BUTTON_HEIGHT = 28;

// Index of the button clicked; -1 while waiting.
var choice = -1;

ObjC.registerSubclass({
  name: 'ClaudeDialogTarget',
  methods: {
    'pick:': {
      types: ['void', ['id']],
      implementation: function (sender) { choice = sender.tag; },
    },
  },
});

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

// Read from the right: the label may itself hold colons ("Always approve:
// Bash(npm test:*)"), the key and the token never do.
function parseButtons(spec) {
  return spec.split('|').map(function (entry) {
    var parts = entry.split(':');
    var token = parts.length > 2 ? parts.pop() : (parts[2] || '');
    var key = (parts.length > 1 ? parts.pop() : '').toLowerCase();
    var label = parts.join(':');
    var letter = key === 'esc' ? '' : key;
    return {
      label: label,
      token: token,
      keyEquivalent: letter,
      escape: key === 'esc',
      // The shortcut letter is underlined wherever it first appears; a
      // button without one has nothing to underline.
      underlineAt: letter ? label.toLowerCase().indexOf(letter) : -1,
    };
  });
}

// The exact command, read-only but selectable, scrolling past a few lines.
function detailView(detail, width) {
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

// A label that wraps at <width>, sized to its text.
function wrappingLabel(text, font, width) {
  var label = $.NSTextField.wrappingLabelWithString(text);
  label.font = font;
  label.preferredMaxLayoutWidth = width;
  label.setFrameSize($.NSMakeSize(width, label.fittingSize.height));
  return label;
}

// Builds the panel without showing it: icon and text on top, the command
// below, one full-width button per choice at the bottom.
function buildPanel(title, body, iconPath, buttons, detail) {
  var textX = MARGIN + ICON + 16;
  var textWidth = WIDTH - textX - MARGIN;
  var titleView = wrappingLabel(title, $.NSFont.boldSystemFontOfSize(13), textWidth);
  var bodyView = body ? wrappingLabel(body, $.NSFont.systemFontOfSize(12), textWidth) : null;
  if (bodyView) bodyView.textColor = $.NSColor.secondaryLabelColor;
  var detailBox = detail ? detailView(detail, WIDTH - 2 * MARGIN) : null;

  var target = $.ClaudeDialogTarget.alloc.init;
  var views = buttons.map(function (spec, i) {
    var button = $.NSButton.buttonWithTitleTargetAction(spec.label, target, 'pick:');
    button.tag = i;
    // A letter only when the label has one; Return never picks anything.
    button.keyEquivalent = spec.escape ? '\u001b' : spec.keyEquivalent;
    button.keyEquivalentModifierMask = 0;
    if (spec.underlineAt >= 0) button.attributedTitle = underlined(spec.label, spec.underlineAt);
    return button;
  });
  var buttonWidth = 240;
  views.forEach(function (view) {
    buttonWidth = Math.max(buttonWidth, view.fittingSize.width + 32);
  });
  buttonWidth = Math.min(buttonWidth, WIDTH - 2 * MARGIN);

  var textHeight = titleView.frame.size.height + (bodyView ? 6 + bodyView.frame.size.height : 0);
  var header = Math.max(ICON, textHeight);
  var buttonsHeight = views.length * BUTTON_HEIGHT + (views.length - 1) * 8;
  var height = MARGIN + header + (detailBox ? GAP + detailBox.frame.size.height : 0)
    + GAP + 4 + buttonsHeight + MARGIN;

  var style = $.NSWindowStyleMaskTitled | $.NSWindowStyleMaskClosable | $.NSWindowStyleMaskNonactivatingPanel;
  var panel = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(0, 0, WIDTH, height), style, $.NSBackingStoreBuffered, false);
  panel.title = 'Claude Code';
  panel.releasedWhenClosed = false;
  panel.level = $.NSFloatingWindowLevel;
  panel.hidesOnDeactivate = false;
  panel.becomesKeyOnlyIfNeeded = true;
  panel.collectionBehavior = $.NSWindowCollectionBehaviorCanJoinAllSpaces
    | $.NSWindowCollectionBehaviorFullScreenAuxiliary;
  var content = panel.contentView;

  var top = height - MARGIN;
  if (iconPath) {
    var image = $.NSImage.alloc.initWithContentsOfFile(iconPath);
    if (!image.isNil()) {
      var icon = $.NSImageView.imageViewWithImage(image);
      icon.frame = $.NSMakeRect(MARGIN, top - ICON, ICON, ICON);
      icon.imageScaling = $.NSImageScaleProportionallyUpOrDown;
      content.addSubview(icon);
    }
  }
  titleView.setFrameOrigin($.NSMakePoint(textX, top - titleView.frame.size.height));
  content.addSubview(titleView);
  if (bodyView) {
    bodyView.setFrameOrigin($.NSMakePoint(textX,
      top - titleView.frame.size.height - 6 - bodyView.frame.size.height));
    content.addSubview(bodyView);
  }

  var y = top - header;
  if (detailBox) {
    y -= GAP + detailBox.frame.size.height;
    detailBox.setFrameOrigin($.NSMakePoint(MARGIN, y));
    content.addSubview(detailBox);
  }
  y -= GAP + 4;
  views.forEach(function (view) {
    y -= BUTTON_HEIGHT;
    view.frame = $.NSMakeRect((WIDTH - buttonWidth) / 2, y, buttonWidth, BUTTON_HEIGHT);
    content.addSubview(view);
    y -= 8;
  });

  return { panel: panel, views: views, target: target };
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
  // Accessory: no Dock icon. And this app is never activated: the panel is
  // shown with orderFrontRegardless, never made key.
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  var built = buildPanel(title, body, iconPath, buttons, detail);
  built.panel.center;
  built.panel.orderFrontRegardless;

  // No runModal: a modal session makes the panel key, which is exactly the
  // keyboard grab this panel exists to avoid. Events are pumped by hand until
  // a button is clicked or the panel is closed.
  while (choice < 0 && built.panel.isVisible) {
    var event = app.nextEventMatchingMaskUntilDateInModeDequeue(
      $.NSEventMaskAny, $.NSDate.dateWithTimeIntervalSinceNow(0.25), $.NSDefaultRunLoopMode, true);
    if (!event.isNil()) app.sendEvent(event);
  }
  built.panel.orderOut(null);

  if (choice >= 0 && choice < buttons.length) return buttons[choice].token;
  return '';
}
