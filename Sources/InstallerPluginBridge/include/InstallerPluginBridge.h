#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The Installer pane hosting a controller. Lets Swift drive Installer's buttons
/// without importing InstallerPlugins.
NS_SWIFT_UI_ACTOR
@protocol PermissionInstallerPaneHost <NSObject>
@property (nonatomic) BOOL nextEnabled;
@property (nonatomic) BOOL previousEnabled;
@property (nonatomic, readonly) BOOL installSucceeded;
- (BOOL)gotoNextPane;
@end

/// One pane's content and behavior.
NS_SWIFT_UI_ACTOR
@protocol PermissionInstallerPaneController <NSObject>
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, strong) NSView *view;
/// YES to pass over this pane without showing it, such as a step that's already done.
@property (nonatomic, readonly) BOOL shouldSkip;
- (void)attachHost:(id<PermissionInstallerPaneHost>)host;
- (void)willEnterForward:(BOOL)forward;
- (void)didEnterForward:(BOOL)forward;
- (BOOL)shouldExitForward:(BOOL)forward;
- (void)didExit;
@end

/// What the class named by the bundle's `PermissionInstallerProvider` Info.plist key
/// responds to. Looked up by selector, so the Swift class needn't declare conformance.
NS_SWIFT_UI_ACTOR
@protocol PermissionInstallerPaneProvider <NSObject>
- (NSArray<id<PermissionInstallerPaneController>> *)makePaneControllers;
@end

NS_ASSUME_NONNULL_END
