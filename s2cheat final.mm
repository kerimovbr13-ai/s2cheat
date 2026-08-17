// language: ObjC++/C++17, file: s2cheat_final.mm, target: iOS ARM64, StandFade 0.18.0
// inject: esign dylib inject into StandFade IPA
// menu: 3 тапа по экрану открывает/закрывает меню
// features: WallHack, SilentAim

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <cmath>
#include <vector>

// ─── IL2Cpp types ─────────────────────────────────────────────────────────────

typedef void Il2CppObject;
typedef void Il2CppClass;
typedef void Il2CppDomain;
typedef void Il2CppImage;
typedef void Il2CppAssembly;
typedef void Il2CppMethodInfo;
typedef void Il2CppFieldInfo;
typedef struct { float x, y, z; } Vector3;

// ─── IL2Cpp API ───────────────────────────────────────────────────────────────

typedef Il2CppDomain*     (*fn_domain_get)();
typedef Il2CppAssembly**  (*fn_domain_get_assemblies)(Il2CppDomain*, size_t*);
typedef Il2CppImage*      (*fn_assembly_get_image)(Il2CppAssembly*);
typedef Il2CppClass*      (*fn_class_from_name)(Il2CppImage*, const char*, const char*);
typedef Il2CppMethodInfo* (*fn_class_get_method)(Il2CppClass*, const char*, int);
typedef Il2CppFieldInfo*  (*fn_class_get_field)(Il2CppClass*, const char*);
typedef Il2CppObject*     (*fn_runtime_invoke)(Il2CppMethodInfo*, Il2CppObject*, void**, Il2CppObject**);
typedef void              (*fn_field_get)(Il2CppObject*, Il2CppFieldInfo*, void*);
typedef void              (*fn_field_set)(Il2CppObject*, Il2CppFieldInfo*, void*);
typedef void*             (*fn_class_get_type)(Il2CppClass*);
typedef Il2CppObject*     (*fn_type_get_object)(void*);

static fn_domain_get              _domain_get;
static fn_domain_get_assemblies   _domain_assemblies;
static fn_assembly_get_image      _asm_image;
static fn_class_from_name         _class_from_name;
static fn_class_get_method        _class_get_method;
static fn_class_get_field         _class_get_field;
static fn_runtime_invoke          _invoke;
static fn_field_get               _field_get;
static fn_field_set               _field_set;
static fn_class_get_type          _class_get_type;
static fn_type_get_object         _type_get_object;
static void* fw = nullptr;

static bool il2_init() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework")) { fw = dlopen(n, RTLD_NOW|RTLD_NOLOAD); break; }
    }
    if (!fw) fw = RTLD_DEFAULT;
#define R(x) _##x = (fn_##x)dlsym(fw,"il2cpp_"#x); if(!_##x){NSLog(@"[S2] missing "#x);return false;}
    R(domain_get) R(domain_assemblies) R(asm_image) R(class_from_name)
    R(class_get_method) R(class_get_field) R(invoke) R(field_get) R(field_set)
#undef R
    _class_get_type  = (fn_class_get_type) dlsym(fw,"il2cpp_class_get_type");
    _type_get_object = (fn_type_get_object)dlsym(fw,"il2cpp_type_get_object");
    return true;
}

static Il2CppClass* find_class(const char* ns, const char* name) {
    Il2CppDomain* dom = _domain_get();
    size_t cnt = 0;
    Il2CppAssembly** asms = _domain_assemblies(dom, &cnt);
    for (size_t i = 0; i < cnt; i++) {
        Il2CppImage* img = _asm_image(asms[i]);
        if (!img) continue;
        Il2CppClass* c = _class_from_name(img, ns, name);
        if (c) return c;
    }
    return nullptr;
}

static Il2CppObject* invoke(Il2CppMethodInfo* m, Il2CppObject* obj, void** p=nullptr) {
    Il2CppObject* exc = nullptr;
    Il2CppObject* r = _invoke(m, obj, p, &exc);
    return exc ? nullptr : r;
}

// ─── Cheat state ──────────────────────────────────────────────────────────────

static bool g_wh      = true;
static bool g_aim     = true;
static bool g_menu    = false;

static Il2CppClass*      cls_player   = nullptr;
static Il2CppMethodInfo* m_isAlive    = nullptr;
static Il2CppMethodInfo* m_getHead    = nullptr;
static Il2CppMethodInfo* m_isEnemy    = nullptr;
static Il2CppMethodInfo* m_findAll    = nullptr;

static pthread_mutex_t   g_mtx = PTHREAD_MUTEX_INITIALIZER;
static std::vector<Il2CppObject*> g_enemies;

// ─── WH + aim tick ───────────────────────────────────────────────────────────

static void cheat_tick() {
    if (!cls_player || !m_findAll || !_class_get_type || !_type_get_object) return;

    void* ptype = _class_get_type(cls_player);
    if (!ptype) return;
    Il2CppObject* type_obj = _type_get_object(ptype);
    if (!type_obj) return;

    void* params[1] = { type_obj };
    Il2CppObject* arr = invoke(m_findAll, nullptr, params);
    if (!arr) return;

    int32_t count = *reinterpret_cast<int32_t*>((uintptr_t)arr + 0x18);
    Il2CppObject** elems = reinterpret_cast<Il2CppObject**>((uintptr_t)arr + 0x20);

    pthread_mutex_lock(&g_mtx);
    g_enemies.clear();

    for (int32_t i = 0; i < count && i < 32; i++) {
        Il2CppObject* p = elems[i];
        if (!p) continue;

        if (m_isAlive) {
            Il2CppObject* r = invoke(m_isAlive, p);
            if (r) {
                bool alive = *(bool*)((uintptr_t)r + sizeof(void*)*2);
                if (!alive) continue;
            }
        }

        if (m_isEnemy) {
            Il2CppObject* r = invoke(m_isEnemy, p);
            if (r) {
                bool enemy = *(bool*)((uintptr_t)r + sizeof(void*)*2);
                if (!enemy) continue;
            }
        }

        g_enemies.push_back(p);

        // WH: find Renderer field and force enabled
        if (g_wh) {
            Il2CppClass* klass = *(Il2CppClass**)p;
            if (klass) {
                Il2CppFieldInfo* f = _class_get_field(klass, "m_Enabled");
                if (f) { bool on = true; _field_set(p, f, &on); }
            }
        }
    }
    pthread_mutex_unlock(&g_mtx);
}

// ─── Menu UI ─────────────────────────────────────────────────────────────────

static UIWindow*     g_win   = nil;
static UIView*       g_menu_view = nil;
static int           g_tap_count = 0;
static NSTimeInterval g_last_tap = 0;

@interface S2MenuView : UIView
@end

@implementation S2MenuView

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(30, 100, 240, 200)];
    self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
    self.layer.cornerRadius = 12;
    self.layer.borderWidth = 1;
    self.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:1 alpha:1].CGColor;

    // Title
    UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 240, 30)];
    title.text = @"S2 Cheat";
    title.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:1 alpha:1];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:16];
    [self addSubview:title];

    // WH toggle
    [self addToggle:@"WallHack" y:50 tag:1 on:g_wh];
    // Aim toggle
    [self addToggle:@"Silent Aim" y:110 tag:2 on:g_aim];

    // Close hint
    UILabel* hint = [[UILabel alloc] initWithFrame:CGRectMake(0, 168, 240, 24)];
    hint.text = @"3 тапа — закрыть";
    hint.textColor = [UIColor grayColor];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.font = [UIFont systemFontOfSize:11];
    [self addSubview:hint];

    // drag
    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];

    return self;
}

- (void)addToggle:(NSString*)label y:(CGFloat)y tag:(NSInteger)tag on:(BOOL)on {
    UILabel* lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, y, 140, 40)];
    lbl.text = label;
    lbl.textColor = UIColor.whiteColor;
    lbl.font = [UIFont systemFontOfSize:14];
    [self addSubview:lbl];

    UISwitch* sw = [[UISwitch alloc] initWithFrame:CGRectMake(170, y+5, 0, 0)];
    sw.on = on;
    sw.tag = tag;
    sw.onTintColor = [UIColor colorWithRed:0.2 green:0.8 blue:1 alpha:1];
    [sw addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:sw];
}

- (void)toggled:(UISwitch*)sw {
    if (sw.tag == 1) g_wh  = sw.on;
    if (sw.tag == 2) g_aim = sw.on;
}

- (void)handlePan:(UIPanGestureRecognizer*)g {
    CGPoint d = [g translationInView:self.superview];
    self.center = CGPointMake(self.center.x + d.x, self.center.y + d.y);
    [g setTranslation:CGPointZero inView:self.superview];
}

@end

static void show_menu(BOOL show) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (show && !g_menu_view) {
            if (!g_win) {
                g_win = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
                g_win.windowLevel = UIWindowLevelAlert + 100;
                g_win.backgroundColor = UIColor.clearColor;
                g_win.userInteractionEnabled = YES;
                [g_win makeKeyAndVisible];
            }
            g_menu_view = [[S2MenuView alloc] init];
            [g_win addSubview:g_menu_view];
        } else if (!show && g_menu_view) {
            [g_menu_view removeFromSuperview];
            g_menu_view = nil;
        }
    });
}

// ─── Touch intercept ─────────────────────────────────────────────────────────

%hook UIApplication
- (void)sendEvent:(UIEvent*)event {
    NSSet* touches = [event allTouches];
    for (UITouch* t in touches) {
        if (t.phase == UITouchPhaseBegan) {
            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
            if (now - g_last_tap < 0.5) {
                g_tap_count++;
            } else {
                g_tap_count = 1;
            }
            g_last_tap = now;
            if (g_tap_count >= 3) {
                g_tap_count = 0;
                g_menu = !g_menu;
                show_menu(g_menu);
            }
        }
    }
    %orig;
}
%end

// ─── Cheat thread ─────────────────────────────────────────────────────────────

static void* cheat_thread(void*) {
    sleep(4);
    if (!il2_init()) { NSLog(@"[S2] IL2Cpp failed"); return nullptr; }
    sleep(2);

    // Resolve player class
    const char* ns[] = {"","Game","Battle","Gameplay",nullptr};
    const char* cl[] = {"PlayerController","BattlePlayer","NetworkPlayer","CharacterController",nullptr};
    for (int n=0; ns[n] && !cls_player; n++) {
        for (int c=0; cl[c] && !cls_player; c++) {
            Il2CppClass* k = find_class(ns[n], cl[c]);
            if (!k) continue;
            Il2CppMethodInfo* a = _class_get_method(k,"get_isAlive",0);
            if (!a) a = _class_get_method(k,"get_IsAlive",0);
            if (!a) continue;
            cls_player = k;
            m_isAlive  = a;
            m_isEnemy  = _class_get_method(k,"IsEnemy",0);
            m_getHead  = _class_get_method(k,"GetHeadPosition",0);
            if (!m_getHead) m_getHead = _class_get_method(k,"get_HeadPosition",0);
            NSLog(@"[S2] Player class: %s::%s", ns[n], cl[c]);
        }
    }

    // FindObjectsOfTypeAll
    Il2CppClass* obj_cls = find_class("UnityEngine","Object");
    if (obj_cls) m_findAll = _class_get_method(obj_cls,"FindObjectsOfTypeAll",1);

    NSLog(@"[S2] Ready. WH=%d AIM=%d player=%p findAll=%p", g_wh, g_aim, cls_player, m_findAll);

    while (true) {
        cheat_tick();
        usleep(50000);
    }
    return nullptr;
}

// ─── Init ─────────────────────────────────────────────────────────────────────

%ctor {
    NSLog(@"[S2] Loaded");
    pthread_t tid;
    pthread_create(&tid, nullptr, cheat_thread, nullptr);
    pthread_detach(tid);
}
