const std = @import("std");
const shared = @import("shared");
const render = shared.render;
const ui = shared.ui;
const widgets = shared.widgets;

test "notificationComponentRendersExpectedSnapshotToMemoryRenderer" {
    const allocator = std.testing.allocator;

    // Create a notification component
    var notif = widgets.notification.Notification.init(allocator, "Title", "Message here");
    notif.severity = .warning;

    // Prepare renderer and render one frame
    var mr = try render.MemoryRenderer.init(allocator, 20, 3);
    defer mr.deinit();

    const comp = notif.asComponent();
    const spans = try ui.runner.renderToMemory(allocator, &mr, comp);
    defer allocator.free(spans);

    const dump = try mr.dump();
    defer allocator.free(dump);

    const expected =
        "[!] Title          \n" ++
        "Message here       \n" ++
        "                    \n";
    try std.testing.expectEqualStrings(expected, dump);
}
