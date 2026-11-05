// CircleMenu - Theos tweak
// قائمة دائرية عائمة: (الشبكة) + (سرعة الصوت)

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

#pragma mark - ================= Voice engine =================

// Pitch/speed shifter: خطّان للقراءة من delay-line مع crossfade (زمن حقيقي)
#define PS_WIN 1024
#define PS_LEN 8192   // لازم يكون من مضاعفات 2

typedef struct { float buf[PS_LEN]; int wp; float ph; } PShift;

static PShift gPS[4];
static volatile float gVoiceRate = 1.0f;  // 1.0 = بدون تأثير
static volatile int   gVoiceMode = 0;     // 0 = عادي، 1 = شيطان (تشويه خفيف)

static inline float PSProcess(PShift *s, float in, float r) {
    s->buf[s->wp] = in;
    float out = 0.f;
    const float step = (1.0f - r) / (float)PS_WIN;
    for (int h = 0; h < 2; h++) {
        float p = s->ph + 0.5f * h;
        if (p >= 1.f) p -= 1.f;
        float d  = p * PS_WIN + 2.f;
        float rp = (float)s->wp - d;
        if (rp < 0.f) rp += PS_LEN;
        int   i0 = (int)rp;
        float fr = rp - (float)i0;
        int   i1 = (i0 + 1) & (PS_LEN - 1);
        float v  = s->buf[i0] * (1.f - fr) + s->buf[i1] * fr;
        float g  = 0.5f - 0.5f * cosf(2.f * (float)M_PI * p);
        out += v * g;
    }
    s->ph += step;
    if (s->ph >= 1.f) s->ph -= 1.f;
    if (s->ph <  0.f) s->ph += 1.f;
    s->wp = (s->wp + 1) & (PS_LEN - 1);
    return out;
}

static inline float CMShape(float x) {
    if (gVoiceMode == 1) x = tanhf(x * 2.2f) * 0.85f;
    if (x > 1.f) x = 1.f; else if (x < -1.f) x = -1.f;
    return x;
}

static void CMProcessMic(AudioBufferList *io, UInt32 frames) {
    float r = gVoiceRate;
    int slot = 0;
    for (UInt32 b = 0; b < io->mNumberBuffers && slot < 4; b++) {
        AudioBuffer *ab = &io->mBuffers[b];
        UInt32 ch = ab->mNumberChannels ? ab->mNumberChannels : 1;
        if (!ab->mData || frames == 0) continue;
        UInt32 bps = ab->mDataByteSize / (frames * ch);   // 2 = Int16 ، 4 = Float32
        for (UInt32 c = 0; c < ch && slot < 4; c++, slot++) {
            if (bps == 2) {
                SInt16 *p = (SInt16 *)ab->mData;
                for (UInt32 f = 0; f < frames; f++) {
                    float x = (float)p[f * ch + c] / 32768.f;
                    x = CMShape(PSProcess(&gPS[slot], x, r));
                    p[f * ch + c] = (SInt16)(x * 32767.f);
                }
            } else if (bps == 4) {
                float *p = (float *)ab->mData;
                for (UInt32 f = 0; f < frames; f++) {
                    p[f * ch + c] = CMShape(PSProcess(&gPS[slot], p[f * ch + c], r));
                }
            }
        }
    }
}

#pragma mark - ================= UI model =================

@interface CMItem : NSObject
@property (nonatomic, copy) NSString *emoji, *title, *group;
@property (nonatomic, strong) NSArray<CMItem *> *children;
@property (nonatomic, copy) void (^action)(BOOL on);
@property (nonatomic) BOOL on;
+ (instancetype)emoji:(NSString *)e title:(NSString *)t group:(NSString *)g action:(void (^)(BOOL))a;
+ (instancetype)emoji:(NSString *)e title:(NSString *)t children:(NSArray *)c;
@end

@implementation CMItem
+ (instancetype)emoji:(NSString *)e title:(NSString *)t group:(NSString *)g action:(void (^)(BOOL))a {
    CMItem *i = [CMItem new]; i.emoji = e; i.title = t; i.group = g; i.action = a; return i;
}
+ (instancetype)emoji:(NSString *)e title:(NSString *)t children:(NSArray *)c {
    CMItem *i = [CMItem new]; i.emoji = e; i.title = t; i.children = c; return i;
}
@end

#pragma mark - ================= Orb (الأيقونة) =================

static UIColor *CMCyan(void)   { return [UIColor colorWithRed:0.00 green:0.90 blue:1.00 alpha:1]; }
static UIColor *CMViolet(void) { return [UIColor colorWithRed:0.49 green:0.30 blue:1.00 alpha:1]; }
static UIColor *CMPink(void)   { return [UIColor colorWithRed:1.00 green:0.25 blue:0.75 alpha:1]; }

// صورة الأيقونة: كرة نيون بتدرج + صاعقة + لمعة زجاجية (مرسومة بالكود، بدون ملفات)
static UIImage *CMOrbImage(CGFloat s) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(s, s)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGContextSaveGState(c);
        CGContextAddEllipseInRect(c, CGRectInset(CGRectMake(0, 0, s, s), 5, 5));
        CGContextClip(c);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat comps[] = {0.00, 0.90, 1.00, 1,
                           0.49, 0.30, 1.00, 1,
                           0.10, 0.04, 0.23, 1};
        CGFloat locs[] = {0, 0.55, 1};
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locs, 3);
        CGContextDrawRadialGradient(c, g, CGPointMake(s * 0.36, s * 0.32), 0,
                                    CGPointMake(s / 2, s / 2), s / 2,
                                    kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(g);
        CGColorSpaceRelease(cs);

        // صاعقة
        UIBezierPath *b = [UIBezierPath bezierPath];
        CGPoint pts[] = {{0.57,0.17},{0.33,0.54},{0.47,0.54},{0.42,0.83},{0.68,0.44},{0.54,0.44}};
        for (int i = 0; i < 6; i++) {
            CGPoint p = CGPointMake(pts[i].x * s, pts[i].y * s);
            if (i == 0) [b moveToPoint:p]; else [b addLineToPoint:p];
        }
        [b closePath];
        [[UIColor colorWithWhite:1 alpha:0.95] setFill];
        [b fill];

        // لمعة زجاجية
        UIBezierPath *hl = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(s*0.22, s*0.12, s*0.42, s*0.2)];
        [[UIColor colorWithWhite:1 alpha:0.28] setFill];
        [hl fill];
        CGContextRestoreGState(c);
    }];
}

@interface CMOrb : UIView
@end
@implementation CMOrb
- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    UIImageView *iv = [[UIImageView alloc] initWithImage:CMOrbImage(f.size.width)];
    iv.frame = self.bounds;
    [self addSubview:iv];

    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = self.bounds;
    g.type = kCAGradientLayerConic;
    g.colors = @[(id)CMCyan().CGColor, (id)CMViolet().CGColor, (id)CMPink().CGColor, (id)CMCyan().CGColor];
    g.startPoint = CGPointMake(0.5, 0.5);
    g.endPoint = CGPointMake(0.5, 0.0);
    CAShapeLayer *m = [CAShapeLayer layer];
    m.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 2, 2)].CGPath;
    m.fillColor = nil;
    m.strokeColor = UIColor.whiteColor.CGColor;
    m.lineWidth = 3;
    g.mask = m;
    [self.layer addSublayer:g];

    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    a.toValue = @(2 * M_PI); a.duration = 4; a.repeatCount = HUGE_VALF;
    [g addAnimation:a forKey:@"spin"];

    self.layer.shadowColor = CMCyan().CGColor;
    self.layer.shadowRadius = 12;
    self.layer.shadowOpacity = 0.9;
    self.layer.shadowOffset = CGSizeZero;
    return self;
}
@end

#pragma mark - ================= Window / Root =================

@interface CMPassWindow : UIWindow
@end
@implementation CMPassWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    if (v == self || v == self.rootViewController.view) return nil;   // مرّر اللمس للتطبيق
    return v;
}
@end

@interface CMRootVC : UIViewController
@end

#pragma mark - ================= Controller =================

@interface CMController : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *root;
@property (nonatomic, strong) CMOrb *orb;
@property (nonatomic, strong) UIVisualEffectView *hud;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) NSArray<CMItem *> *rootItems;
@property (nonatomic, strong) NSMutableArray<NSArray<CMItem *> *> *levels;
@property (nonatomic, strong) NSMutableArray<UIButton *> *itemViews;
@property (nonatomic, strong) NSTimer *hudTimer, *pingTimer;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic) BOOL fakeSpeed, fakePing, realPing;
@property (nonatomic) double realMs;
@property (nonatomic, copy) NSString *voiceText;
@property (nonatomic) CGPoint panStart;
- (void)setup;
- (void)layoutChanged;
@end

static CMController *gC;

@implementation CMRootVC
- (void)loadView { UIView *v = [UIView new]; v.backgroundColor = UIColor.clearColor; self.view = v; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [gC layoutChanged]; }
@end

@implementation CMController

- (void)setup {
    if (self.window) return;

    UIWindowScene *sc = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive) {
            sc = (UIWindowScene *)s; break;
        }
    }
    CMPassWindow *w = sc ? [[CMPassWindow alloc] initWithWindowScene:sc]
                         : [[CMPassWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    w.windowLevel = UIWindowLevelAlert + 1000;
    w.backgroundColor = UIColor.clearColor;
    CMRootVC *vc = [CMRootVC new];
    w.rootViewController = vc;
    w.hidden = NO;
    self.window = w;
    self.root = vc.view;

    self.levels = [NSMutableArray array];
    self.itemViews = [NSMutableArray array];
    [self buildItems];

    // HUD
    self.hud = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
    self.hud.layer.cornerRadius = 14;
    self.hud.clipsToBounds = YES;
    self.hud.userInteractionEnabled = NO;
    self.hud.hidden = YES;
    self.stack = [UIStackView new];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 2;
    self.stack.alignment = UIStackViewAlignmentLeading;
    [self.hud.contentView addSubview:self.stack];
    [self.root addSubview:self.hud];

    // Orb
    self.orb = [[CMOrb alloc] initWithFrame:CGRectMake(10, 180, 60, 60)];
    [self.root addSubview:self.orb];
    [self.orb addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(orbTap)]];
    [self.orb addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(orbPan:)]];

    self.session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    self.hudTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refreshHUD) userInfo:nil repeats:YES];
}

#pragma mark Items

- (void)buildItems {
    CMItem *speed = [CMItem emoji:@"🚀" title:@"1TB تحميل/رفع" group:nil action:^(BOOL on) { gC.fakeSpeed = on; }];
    CMItem *ping0 = [CMItem emoji:@"🏓" title:@"Ping 0ms" group:nil action:^(BOOL on) { gC.fakePing = on; }];
    CMItem *real  = [CMItem emoji:@"📡" title:@"بنق حقيقي" group:nil action:^(BOOL on) { [gC setRealPing:on]; }];

    CMItem *v3  = [CMItem emoji:@"🐿️" title:@"×3" group:@"v" action:^(BOOL on) {
        gVoiceMode = 0; gVoiceRate = on ? 3.0f : 1.0f; gC.voiceText = on ? @"🎙 Voice ×3" : nil; }];
    CMItem *v15 = [CMItem emoji:@"⚡" title:@"×1.5" group:@"v" action:^(BOOL on) {
        gVoiceMode = 0; gVoiceRate = on ? 1.5f : 1.0f; gC.voiceText = on ? @"🎙 Voice ×1.5" : nil; }];
    CMItem *dem = [CMItem emoji:@"😈" title:@"شيطان" group:@"v" action:^(BOOL on) {
        gVoiceMode = on ? 1 : 0; gVoiceRate = on ? 0.7f : 1.0f; gC.voiceText = on ? @"🎙 Demon ×0.7" : nil; }];

    CMItem *net = [CMItem emoji:@"🌐" title:@"الشبكة" children:@[speed, ping0, real]];
    CMItem *voc = [CMItem emoji:@"🎙️" title:@"الصوت" children:@[v3, v15, dem]];
    self.rootItems = @[net, voc];
}

- (void)setRealPing:(BOOL)on {
    _realPing = on;
    [self.pingTimer invalidate]; self.pingTimer = nil;
    self.realMs = 0;
    if (on) {
        [self pingOnce];
        self.pingTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(pingOnce) userInfo:nil repeats:YES];
    }
}

- (void)pingOnce {
    NSMutableURLRequest *rq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://www.apple.com/library/test/success.html"]
                                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                  timeoutInterval:4];
    rq.HTTPMethod = @"HEAD";
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    [[self.session dataTaskWithRequest:rq completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        self.realMs = e ? -1 : (CFAbsoluteTimeGetCurrent() - t0) * 1000.0;
    }] resume];
}

#pragma mark Menu show/hide

- (void)orbTap {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    if (self.levels.count == 0) { [self.levels addObject:self.rootItems]; }
    else if (self.levels.count > 1) { [self.levels removeLastObject]; }
    else { [self.levels removeAllObjects]; }
    [self showLevel];
}

- (void)clearItems {
    NSArray *old = [self.itemViews copy];
    [self.itemViews removeAllObjects];
    CGPoint c = self.orb.center;
    [UIView animateWithDuration:0.18 animations:^{
        for (UIView *v in old) { v.center = c; v.alpha = 0; v.transform = CGAffineTransformMakeScale(0.2, 0.2); }
    } completion:^(BOOL f) { for (UIView *v in old) [v removeFromSuperview]; }];
}

- (void)showLevel {
    [self clearItems];
    NSArray<CMItem *> *items = self.levels.lastObject;
    if (!items) return;

    CGPoint c = self.orb.center;
    CGPoint mid = CGPointMake(CGRectGetMidX(self.root.bounds), CGRectGetMidY(self.root.bounds));
    CGFloat a0 = atan2(mid.y - c.y, mid.x - c.x);   // وجّه القائمة نحو وسط الشاشة
    CGFloat R = 96, span = 1.0;
    NSInteger n = items.count;

    for (NSInteger i = 0; i < n; i++) {
        CMItem *it = items[i];
        CGFloat ang = a0 + (i - (n - 1) / 2.0) * span;
        CGPoint p = CGPointMake(c.x + R * cos(ang), c.y + R * sin(ang));
        p.x = MIN(MAX(p.x, 40), self.root.bounds.size.width - 40);
        p.y = MIN(MAX(p.y, 60), self.root.bounds.size.height - 60);

        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(0, 0, 54, 54);
        b.tag = i;
        b.layer.cornerRadius = 27;
        b.layer.borderWidth = 2;
        b.layer.borderColor = CMViolet().CGColor;
        b.layer.shadowColor = CMCyan().CGColor;
        b.layer.shadowOpacity = 0.6;
        b.layer.shadowRadius = 8;
        b.layer.shadowOffset = CGSizeZero;

        UIVisualEffectView *bl = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
        bl.frame = b.bounds; bl.layer.cornerRadius = 27; bl.clipsToBounds = YES; bl.userInteractionEnabled = NO;
        [b addSubview:bl];

        UILabel *em = [[UILabel alloc] initWithFrame:b.bounds];
        em.text = it.emoji; em.textAlignment = NSTextAlignmentCenter; em.font = [UIFont systemFontOfSize:26];
        em.userInteractionEnabled = NO;
        [b addSubview:em];

        UILabel *cap = [[UILabel alloc] initWithFrame:CGRectMake(-23, 58, 100, 14)];
        cap.text = it.title; cap.textAlignment = NSTextAlignmentCenter;
        cap.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        cap.textColor = UIColor.whiteColor;
        cap.layer.shadowColor = UIColor.blackColor.CGColor; cap.layer.shadowOpacity = 1; cap.layer.shadowRadius = 2; cap.layer.shadowOffset = CGSizeZero;
        cap.userInteractionEnabled = NO;
        [b addSubview:cap];

        [b addTarget:self action:@selector(tapItem:) forControlEvents:UIControlEventTouchUpInside];
        [self.root insertSubview:b belowSubview:self.orb];
        [self.itemViews addObject:b];

        b.center = c; b.alpha = 0; b.transform = CGAffineTransformMakeScale(0.2, 0.2);
        [UIView animateWithDuration:0.45 delay:0.04 * i usingSpringWithDamping:0.7 initialSpringVelocity:0.8 options:0 animations:^{
            b.center = p; b.alpha = 1; b.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
    [self refreshItemStates];
}

- (void)refreshItemStates {
    NSArray<CMItem *> *items = self.levels.lastObject;
    for (UIButton *b in self.itemViews) {
        if (b.tag >= (NSInteger)items.count) continue;
        BOOL on = items[b.tag].on;
        b.layer.borderColor = (on ? [UIColor colorWithRed:0.2 green:1 blue:0.5 alpha:1] : CMViolet()).CGColor;
        b.layer.shadowColor = (on ? [UIColor colorWithRed:0.2 green:1 blue:0.5 alpha:1] : CMCyan()).CGColor;
    }
}

- (void)tapItem:(UIButton *)b {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    NSArray<CMItem *> *items = self.levels.lastObject;
    CMItem *it = items[b.tag];
    if (it.children) { [self.levels addObject:it.children]; [self showLevel]; return; }
    if (it.group) {
        for (CMItem *s in items) if (s != it && [s.group isEqual:it.group]) s.on = NO;
    }
    it.on = !it.on;
    if (it.action) it.action(it.on);
    [self refreshItemStates];
    [self refreshHUD];
}

#pragma mark Drag

- (void)orbPan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        self.panStart = self.orb.center;
        if (self.levels.count) { [self.levels removeAllObjects]; [self clearItems]; }
    }
    CGPoint t = [g translationInView:self.root];
    self.orb.center = [self clamp:CGPointMake(self.panStart.x + t.x, self.panStart.y + t.y)];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        CGFloat W = self.root.bounds.size.width;
        CGFloat x = self.orb.center.x < W / 2 ? 36 : W - 36;
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
            self.orb.center = [self clamp:CGPointMake(x, self.orb.center.y)];
        } completion:nil];
    }
}

- (CGPoint)clamp:(CGPoint)p {
    UIEdgeInsets si = self.root.safeAreaInsets;
    CGRect r = UIEdgeInsetsInsetRect(self.root.bounds, UIEdgeInsetsMake(si.top + 34, 34, si.bottom + 34, 34));
    p.x = MIN(MAX(p.x, CGRectGetMinX(r)), CGRectGetMaxX(r));
    p.y = MIN(MAX(p.y, CGRectGetMinY(r)), CGRectGetMaxY(r));
    return p;
}

- (void)layoutChanged {
    if (!self.orb) return;
    self.orb.center = [self clamp:self.orb.center];
    [self refreshHUD];
}

#pragma mark HUD

- (void)refreshHUD {
    NSMutableArray *lines = [NSMutableArray array];
    UIColor *green = [UIColor colorWithRed:0.2 green:1 blue:0.5 alpha:1];

    if (self.fakeSpeed) {
        double j1 = ((int)arc4random_uniform(21) - 10) / 1000.0;
        double j2 = ((int)arc4random_uniform(21) - 10) / 1000.0;
        [lines addObject:@[[NSString stringWithFormat:@"⬇︎ %.3f TB/s   ⬆︎ %.3f TB/s", 1.0 + j1, 1.0 + j2], green]];
    }
    if (self.fakePing) [lines addObject:@[@"📶 Ping 0 ms", green]];
    if (self.realPing) {
        if (self.realMs == 0) [lines addObject:@[@"📡 Ping …", UIColor.whiteColor]];
        else if (self.realMs < 0) [lines addObject:@[@"📡 Ping: timeout", [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1]]];
        else {
            UIColor *c = self.realMs <= 60 ? green : (self.realMs <= 120 ? [UIColor colorWithRed:1 green:0.85 blue:0.2 alpha:1] : [UIColor colorWithRed:1 green:0.3 blue:0.3 alpha:1]);
            [lines addObject:@[[NSString stringWithFormat:@"📡 Ping %.0f ms", self.realMs], c]];
        }
    }
    if (self.voiceText) [lines addObject:@[self.voiceText, CMCyan()]];

    for (UIView *v in self.stack.arrangedSubviews) { [self.stack removeArrangedSubview:v]; [v removeFromSuperview]; }
    if (!lines.count) { self.hud.hidden = YES; return; }

    for (NSArray *l in lines) {
        UILabel *lb = [UILabel new];
        lb.text = l[0]; lb.textColor = l[1];
        lb.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
        [self.stack addArrangedSubview:lb];
    }
    CGSize sz = [self.stack systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    CGFloat w = sz.width + 24, h = sz.height + 16;
    UIEdgeInsets si = self.root.safeAreaInsets;
    self.hud.frame = CGRectMake((self.root.bounds.size.width - w) / 2, si.top + 6, w, h);
    self.stack.frame = CGRectMake(12, 8, sz.width, sz.height);
    self.hud.hidden = NO;
}

@end

#pragma mark - ================= Hooks =================

%hookf(OSStatus, AudioUnitRender, AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags,
       const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData) {
    OSStatus st = %orig;
    // bus 1 = ميكروفون (RemoteIO / VoiceProcessingIO)
    if (st == noErr && inOutputBusNumber == 1 && ioData && gVoiceRate != 1.0f) {
        CMProcessMic(ioData, inNumberFrames);
    }
    return st;
}

%ctor {
    %init;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *n) {
        if (!gC) gC = [CMController new];
        [gC setup];
    }];
}
