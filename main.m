// 文字数カウンター — テキストを選択するだけでカーソル近くに文字数を表示
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

static NSUInteger CountChars(NSString *s) {
    // 絵文字なども1文字として数える（書記素単位）
    __block NSUInteger n = 0;
    [s enumerateSubstringsInRange:NSMakeRange(0, s.length)
                          options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString *sub, NSRange r1, NSRange r2, BOOL *stop) { n++; }];
    return n;
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) NSStatusItem *statusItem;
@property (strong) NSPanel *panel;
@property (strong) NSTextField *label;
@property (strong) NSTimer *timer;
@property (copy) NSString *lastText;
@property (assign) pid_t lastPid;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"字";
    NSMenu *menu = [NSMenu new];
    NSMenuItem *info = [[NSMenuItem alloc] initWithTitle:@"文字数カウンター — 選択するだけ"
                                                  action:nil keyEquivalent:@""];
    info.enabled = NO;
    [menu addItem:info];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"終了"
                                             action:@selector(terminate:) keyEquivalent:@"q"]];
    self.statusItem.menu = menu;

    // アクセシビリティ権限の確認（未許可ならシステム設定へ誘導するダイアログが出る）
    NSDictionary *opts = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);

    [self buildPanel];
    self.lastText = @"";
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self
                                                selector:@selector(tick) userInfo:nil repeats:YES];
}

- (void)buildPanel {
    self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 10, 10)
                                            styleMask:NSWindowStyleMaskNonactivatingPanel | NSWindowStyleMaskBorderless
                                              backing:NSBackingStoreBuffered defer:NO];
    self.panel.level = NSStatusWindowLevel;
    self.panel.opaque = NO;
    self.panel.backgroundColor = [NSColor clearColor];
    self.panel.hasShadow = YES;
    self.panel.ignoresMouseEvents = YES;
    self.panel.hidesOnDeactivate = NO;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
                                  | NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSView *bg = [NSView new];
    bg.wantsLayer = YES;
    bg.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.08 alpha:0.92].CGColor;
    bg.layer.cornerRadius = 9;

    self.label = [NSTextField labelWithString:@""];
    self.label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.label.textColor = [NSColor whiteColor];
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    [bg addSubview:self.label];
    [NSLayoutConstraint activateConstraints:@[
        [self.label.leadingAnchor constraintEqualToAnchor:bg.leadingAnchor constant:11],
        [self.label.trailingAnchor constraintEqualToAnchor:bg.trailingAnchor constant:-11],
        [self.label.topAnchor constraintEqualToAnchor:bg.topAnchor constant:6],
        [self.label.bottomAnchor constraintEqualToAnchor:bg.bottomAnchor constant:-6],
    ]];
    self.panel.contentView = bg;
}

- (void)tick {
    // Electron系アプリ（Claudeデスクトップ等）はこれを立てないとAXツリーを公開しない
    NSRunningApplication *front = [NSWorkspace sharedWorkspace].frontmostApplication;
    if (front && front.processIdentifier != self.lastPid) {
        self.lastPid = front.processIdentifier;
        AXUIElementRef axApp = AXUIElementCreateApplication(self.lastPid);
        AXUIElementSetAttributeValue(axApp, CFSTR("AXManualAccessibility"), kCFBooleanTrue);
        CFRelease(axApp);
    }

    NSString *text = [self selectedText] ?: @"";
    if (text.length == 0) {
        if (self.lastText.length > 0) {
            self.lastText = @"";
            [self.panel orderOut:nil];
        }
        return;
    }
    if ([text isEqualToString:self.lastText]) return;
    self.lastText = text;

    NSUInteger total = CountChars(text);
    NSArray *parts = [text componentsSeparatedByCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSUInteger noSpace = CountChars([parts componentsJoinedByString:@""]);
    self.label.stringValue = (noSpace == total)
        ? [NSString stringWithFormat:@"%lu字", (unsigned long)total]
        : [NSString stringWithFormat:@"%lu字（空白除く %lu）", (unsigned long)total, (unsigned long)noSpace];

    [self.panel.contentView layoutSubtreeIfNeeded];
    NSSize size = self.panel.contentView.fittingSize;
    [self.panel setContentSize:size];

    NSPoint mouse = [NSEvent mouseLocation];
    // カーソルの下側に出す。上側は「調べる」やアプリの選択ポップアップ
    // （引用ボタン等）が出る場所なので、覆い隠さないように空けておく
    NSPoint origin = NSMakePoint(mouse.x + 14, mouse.y - size.height - 22);
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSMouseInRect(mouse, screen.frame, NO)) {
            NSRect f = screen.visibleFrame;
            origin.x = MIN(origin.x, NSMaxX(f) - size.width - 8);
            origin.y = MIN(origin.y, NSMaxY(f) - size.height - 8);
            origin.x = MAX(origin.x, NSMinX(f) + 8);
            origin.y = MAX(origin.y, NSMinY(f) + 8);
            break;
        }
    }
    [self.panel setFrameOrigin:origin];
    [self.panel orderFrontRegardless];
}

- (NSString *)selectedText {
    AXUIElementRef system = AXUIElementCreateSystemWide();
    CFTypeRef focusedRef = NULL;
    AXError err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute, &focusedRef);
    CFRelease(system);
    if (err != kAXErrorSuccess || focusedRef == NULL) return nil;
    AXUIElementRef el = (AXUIElementRef)focusedRef;

    NSString *result = nil;
    CFTypeRef selRef = NULL;
    if (AXUIElementCopyAttributeValue(el, kAXSelectedTextAttribute, &selRef) == kAXErrorSuccess && selRef) {
        if (CFGetTypeID(selRef) == CFStringGetTypeID() && CFStringGetLength(selRef) > 0) {
            result = [(__bridge NSString *)selRef copy];
        }
        CFRelease(selRef);
    }

    // AXSelectedTextが無いアプリ向けのフォールバック：選択範囲→文字列取得
    if (!result) {
        CFTypeRef rangeRef = NULL;
        if (AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute, &rangeRef) == kAXErrorSuccess && rangeRef) {
            CFRange range;
            if (CFGetTypeID(rangeRef) == AXValueGetTypeID()
                && AXValueGetValue((AXValueRef)rangeRef, kAXValueTypeCFRange, &range)
                && range.length > 0) {
                CFTypeRef strRef = NULL;
                if (AXUIElementCopyParameterizedAttributeValue(el, kAXStringForRangeParameterizedAttribute,
                                                               rangeRef, &strRef) == kAXErrorSuccess && strRef) {
                    if (CFGetTypeID(strRef) == CFStringGetTypeID() && CFStringGetLength(strRef) > 0) {
                        result = [(__bridge NSString *)strRef copy];
                    }
                    CFRelease(strRef);
                }
            }
            CFRelease(rangeRef);
        }
    }
    CFRelease(el);
    return result;
}

@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
