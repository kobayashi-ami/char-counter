// 文字数カウンター — テキストを選択するだけでカーソル近くに文字数を表示
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <QuartzCore/QuartzCore.h>

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
@property (strong) NSVisualEffectView *glass;
@property (strong) CAGradientLayer *sheen;
@property (assign) BOOL hiding;
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

    // ガラス本体：背後のウィンドウを実際にぼかして透かす（ライト/ダーク自動適応）
    NSVisualEffectView *glass = [NSVisualEffectView new];
    glass.material = NSVisualEffectMaterialPopover;
    glass.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    glass.state = NSVisualEffectStateActive;
    glass.wantsLayer = YES;
    glass.layer.masksToBounds = YES;
    glass.layer.borderWidth = 1;
    glass.layer.borderColor = [NSColor colorWithWhite:1 alpha:0.35].CGColor;
    self.glass = glass;

    self.label = [NSTextField labelWithString:@""];
    NSFont *font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    NSFontDescriptor *rounded = [font.fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignRounded];
    if (rounded) font = [NSFont fontWithDescriptor:rounded size:13] ?: font;
    self.label.font = font;
    self.label.textColor = [NSColor labelColor];
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    [glass addSubview:self.label];
    [NSLayoutConstraint activateConstraints:@[
        [self.label.leadingAnchor constraintEqualToAnchor:glass.leadingAnchor constant:13],
        [self.label.trailingAnchor constraintEqualToAnchor:glass.trailingAnchor constant:-13],
        [self.label.topAnchor constraintEqualToAnchor:glass.topAnchor constant:7],
        [self.label.bottomAnchor constraintEqualToAnchor:glass.bottomAnchor constant:-7],
    ]];

    // 光の反射：上から差し込む斜めのスペキュラーハイライト（レイヤーホスティング）
    CAGradientLayer *spec = [CAGradientLayer layer];
    spec.colors = @[(id)[NSColor colorWithWhite:1 alpha:0.28].CGColor,
                    (id)[NSColor colorWithWhite:1 alpha:0.05].CGColor,
                    (id)[NSColor colorWithWhite:1 alpha:0.0].CGColor];
    spec.locations = @[@0.0, @0.5, @1.0];
    spec.startPoint = CGPointMake(0.3, 1.0);   // AppKitのレイヤー座標は左下原点
    spec.endPoint = CGPointMake(0.7, 0.0);

    // 出現時に横切る光の帯（屈折のきらめき）
    CAGradientLayer *sheen = [CAGradientLayer layer];
    sheen.colors = @[(id)[NSColor colorWithWhite:1 alpha:0.0].CGColor,
                     (id)[NSColor colorWithWhite:1 alpha:0.35].CGColor,
                     (id)[NSColor colorWithWhite:1 alpha:0.0].CGColor];
    sheen.startPoint = CGPointMake(0, 0.5);
    sheen.endPoint = CGPointMake(1, 0.5);
    sheen.opacity = 0;
    [spec addSublayer:sheen];
    self.sheen = sheen;

    NSView *overlay = [NSView new];
    [overlay setLayer:spec];
    [overlay setWantsLayer:YES];
    overlay.frame = glass.bounds;
    overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [glass addSubview:overlay];

    self.panel.contentView = glass;
}

// 出現時にガラスの上を光がすっと走る
- (void)runSheen {
    NSSize s = self.panel.contentView.bounds.size;
    CGFloat w = MAX(s.width * 0.45, 24);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.sheen.bounds = CGRectMake(0, 0, w, s.height * 2.2);
    self.sheen.position = CGPointMake(-w, s.height / 2);
    self.sheen.transform = CATransform3DMakeRotation(0.3, 0, 0, 1);
    [CATransaction commit];

    CABasicAnimation *move = [CABasicAnimation animationWithKeyPath:@"position.x"];
    move.fromValue = @(-w);
    move.toValue = @(s.width + w);
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = @[@0.0, @1.0, @1.0, @0.0];
    fade.keyTimes = @[@0.0, @0.25, @0.75, @1.0];
    CAAnimationGroup *g = [CAAnimationGroup animation];
    g.animations = @[move, fade];
    g.duration = 0.6;
    g.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.sheen addAnimation:g forKey:@"sweep"];
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
            self.hiding = YES;
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
                ctx.duration = 0.15;
                [[self.panel animator] setAlphaValue:0];
            } completionHandler:^{
                if (self.hiding) { [self.panel orderOut:nil]; self.hiding = NO; }
            }];
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
    self.glass.layer.cornerRadius = size.height / 2;  // カプセル形状

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
    BOOL wasVisible = self.panel.isVisible && !self.hiding;
    self.hiding = NO;
    if (wasVisible) {
        [self.panel setFrameOrigin:origin];
        [self.panel orderFrontRegardless];
    } else {
        // ふわっと浮き上がりながらフェードイン＋光が横切る
        self.panel.alphaValue = 0;
        [self.panel setFrameOrigin:NSMakePoint(origin.x, origin.y - 7)];
        [self.panel orderFrontRegardless];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.22;
            ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [[self.panel animator] setAlphaValue:1];
            [[self.panel animator] setFrameOrigin:origin];
        } completionHandler:nil];
        [self runSheen];
    }
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
