#import "InstallerPluginBridge.h"
#import <InstallerPlugins/InstallerPlugins.h>

@interface PermissionInstallerPane : InstallerPane <PermissionInstallerPaneHost>
@property (nonatomic, strong) id<PermissionInstallerPaneController> controller;
@end

@implementation PermissionInstallerPane

- (NSString *)title { return self.controller.title; }

// Installer asks for the next pane when Continue is clicked, so skipped panes are passed
// over without ever being shown. Showing and then leaving them makes the window flash.
- (InstallerPane *)nextPane {
    InstallerPane *next = [super nextPane];
    if ([next isKindOfClass:PermissionInstallerPane.class] && ((PermissionInstallerPane *)next).controller.shouldSkip) {
        return next.nextPane;
    }
    return next;
}
- (NSView *)contentView { return self.controller.view; }

- (BOOL)installSucceeded {
    InstallerState *state = self.section.installerState;
    return state.installStarted && state.installSucceeded;
}

- (void)willEnterPane:(InstallerSectionDirection)dir {
    [super willEnterPane:dir];
    [self.controller willEnterForward:dir != InstallerDirectionBackward];
}

- (void)didEnterPane:(InstallerSectionDirection)dir {
    [super didEnterPane:dir];
    [self.controller didEnterForward:dir != InstallerDirectionBackward];
}

- (BOOL)shouldExitPane:(InstallerSectionDirection)dir {
    return [self.controller shouldExitForward:dir == InstallerDirectionForward];
}

- (void)didExitPane:(InstallerSectionDirection)dir {
    [super didExitPane:dir];
    [self.controller didExit];
}

@end

/// The bundle's NSPrincipalClass. Builds one pane per controller from the provider
/// class named in Info.plist.
@interface PermissionInstallerSection : InstallerSection
@end

@implementation PermissionInstallerSection {
    NSArray<PermissionInstallerPane *> *_panes;
}

- (InstallerPane *)firstPane {
    if (_panes) return _panes.firstObject;

    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *name = bundle.infoDictionary[@"PermissionInstallerProvider"];
    Class cls = name ? NSClassFromString(name) : Nil;
    if (![cls instancesRespondToSelector:@selector(makePaneControllers)]) {
        NSLog(@"PermissionInstaller: PermissionInstallerProvider '%@' isn't an InstallerPlugin subclass", name);
        _panes = @[];
        return nil;
    }

    id<PermissionInstallerPaneProvider> provider = [[cls alloc] init];
    NSMutableArray<PermissionInstallerPane *> *panes = [NSMutableArray array];
    for (id<PermissionInstallerPaneController> controller in [provider makePaneControllers]) {
        PermissionInstallerPane *pane = [[PermissionInstallerPane alloc] initWithSection:self];
        pane.controller = controller;
        [controller attachHost:pane];
        panes.lastObject.nextPane = pane;
        [panes addObject:pane];
    }
    _panes = panes;
    return _panes.firstObject;
}

@end
