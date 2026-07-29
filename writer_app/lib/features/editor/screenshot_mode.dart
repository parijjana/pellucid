// Description: Capture-mode flags for the store screenshot harness.
//
// EVERYTHING here is inert in the shipped app: `kScreenshotCaptureMode`
// defaults to `false`, and every gated edit elsewhere in the tree collapses to
// the exact original behavior when it is false. Only the standalone
// `lib/screenshot_main.dart` entry point ever flips these, and only while it is
// rasterizing off-screen shots. The real app never imports that entry point.
//
// The flags are simple mutable globals (no ValueNotifier needed) because the
// harness sets them synchronously right before it builds each scene.

/// Which responsive layout the captured widget tree should assume, independent
/// of the real host platform. During macOS capture `Platform.isIOS` etc. are all
/// false, so the app's own `isMobilePhone` checks would never pick the mobile
/// layout — this lets the harness force it.
enum ScreenshotLayout { desktop, mobilePhone, tablet }

/// Which window controls (if any) the captured header should draw. macOS capture
/// never composites the real native traffic lights into the off-screen raster,
/// and the Windows/Linux `WindowCaption` is `Platform`-gated off on macOS — so
/// the header would otherwise be bare. `macOS` draws synthetic traffic lights for
/// the Mac App Store set; `none` keeps every other store's shots control-free
/// (this is what guarantees no Apple traffic lights leak into non-Mac stores).
enum ScreenshotWindowControls { macOS, none }

/// Master switch. False in the shipped app; the harness sets it true before it
/// builds any scene and the app's UI is byte-for-byte unchanged while it is false.
bool kScreenshotCaptureMode = false;

/// Active layout while [kScreenshotCaptureMode] is true. Ignored otherwise.
ScreenshotLayout kScreenshotLayout = ScreenshotLayout.desktop;

/// Active window-control style while [kScreenshotCaptureMode] is true. Ignored otherwise.
ScreenshotWindowControls kScreenshotWindowControls = ScreenshotWindowControls.macOS;
