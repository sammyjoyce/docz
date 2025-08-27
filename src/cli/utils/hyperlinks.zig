//! Enhanced hyperlink utilities using OSC 8 terminal capabilities
//! Builds on @src/term/ansi/hyperlink.zig with additional convenience functions

const std = @import("std");
const term_shared = @import("../../term/mod.zig");
const term_hyperlink = term_shared.ansi.hyperlink;
const term_caps = term_shared.caps;
const Allocator = std.mem.Allocator;

/// Enhanced hyperlink builder with intelligent fallbacks
pub const HyperlinkBuilder = struct {
    caps: term_caps.TermCaps,
    allocator: Allocator,

    pub fn init(allocator: Allocator) HyperlinkBuilder {
        return HyperlinkBuilder{
            .caps = term_caps.getTermCaps(),
            .allocator = allocator,
        };
    }

    /// Write a hyperlink with automatic fallback to plain text if not supported
    pub fn writeLink(self: HyperlinkBuilder, writer: anytype, text: []const u8, url: []const u8) !void {
        if (self.caps.supportsHyperlinks()) {
            try term_hyperlink.writeHyperlink(writer, self.caps, self.allocator, text, url);
        } else {
            // Fallback: display as "text (url)" or just text if URL is too long
            if (url.len > 50) {
                try writer.print("{s}", .{text});
            } else {
                try writer.print("{s} ({s})", .{ text, url });
            }
        }
    }

    /// Create a documentation link for CLI options/commands
    pub fn writeDocLink(
        self: HyperlinkBuilder,
        writer: anytype,
        text: []const u8,
        section: []const u8,
    ) !void {
        const base_url = "https://docs.anthropic.com/claude/docs";
        const url = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ base_url, section });
        defer self.allocator.free(url);

        try self.writeLink(writer, text, url);
    }

    /// Create a GitHub issue link for bug reports
    pub fn writeIssueLink(
        self: HyperlinkBuilder,
        writer: anytype,
        text: []const u8,
        title: []const u8,
    ) !void {
        const repo_url = "https://github.com/anthropic/docz/issues/new";
        const encoded_title = try std.Uri.escapeString(self.allocator, title);
        defer self.allocator.free(encoded_title);

        const url = try std.fmt.allocPrint(self.allocator, "{s}?title={s}", .{ repo_url, encoded_title });
        defer self.allocator.free(url);

        try self.writeLink(writer, text, url);
    }

    /// Create a link to file in the local filesystem (file:// protocol)
    pub fn writeFileLink(
        self: HyperlinkBuilder,
        writer: anytype,
        text: []const u8,
        file_path: []const u8,
    ) !void {
        // Convert relative paths to absolute
        var abs_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const abs_path = std.fs.realpath(file_path, &abs_path_buf) catch file_path;

        const url = try std.fmt.allocPrint(self.allocator, "file://{s}", .{abs_path});
        defer self.allocator.free(url);

        try self.writeLink(writer, text, url);
    }

    /// Create an email link (mailto: protocol)
    pub fn writeEmailLink(
        self: HyperlinkBuilder,
        writer: anytype,
        text: []const u8,
        email: []const u8,
        subject: ?[]const u8,
    ) !void {
        const url = if (subject) |subj| blk: {
            const encoded_subject = try std.Uri.escapeString(self.allocator, subj);
            defer self.allocator.free(encoded_subject);
            break :blk try std.fmt.allocPrint(self.allocator, "mailto:{s}?subject={s}", .{ email, encoded_subject });
        } else try std.fmt.allocPrint(self.allocator, "mailto:{s}", .{email});
        defer self.allocator.free(url);

        try self.writeLink(writer, text, url);
    }
};

/// Predefined links for common DocZ use cases
pub const CommonLinks = struct {
    pub fn writeAnthropicDocs(writer: anytype, allocator: Allocator, text: []const u8) !void {
        const builder = HyperlinkBuilder.init(allocator);
        try builder.writeLink(writer, text, "https://docs.anthropic.com/claude/docs");
    }

    pub fn writeGitHubRepo(writer: anytype, allocator: Allocator, text: []const u8) !void {
        const builder = HyperlinkBuilder.init(allocator);
        try builder.writeLink(writer, text, "https://github.com/anthropic/docz");
    }

    pub fn writeAPIReference(writer: anytype, allocator: Allocator, text: []const u8) !void {
        const builder = HyperlinkBuilder.init(allocator);
        try builder.writeLink(writer, text, "https://docs.anthropic.com/claude/reference");
    }

    pub fn writeOAuthSetup(writer: anytype, allocator: Allocator, text: []const u8) !void {
        const builder = HyperlinkBuilder.init(allocator);
        try builder.writeLink(writer, text, "https://docs.anthropic.com/claude/docs/oauth");
    }

    pub fn writeModelInfo(writer: anytype, allocator: Allocator, text: []const u8, model: []const u8) !void {
        const builder = HyperlinkBuilder.init(allocator);
        const url = try std.fmt.allocPrint(allocator, "https://docs.anthropic.com/claude/docs/models#{s}", .{model});
        defer allocator.free(url);
        try builder.writeLink(writer, text, url);
    }
};

/// Interactive link menu for help systems
pub const LinkMenu = struct {
    links: std.ArrayList(LinkItem),
    allocator: Allocator,

    const LinkItem = struct {
        title: []const u8,
        url: []const u8,
        description: ?[]const u8 = null,
    };

    pub fn init(allocator: Allocator) LinkMenu {
        return LinkMenu{
            .links = std.ArrayList(LinkItem).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LinkMenu) void {
        self.links.deinit();
    }

    pub fn addLink(self: *LinkMenu, title: []const u8, url: []const u8, description: ?[]const u8) !void {
        try self.links.append(LinkItem{
            .title = title,
            .url = url,
            .description = description,
        });
    }

    pub fn render(self: LinkMenu, writer: anytype) !void {
        const builder = HyperlinkBuilder.init(self.allocator);

        try writer.writeAll("📚 Helpful Links:\n\n");

        for (self.links.items, 1..) |link, i| {
            try writer.print("  {}. ", .{i});
            try builder.writeLink(writer, link.title, link.url);

            if (link.description) |desc| {
                try writer.print(" - {s}", .{desc});
            }

            try writer.writeAll("\n");
        }

        try writer.writeAll("\n");

        if (builder.caps.supportsHyperlinks()) {
            try writer.writeAll("💡 Tip: Click on the links above or Ctrl+Click to open in browser\n");
        } else {
            try writer.writeAll("💡 Tip: Copy and paste the URLs into your browser\n");
        }
    }

    /// Populate with default DocZ help links
    pub fn addDefaultLinks(self: *LinkMenu) !void {
        try self.addLink("Getting Started", "https://docs.anthropic.com/claude/docs/getting-started", "Quick start guide");
        try self.addLink("API Reference", "https://docs.anthropic.com/claude/reference", "Complete API documentation");
        try self.addLink("OAuth Setup", "https://docs.anthropic.com/claude/docs/oauth", "Setup Claude Pro/Max authentication");
        try self.addLink("Model Guide", "https://docs.anthropic.com/claude/docs/models", "Compare Claude models");
        try self.addLink("Rate Limits", "https://docs.anthropic.com/claude/docs/rate-limits", "Understand API limits");
        try self.addLink("GitHub Issues", "https://github.com/anthropic/docz/issues", "Report bugs or request features");
        try self.addLink("Community", "https://discord.gg/anthropic", "Join the Discord community");
    }
};
