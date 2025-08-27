//! Typing Animation Demo
//!
//! This demo showcases the typing animation system with:
//! - Multiple typing styles (smooth, stutter, wave, typewriter)
//! - Particle effects and cursor animations
//! - Styled text support
//! - Customizable animation parameters
//! - Real-time animation control

const std = @import("std");
const tui = @import("tui_shared");
const term = @import("term_shared");

/// Demo configuration
const DemoConfig = struct {
    show_styles: bool = true,
    show_particles: bool = true,
    show_styled_text: bool = true,
    interactive_mode: bool = true,
    animation_duration_ms: u64 = 3000,
};

/// Typing Animation Demo
pub const TypingAnimationDemo = struct {
    allocator: std.mem.Allocator,
    terminal: term.Terminal,
    config: DemoConfig,

    pub fn init(allocator: std.mem.Allocator, config: DemoConfig) !TypingAnimationDemo {
        const terminal = try term.Terminal.init(allocator);

        return TypingAnimationDemo{
            .allocator = allocator,
            .terminal = terminal,
            .config = config,
        };
    }

    pub fn deinit(self: *TypingAnimationDemo) void {
        self.terminal.deinit();
    }

    /// Run the complete typing animation demo
    pub fn run(self: *TypingAnimationDemo) !void {
        try self.showWelcome();

        if (self.config.show_styles) {
            try self.demoTypingStyles();
        }

        if (self.config.show_particles) {
            try self.demoParticleEffects();
        }

        if (self.config.show_styled_text) {
            try self.demoStyledText();
        }

        if (self.config.interactive_mode) {
            try self.interactiveDemo();
        }

        try self.showConclusion();
    }

    /// Show welcome message
    fn showWelcome(self: *TypingAnimationDemo) !void {
        try self.terminal.clear();

        const welcome_text =
            \\🎬 Typing Animation Demo
            \\========================
            \\
            \\This demo showcases text typing animations with:
            \\• Multiple typing styles (smooth, stutter, wave, typewriter)
            \\• Particle effects and cursor animations
            \\• Styled text support with colors and formatting
            \\• Customizable animation parameters
            \\• Real-time animation control
            \\
        ;

        try self.terminal.print(welcome_text, .{});
        try self.waitForUser();
    }

    /// Demonstrate different typing styles
    fn demoTypingStyles(self: *TypingAnimationDemo) !void {
        try self.showSectionHeader("⌨️  Typing Styles");

        const sample_text = "Hello, World! This is a typing animation demo showcasing different styles and effects.";

        // Smooth typing
        try self.terminal.print("🎯 Smooth Typing:\n", .{ .bold = true });
        var smooth_anim = try tui.TypingAnimationBuilder.init(self.allocator, &self.terminal)
            .withText(sample_text)
            .withStyle(.smooth)
            .withSpeed(30)
            .build();
        defer smooth_anim.deinit();

        try smooth_anim.start();
        try self.waitForAnimation(&smooth_anim);

        try self.terminal.print("\n\n", .{});

        // Stutter typing
        try self.terminal.print("🎯 Stutter Typing:\n", .{ .bold = true });
        var stutter_anim = try tui.TypingAnimationBuilder.init(self.allocator, &self.terminal)
            .withText("This text has a stuttering effect for dramatic impact!")
            .withStyle(.stutter)
            .withSpeed(25)
            .build();
        defer stutter_anim.deinit();

        try stutter_anim.start();
        try self.waitForAnimation(&stutter_anim);

        try self.terminal.print("\n\n", .{});

        // Wave typing
        try self.terminal.print("🎯 Wave Typing:\n", .{ .bold = true });
        var wave_anim = try tui.TypingAnimationBuilder.init(self.allocator, &self.terminal)
            .withText("This creates a wave-like typing effect with varying speeds.")
            .withStyle(.wave)
            .withSpeed(20)
            .build();
        defer wave_anim.deinit();

        try wave_anim.start();
        try self.waitForAnimation(&wave_anim);

        try self.terminal.print("\n\n", .{});

        // Typewriter typing
        try self.terminal.print("🎯 Typewriter Typing:\n", .{ .bold = true });
        var typewriter_anim = try tui.TypingAnimationBuilder.init(self.allocator, &self.terminal)
            .withText("Classic typewriter sound effect with mechanical delays.")
            .withStyle(.typewriter)
            .withSpeed(15)
            .build();
        defer typewriter_anim.deinit();

        try typewriter_anim.start();
        try self.waitForAnimation(&typewriter_anim);

        try self.terminal.print("\n✅ Typing styles demo complete!\n", .{ .fg = .green });
        try self.waitForUser();
    }

    /// Demonstrate particle effects
    fn demoParticleEffects(self: *TypingAnimationDemo) !void {
        try self.showSectionHeader("✨ Particle Effects");

        try self.terminal.print("🎆 Particle effects can be added to typing animations:\n\n", .{});

        // Create animation with particles
        const particle_text = "This text has particle effects!";

        var particle_anim = try tui.TypingAnimationBuilder.init(self.allocator, &self.terminal)
            .withText(particle_text)
            .withStyle(.smooth)
            .withSpeed(25)
            .withParticles(true)
            .build();
        defer particle_anim.deinit();

        try self.terminal.print("🎯 With Particle Effects:\n", .{ .bold = true });
        try particle_anim.start();
        try self.waitForAnimation(&particle_anim);

        try self.terminal.print("\n\n", .{});

        // Compare without particles
        var no_particle_anim = try tui.TypingAnimationBuilder.init(self.allocator, &self.terminal)
            .withText(particle_text)
            .withStyle(.smooth)
            .withSpeed(25)
            .withParticles(false)
            .build();
        defer no_particle_anim.deinit();

        try self.terminal.print("🎯 Without Particle Effects:\n", .{ .bold = true });
        try no_particle_anim.start();
        try self.waitForAnimation(&no_particle_anim);

        try self.terminal.print("\n✅ Particle effects demo complete!\n", .{ .fg = .green });
        try self.waitForUser();
    }

    /// Demonstrate styled text
    fn demoStyledText(self: *TypingAnimationDemo) !void {
        try self.showSectionHeader("🎨 Styled Text");

        try self.terminal.print("💫 Text can be styled with colors and formatting:\n\n", .{});

        // Create styled text animation
        const styled_text =
            \\**Bold text** with *italic* and `code` formatting!
            \\## Headers ## and ~~strikethrough~~ effects.
            \\Colors: [red]Red[/red], [blue]Blue[/blue], [green]Green[/green]
        ;

        var styled_anim = try tui.TypingAnimationBuilder.init(self.allocator, &self.terminal)
            .withText(styled_text)
            .withStyle(.smooth)
            .withSpeed(20)
            .withStyledText(true)
            .build();
        defer styled_anim.deinit();

        try styled_anim.start();
        try self.waitForAnimation(&styled_anim);

        try self.terminal.print("\n\n", .{});

        // Custom styled animation
        const custom_text = "Custom [bold,red]styled[/bold,red] text with [italic,blue]multiple[/italic,blue] effects!";

        var custom_anim = try tui.TypingAnimationBuilder.init(self.allocator, &self.terminal)
            .withText(custom_text)
            .withStyle(.wave)
            .withSpeed(18)
            .withStyledText(true)
            .build();
        defer custom_anim.deinit();

        try custom_anim.start();
        try self.waitForAnimation(&custom_anim);

        try self.terminal.print("\n✅ Styled text demo complete!\n", .{ .fg = .green });
        try self.waitForUser();
    }

    /// Interactive demonstration
    fn interactiveDemo(self: *TypingAnimationDemo) !void {
        try self.showSectionHeader("🎮 Interactive Demo");

        try self.terminal.print("🎯 Try creating your own typing animation!\n\n", .{});

        // Demo custom animation
        const demo_text = "This is an interactive typing animation demo! You can customize speed, style, and effects.";

        var interactive_anim = try tui.TypingAnimationBuilder.init(self.allocator, &self.terminal)
            .withText(demo_text)
            .withStyle(.smooth)
            .withSpeed(22)
            .withParticles(true)
            .withStyledText(true)
            .build();
        defer interactive_anim.deinit();

        try interactive_anim.start();
        try self.waitForAnimation(&interactive_anim);

        try self.terminal.print("\n\n", .{});

        // Show animation controls
        try self.terminal.print("🎮 Animation Controls:\n", .{ .bold = true });
        try self.terminal.print("• Speed: Characters per second\n", .{});
        try self.terminal.print("• Style: smooth, stutter, wave, typewriter\n", .{});
        try self.terminal.print("• Particles: Enable/disable particle effects\n", .{});
        try self.terminal.print("• Styled Text: Enable markdown-style formatting\n", .{});
        try self.terminal.print("• Cursor: Blinking cursor animation\n", .{});

        try self.terminal.print("\n✅ Interactive demo complete!\n", .{ .fg = .green });
    }

    /// Show conclusion
    fn showConclusion(self: *TypingAnimationDemo) !void {
        try self.showSectionHeader("🎉 Demo Conclusion");

        try self.terminal.print("Advanced typing animation features demonstrated:\n\n", .{});

        const features = [_]struct { name: []const u8, icon: []const u8 }{
            .{ .name = "Multiple typing styles", .icon = "⌨️" },
            .{ .name = "Particle effects system", .icon = "✨" },
            .{ .name = "Styled text support", .icon = "🎨" },
            .{ .name = "Customizable parameters", .icon = "⚙️" },
            .{ .name = "Real-time animation control", .icon = "🎮" },
            .{ .name = "Cursor animations", .icon = "👆" },
            .{ .name = "Performance optimized", .icon = "🚀" },
        };

        for (features) |feature| {
            try self.terminal.print("  ", .{});
            try self.terminal.print(feature.icon, .{ .fg = .yellow });
            try self.terminal.print(" ", .{});
            try self.terminal.print(feature.name, .{ .fg = .cyan });
            try self.terminal.print("\n", .{});
        }

        try self.terminal.print("\n🚀 Typing animation demo complete!\n", .{ .bold = true, .fg = .green });
        try self.terminal.print("Thank you for exploring the typing animation system!\n", .{});
    }

    // ========== HELPER FUNCTIONS ==========

    fn showSectionHeader(self: *TypingAnimationDemo, title: []const u8) !void {
        try self.terminal.print("\n", .{});
        try self.terminal.print("=".repeat(50), .{ .fg = .cyan });
        try self.terminal.print("\n", .{});
        try self.terminal.print(title, .{ .bold = true, .fg = .yellow });
        try self.terminal.print("\n", .{});
        try self.terminal.print("=".repeat(50), .{ .fg = .cyan });
        try self.terminal.print("\n\n", .{});
    }

    fn waitForUser(self: *TypingAnimationDemo) !void {
        try self.terminal.print("\n💡 Press Enter to continue...", .{ .fg = .magenta });

        // In a real implementation, this would wait for actual user input
        // For demo purposes, just add a short delay
        std.time.sleep(2 * std.time.ns_per_s);
        try self.terminal.print(" ⏭️\n", .{});
    }

    fn waitForAnimation(self: *TypingAnimationDemo, animation: *tui.TypingAnimation) !void {
        // Wait for animation to complete
        const start_time = std.time.milliTimestamp();
        while (animation.isRunning()) {
            std.time.sleep(100 * std.time.ns_per_ms);

            // Safety timeout
            const elapsed = std.time.milliTimestamp() - start_time;
            if (elapsed > self.config.animation_duration_ms) {
                try animation.stop();
                break;
            }
        }
    }
};

/// Main demo entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = DemoConfig{
        .show_styles = true,
        .show_particles = true,
        .show_styled_text = true,
        .interactive_mode = true,
    };

    var demo = try TypingAnimationDemo.init(allocator, config);
    defer demo.deinit();

    try demo.run();
}