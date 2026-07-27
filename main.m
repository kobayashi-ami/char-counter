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
@property (strong) CAGradientLayer *glow;
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

// レイヤーをカプセルいっぱいに敷くビューを作って重ねる（サイズは自動追従）
- (NSView *)hostLayer:(CALayer *)layer in:(NSView *)parent {
    NSView *v = [NSView new];
    [v setLayer:layer];
    [v setWantsLayer:YES];
    v.frame = parent.bounds;
    v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [parent addSubview:v];
    return v;
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

    // ガラス本体：背後のウィンドウを実際にぼかして透かす
    // "Always On Time" PVの色味＝深いネイビー影＋スチールブルー＋シアンの光。
    // ライト/ダーク問わずあの夜のブルーに沈めたいので、暗い外観を明示する。
    NSVisualEffectView *glass = [NSVisualEffectView new];
    glass.material = NSVisualEffectMaterialHUDWindow;
    glass.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    glass.state = NSVisualEffectStateActive;
    glass.appearance = [NSAppearance appearanceNamed:NSAppearanceNameVibrantDark];
    glass.wantsLayer = YES;
    glass.layer.masksToBounds = YES;
    // フチなし：カプセルの輪郭は影とティントだけで表現する
    self.glass = glass;

    // 色味：単色にしない。AOTの夜のブルーにPrinceの紫を滲ませ、色の境目に
    // “ごちゃつき”＝色気を作る。ティール〜インクネイビーの土台に、マゼンタの
    // グローとアンバーの残り火をスクリーン合成で乗せた、濡れたオイルスリック。

    // 土台：左上ティール → 中央 → 右下インクネイビー（3段で奥行き）
    CAGradientLayer *base = [CAGradientLayer layer];
    base.colors = @[(id)[NSColor colorWithCalibratedRed:0.16 green:0.40 blue:0.48 alpha:0.52].CGColor,
                    (id)[NSColor colorWithCalibratedRed:0.09 green:0.22 blue:0.33 alpha:0.60].CGColor,
                    (id)[NSColor colorWithCalibratedRed:0.03 green:0.09 blue:0.17 alpha:0.72].CGColor];
    base.locations = @[@0.0, @0.5, @1.0];
    base.startPoint = CGPointMake(0.10, 1.0);   // 左上（レイヤー座標は左下原点）
    base.endPoint = CGPointMake(0.90, 0.0);     // 右下
    [self hostLayer:base in:glass];

    // Princeのマゼンタ光：右上に灯る球状のグロー。スクリーン合成で青と溶け合い
    // 境界に紫〜青緑の“濁り”を生む
    CAGradientLayer *glow = [CAGradientLayer layer];
    glow.type = kCAGradientLayerRadial;
    glow.colors = @[(id)[NSColor colorWithCalibratedRed:0.74 green:0.15 blue:0.56 alpha:0.62].CGColor,
                    (id)[NSColor colorWithCalibratedRed:0.44 green:0.10 blue:0.62 alpha:0.30].CGColor,
                    (id)[NSColor colorWithCalibratedRed:0.44 green:0.10 blue:0.62 alpha:0.0].CGColor];
    glow.locations = @[@0.0, @0.45, @1.0];
    glow.startPoint = CGPointMake(0.82, 0.85);  // 右上に中心
    glow.endPoint = CGPointMake(1.5, 1.6);      // 外へ広がる半径
    NSView *glowView = [self hostLayer:glow in:glass];
    glowView.layer.compositingFilter = @"screenBlendMode";
    self.glow = glow;

    // アンバーの残り火：下辺だけ温度を上げる。冷たい青×肌の暖色＝AOTの艶
    CAGradientLayer *ember = [CAGradientLayer layer];
    ember.colors = @[(id)[NSColor colorWithCalibratedRed:0.72 green:0.34 blue:0.13 alpha:0.32].CGColor,
                     (id)[NSColor colorWithCalibratedRed:0.72 green:0.34 blue:0.13 alpha:0.0].CGColor];
    ember.locations = @[@0.0, @1.0];
    ember.startPoint = CGPointMake(0.4, 0.0);   // 下辺から
    ember.endPoint = CGPointMake(0.5, 0.75);    // 上へ薄れる
    NSView *emberView = [self hostLayer:ember in:glass];
    emberView.layer.compositingFilter = @"screenBlendMode";

    // 静止させない。紫を生き物のように微かに息づかせる（Princeの変態性＝艶）
    CABasicAnimation *breathe = [CABasicAnimation animationWithKeyPath:@"opacity"];
    breathe.fromValue = @0.62; breathe.toValue = @1.0;
    breathe.duration = 2.6; breathe.autoreverses = YES; breathe.repeatCount = HUGE_VALF;
    breathe.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [glow addAnimation:breathe forKey:@"breathe"];
    CABasicAnimation *drift = [CABasicAnimation animationWithKeyPath:@"startPoint"];
    drift.fromValue = [NSValue valueWithPoint:NSMakePoint(0.78, 0.82)];
    drift.toValue = [NSValue valueWithPoint:NSMakePoint(0.90, 0.92)];
    drift.duration = 5.5; drift.autoreverses = YES; drift.repeatCount = HUGE_VALF;
    drift.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [glow addAnimation:drift forKey:@"drift"];

    self.label = [NSTextField labelWithString:@""];
    NSFont *font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    NSFontDescriptor *rounded = [font.fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignRounded];
    if (rounded) font = [NSFont fontWithDescriptor:rounded size:13] ?: font;
    self.label.font = font;
    // 読み：シアン寄りの冷たい白（あのPVのハイライトの色温度）
    self.label.textColor = [NSColor colorWithCalibratedRed:0.87 green:0.96 blue:0.98 alpha:1.0];
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    [glass addSubview:self.label];
    [NSLayoutConstraint activateConstraints:@[
        [self.label.leadingAnchor constraintEqualToAnchor:glass.leadingAnchor constant:13],
        [self.label.trailingAnchor constraintEqualToAnchor:glass.trailingAnchor constant:-13],
        [self.label.topAnchor constraintEqualToAnchor:glass.topAnchor constant:7],
        [self.label.bottomAnchor constraintEqualToAnchor:glass.bottomAnchor constant:-7],
    ]];

    // 光の反射：上から差し込む斜めのスペキュラーハイライト（シアン寄りの光）
    CAGradientLayer *spec = [CAGradientLayer layer];
    spec.colors = @[(id)[NSColor colorWithCalibratedRed:0.72 green:0.92 blue:0.99 alpha:0.30].CGColor,
                    (id)[NSColor colorWithCalibratedRed:0.72 green:0.92 blue:0.99 alpha:0.06].CGColor,
                    (id)[NSColor colorWithCalibratedRed:0.72 green:0.92 blue:0.99 alpha:0.0].CGColor];
    spec.locations = @[@0.0, @0.5, @1.0];
    spec.startPoint = CGPointMake(0.3, 1.0);   // AppKitのレイヤー座標は左下原点
    spec.endPoint = CGPointMake(0.7, 0.0);

    // 出現時に横切る光の帯：単色じゃなく虹色に屈折させる（シアン→白→マゼンタ）。
    // オイルの膜を光がすっと舐めるような分光
    CAGradientLayer *sheen = [CAGradientLayer layer];
    sheen.colors = @[(id)[NSColor colorWithCalibratedRed:0.55 green:0.90 blue:0.98 alpha:0.0].CGColor,
                     (id)[NSColor colorWithCalibratedRed:0.66 green:0.96 blue:1.00 alpha:0.42].CGColor,
                     (id)[NSColor colorWithCalibratedRed:0.98 green:0.62 blue:0.96 alpha:0.34].CGColor,
                     (id)[NSColor colorWithCalibratedRed:0.80 green:0.28 blue:0.72 alpha:0.0].CGColor];
    sheen.locations = @[@0.0, @0.42, @0.66, @1.0];
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
    // Electron系（Claudeデスクトップ等）とChromium系（Chrome等）は、これらを
    // 立てないとAXツリーを公開しない。ElectronはAXManualAccessibility、Chromeは
    // AXEnhancedUserInterfaceで有効化される（版により片方だけ効くので両方立てる）。
    // 有効化直後はツリー構築に数秒かかるため、最初の数回は選択が取れないことがある。
    NSRunningApplication *front = [NSWorkspace sharedWorkspace].frontmostApplication;
    if (front && front.processIdentifier != self.lastPid) {
        self.lastPid = front.processIdentifier;
        AXUIElementRef axApp = AXUIElementCreateApplication(self.lastPid);
        AXUIElementSetAttributeValue(axApp, CFSTR("AXManualAccessibility"), kCFBooleanTrue);
        AXUIElementSetAttributeValue(axApp, CFSTR("AXEnhancedUserInterface"), kCFBooleanTrue);
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

    // Webコンテンツ（Safari/Chrome/各種WebView等）向けフォールバック：
    // WebKit系はAXSelectedText/AXSelectedTextRangeを公開せず、
    // 「テキストマーカー」で選択を表す。AXSelectedTextMarkerRange（AXTextMarkerRange）を
    // 取り、AXStringForTextMarkerRangeパラメータ付き属性で文字列に変換する。
    // ※どちらも非公開だが安定したAXの慣習的キー。
    if (!result) {
        CFTypeRef markerRange = NULL;
        if (AXUIElementCopyAttributeValue(el, CFSTR("AXSelectedTextMarkerRange"), &markerRange) == kAXErrorSuccess
            && markerRange) {
            CFTypeRef strRef = NULL;
            if (AXUIElementCopyParameterizedAttributeValue(el, CFSTR("AXStringForTextMarkerRange"),
                                                           markerRange, &strRef) == kAXErrorSuccess && strRef) {
                if (CFGetTypeID(strRef) == CFStringGetTypeID() && CFStringGetLength(strRef) > 0) {
                    result = [(__bridge NSString *)strRef copy];
                }
                CFRelease(strRef);
            }
            CFRelease(markerRange);
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
