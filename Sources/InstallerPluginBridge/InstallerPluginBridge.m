#import "InstallerPluginBridge.h"
#import <InstallerPlugins/InstallerPlugins.h>

@interface PKInstallerPane : InstallerPane <PKPaneHost>
@property (nonatomic, strong) id<PKPaneController> controller;
@end

@implementation PKInstallerPane

- (NSString *)title { return self.controller.title; }

// Installer asks for the next pane when Continue is clicked, so skipped panes are passed
// over without ever being shown. Showing and then leaving them makes the window flash.
- (InstallerPane *)nextPane {
    InstallerPane *next = [super nextPane];
    if ([next isKindOfClass:PKInstallerPane.class] && ((PKInstallerPane *)next).controller.shouldSkip) {
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
@interface PKInstallerSection : InstallerSection
@end

@implementation PKInstallerSection {
    NSArray<PKInstallerPane *> *_panes;
}

- (InstallerPane *)firstPane {
    if (_panes) return _panes.firstObject;

    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *name = bundle.infoDictionary[@"PermissionInstallerProvider"];
    Class cls = name ? NSClassFromString(name) : Nil;
    if (![cls conformsToProtocol:@protocol(PKPaneProvider)]) {
        NSLog(@"PermissionInstaller: PermissionInstallerProvider '%@' isn't a PKPaneProvider class", name);
        _panes = @[];
        return nil;
    }

    id<PKPaneProvider> provider = [[cls alloc] init];
    NSMutableArray<PKInstallerPane *> *panes = [NSMutableArray array];
    for (id<PKPaneController> controller in [provider makePaneControllers]) {
        PKInstallerPane *pane = [[PKInstallerPane alloc] initWithSection:self];
        pane.controller = controller;
        [controller attachHost:pane];
        panes.lastObject.nextPane = pane;
        [panes addObject:pane];
    }
    _panes = panes;
    return _panes.firstObject;
}

@end
