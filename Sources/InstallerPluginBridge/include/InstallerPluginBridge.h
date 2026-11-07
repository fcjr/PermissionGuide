#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The Installer pane hosting a controller. Lets Swift drive Installer's buttons
/// without importing InstallerPlugins.
NS_SWIFT_UI_ACTOR
@protocol PKPaneHost <NSObject>
@property (nonatomic) BOOL nextEnabled;
@property (nonatomic) BOOL previousEnabled;
@property (nonatomic, readonly) BOOL installSucceeded;
- (BOOL)gotoNextPane;
@end

/// One pane's content and behavior.
NS_SWIFT_UI_ACTOR
@protocol PKPaneController <NSObject>
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, strong) NSView *view;
/// YES to pass over this pane without showing it, such as a step that's already done.
@property (nonatomic, readonly) BOOL shouldSkip;
- (void)attachHost:(id<PKPaneHost>)host;
- (void)willEnterForward:(BOOL)forward;
- (void)didEnterForward:(BOOL)forward;
- (BOOL)shouldExitForward:(BOOL)forward;
- (void)didExit;
@end

/// The class named by the bundle's `PermissionInstallerProvider` Info.plist key.
NS_SWIFT_UI_ACTOR
@protocol PKPaneProvider <NSObject>
- (NSArray<id<PKPaneController>> *)makePaneControllers;
@end

NS_ASSUME_NONNULL_END
