# WidgetKit preparation

This extension is source-only in 0.3.0. The release uses the AppKit desktop card; it does not embed or register this extension.

`tools/build_widget.sh --check` compiles a standalone extension into a temporary directory, with shared-container access disabled. It does not install anything. `WidgetSnapshotStore` only accepts an explicitly configured system App Group container and never falls back to a guessed home-directory path.

Before shipping, configure a real Apple signing team and an authorized App Group shared with the host, wire host snapshot writing and WidgetCenter reloads, embed/sign the extension, and verify the actual system widget gallery, permission flow, snapshots, deep links, and installation/update behavior. The optional signing branch in the build script prepares only a standalone extension; it does not complete host integration or notarization.
