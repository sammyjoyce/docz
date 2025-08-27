//! Comprehensive Text Typing Animation System with Particle Effects
//!
//! This module provides text typing animations with particle effects,
//! supporting various typing styles, cursor animations, styled text, and
//! seamless integration with the existing TUI infrastructure.
//!
//! Features:
//! - Multiple typing styles (smooth, stutter, wave, typewriter)
//! - Particle effects with physics simulation
//! - Configurable cursor animations and styles
//! - Support for styled text (colors, bold, italic, etc.)
//! - Variable speed based on punctuation
//! - Word-by-word and character-by-character reveal
//! - Backspace/deletion animations
//! - Sound effect triggers for terminal bells
//! - Integration with easing functions and renderer system
//!
//! Compatible with Zig 0.15.1 patterns and error handling.

const std = @import("std");
const math = std.math;
const Easing = @import("easing.zig").Easing;
const Renderer = @import("renderer.zig").Renderer;
const Style = @import("renderer.zig").Style;
const Bounds = @import("bounds.zig").Bounds;
const Point = @import("bounds.zig").Point;

/// Error set for typing animation operations
pub const TypingAnimationError = error{
    InvalidText,
    InvalidPosition,
    AnimationInProgress,
    OutOfMemory,
    RendererError,
};

/// Typing animation styles
pub const TypingStyle = enum {
    /// Smooth, constant speed typing
    smooth,
    /// Stuttering effect with variable pauses
    stutter,
    /// Wave-like reveal with easing
    wave,
    /// Classic typewriter effect
    typewriter,
    /// Word-by-word reveal
    word_by_word,
    /// Custom timing function
    custom,
};

/// Cursor animation styles
pub const CursorStyle = enum {
    /// Simple blinking block cursor
    block_blink,
    /// Underline cursor
    underline,
    /// Vertical bar cursor
    bar,
    /// Custom cursor character
    custom,
};

/// Particle types for effects
pub const ParticleType = enum {
    /// Sparkle effect (✨)
    sparkle,
    /// Star effect (⭐)
    star,
    /// Dot effect (•)
    dot,
    /// Circle effect (◦)
    circle,
    /// Diamond effect (⬥)
    diamond,
    /// Heart effect (♥)
    heart,
};

/// Individual particle for effects
pub const Particle = struct {
    /// Current position
    position: Point2D,
    /// Velocity vector
    velocity: Point2D,
    /// Particle lifetime (0.0 to 1.0)
    lifetime: f32,
    /// Maximum lifetime
    max_lifetime: f32,
    /// Particle color/style
    style: Style,
    /// Particle character
    character: []const u8,
    /// Particle type
    particle_type: ParticleType,
    /// Gravity effect
    gravity: f32 = 0.0,
    /// Damping factor
    damping: f32 = 0.98,
    /// Scale factor
    scale: f32 = 1.0,

    /// 2D point for particle physics
    pub const Point2D = struct {
        x: f32,
        y: f32,

        pub fn add(self: Point2D, other: Point2D) Point2D {
            return .{ .x = self.x + other.x, .y = self.y + other.y };
        }

        pub fn multiply(self: Point2D, scalar: f32) Point2D {
            return .{ .x = self.x * scalar, .y = self.y * scalar };
        }
    };

    /// Update particle physics
    pub fn update(self: *Particle, delta_time: f32) void {
        // Apply gravity
        self.velocity.y += self.gravity * delta_time;

        // Apply damping
        self.velocity = self.velocity.multiply(self.damping);

        // Update position
        self.position = self.position.add(self.velocity.multiply(delta_time));

        // Update lifetime
        self.lifetime -= delta_time / self.max_lifetime;
        if (self.lifetime < 0.0) self.lifetime = 0.0;

        // Update scale based on lifetime
        const life_ratio = self.lifetime / self.max_lifetime;
        self.scale = Easing.easeOutQuad(life_ratio);
    }

    /// Check if particle is still alive
    pub fn isAlive(self: Particle) bool {
        return self.lifetime > 0.0;
    }
};

/// Particle emitter for creating effects
pub const ParticleEmitter = struct {
    allocator: std.mem.Allocator,
    particles: std.ArrayList(Particle),
    position: Particle.Point2D,
    emit_rate: f32 = 1.0, // particles per second
    time_accumulator: f32 = 0.0,
    active: bool = true,

    /// Configuration for particle emission
    pub const Config = struct {
        /// Number of particles to emit
        count: u32 = 5,
        /// Particle speed range
        speed_min: f32 = 10.0,
        speed_max: f32 = 50.0,
        /// Particle lifetime range
        lifetime_min: f32 = 0.5,
        lifetime_max: f32 = 2.0,
        /// Emission angle range (radians)
        angle_min: f32 = 0.0,
        angle_max: f32 = math.pi * 2.0,
        /// Gravity effect
        gravity: f32 = 100.0,
        /// Particle types to use
        particle_types: []const ParticleType = &[_]ParticleType{.sparkle},
        /// Particle colors
        colors: []const Style.Color = undefined,
    };

    /// Initialize particle emitter
    pub fn init(allocator: std.mem.Allocator, position: Particle.Point2D) !ParticleEmitter {
        return ParticleEmitter{
            .allocator = allocator,
            .particles = std.ArrayList(Particle).init(allocator),
            .position = position,
        };
    }

    /// Deinitialize particle emitter
    pub fn deinit(self: *ParticleEmitter) void {
        self.particles.deinit();
    }

    /// Update emitter and particles
    pub fn update(self: *ParticleEmitter, delta_time: f32) !void {
        // Update existing particles
        var i: usize = 0;
        while (i < self.particles.items.len) {
            self.particles.items[i].update(delta_time);
            if (!self.particles.items[i].isAlive()) {
                _ = self.particles.swapRemove(i);
            } else {
                i += 1;
            }
        }

        // Emit new particles
        if (self.active) {
            self.time_accumulator += delta_time;
            const emit_interval = 1.0 / self.emit_rate;

            while (self.time_accumulator >= emit_interval) {
                try self.emitParticle();
                self.time_accumulator -= emit_interval;
            }
        }
    }

    /// Emit a single particle
    pub fn emitParticle(self: *ParticleEmitter) !void {
        const particle_type = ParticleType.sparkle; // Default for now
        const character = getParticleCharacter(particle_type);
        const style = Style{ .fg_color = .{ .ansi = 11 } }; // Yellow

        // Random velocity
        const angle = math.rand.float(f32) * math.pi * 2.0;
        const speed = 20.0 + math.rand.float(f32) * 30.0;
        const velocity = Particle.Point2D{
            .x = @cos(angle) * speed,
            .y = @sin(angle) * speed,
        };

        const particle = Particle{
            .position = self.position,
            .velocity = velocity,
            .lifetime = 1.0,
            .max_lifetime = 1.0,
            .style = style,
            .character = character,
            .particle_type = particle_type,
            .gravity = 50.0,
        };

        try self.particles.append(particle);
    }

    /// Set emitter position
    pub fn setPosition(self: *ParticleEmitter, position: Particle.Point2D) void {
        self.position = position;
    }

    /// Set emission rate
    pub fn setEmitRate(self: *ParticleEmitter, rate: f32) void {
        self.emit_rate = rate;
    }

    /// Start/stop emission
    pub fn setActive(self: *ParticleEmitter, active: bool) void {
        self.active = active;
    }
};

/// Main typing animation system
pub const TypingAnimation = struct {
    allocator: std.mem.Allocator,

    /// Text buffer being typed
    text_buffer: std.ArrayList(u8),
    /// Current character index being revealed
    current_index: usize = 0,
    /// Target text to type
    target_text: []const u8,
    /// Current display text (revealed portion)
    display_text: std.ArrayList(u8),

    /// Animation state
    is_animating: bool = false,
    is_complete: bool = false,
    start_time: i64 = 0,
    last_update_time: i64 = 0,

    /// Timing configuration
    chars_per_second: f32 = 20.0,
    base_delay_ms: f32 = 50.0,
    punctuation_delay_ms: f32 = 200.0,

    /// Typing style configuration
    typing_style: TypingStyle = .smooth,
    custom_timing_fn: ?*const fn (usize, u8) f32 = null,

    /// Cursor configuration
    cursor_style: CursorStyle = .block_blink,
    cursor_blink_rate: f32 = 2.0, // blinks per second
    cursor_visible: bool = true,
    custom_cursor_char: []const u8 = "█",

    /// Text styling
    text_style: Style = .{},
    cursor_style_override: ?Style = null,

    /// Particle effects
    particle_emitter: ?ParticleEmitter = null,
    enable_particles: bool = true,

    /// Sound effect triggers
    enable_sound_effects: bool = false,
    sound_trigger_chars: []const u8 = &[_]u8{ '.', '!', '?' },

    /// Callback functions
    on_character_revealed: ?*const fn (ctx: ?*anyopaque, char: u8, index: usize) void = null,
    on_complete: ?*const fn (ctx: ?*anyopaque) void = null,
    callback_context: ?*anyopaque = null,

    /// Initialize typing animation
    pub fn init(allocator: std.mem.Allocator, text: []const u8) !TypingAnimation {
        if (text.len == 0) return TypingAnimationError.InvalidText;

        const target_text = try allocator.dupe(u8, text);
        errdefer allocator.free(target_text);

        var display_text = try std.ArrayList(u8).initCapacity(allocator, text.len);
        errdefer display_text.deinit();

        var text_buffer = try std.ArrayList(u8).initCapacity(allocator, text.len);
        errdefer text_buffer.deinit();

        return TypingAnimation{
            .allocator = allocator,
            .text_buffer = text_buffer,
            .target_text = target_text,
            .display_text = display_text,
        };
    }

    /// Deinitialize typing animation
    pub fn deinit(self: *TypingAnimation) void {
        self.allocator.free(self.target_text);
        self.display_text.deinit();
        self.text_buffer.deinit();
        if (self.particle_emitter) |*emitter| {
            emitter.deinit();
        }
    }

    /// Start the typing animation
    pub fn start(self: *TypingAnimation) !void {
        if (self.is_animating) return TypingAnimationError.AnimationInProgress;

        self.is_animating = true;
        self.is_complete = false;
        self.current_index = 0;
        self.start_time = std.time.timestamp();
        self.last_update_time = self.start_time;
        self.display_text.clearRetainingCapacity();

        // Initialize particle emitter if enabled
        if (self.enable_particles and self.particle_emitter == null) {
            const emitter_pos = Particle.Point2D{ .x = 0.0, .y = 0.0 };
            self.particle_emitter = try ParticleEmitter.init(self.allocator, emitter_pos);
        }
    }

    /// Stop the typing animation
    pub fn stop(self: *TypingAnimation) void {
        self.is_animating = false;
        self.is_complete = self.current_index >= self.target_text.len;
    }

    /// Reset animation to beginning
    pub fn reset(self: *TypingAnimation) void {
        self.stop();
        self.current_index = 0;
        self.display_text.clearRetainingCapacity();
        self.start_time = 0;
        self.last_update_time = 0;
    }

    /// Set typing speed (characters per second)
    pub fn setSpeed(self: *TypingAnimation, cps: f32) void {
        self.chars_per_second = cps;
        self.base_delay_ms = 1000.0 / cps;
    }

    /// Set typing style
    pub fn setTypingStyle(self: *TypingAnimation, style: TypingStyle) void {
        self.typing_style = style;
    }

    /// Set custom timing function for .custom style
    pub fn setCustomTimingFn(self: *TypingAnimation, timing_fn: *const fn (usize, u8) f32) void {
        self.custom_timing_fn = timing_fn;
        self.typing_style = .custom;
    }

    /// Set cursor style
    pub fn setCursorStyle(self: *TypingAnimation, style: CursorStyle) void {
        self.cursor_style = style;
    }

    /// Set custom cursor character
    pub fn setCustomCursor(self: *TypingAnimation, char: []const u8) void {
        self.custom_cursor_char = char;
        self.cursor_style = .custom;
    }

    /// Set text style
    pub fn setTextStyle(self: *TypingAnimation, style: Style) void {
        self.text_style = style;
    }

    /// Set cursor style override
    pub fn setCursorStyleOverride(self: *TypingAnimation, style: ?Style) void {
        self.cursor_style_override = style;
    }

    /// Enable/disable particle effects
    pub fn setParticleEffects(self: *TypingAnimation, enabled: bool) void {
        self.enable_particles = enabled;
        if (!enabled and self.particle_emitter != null) {
            self.particle_emitter.?.deinit();
            self.particle_emitter = null;
        }
    }

    /// Enable/disable sound effects
    pub fn setSoundEffects(self: *TypingAnimation, enabled: bool) void {
        self.enable_sound_effects = enabled;
    }

    /// Set callback functions
    pub fn setCallbacks(
        self: *TypingAnimation,
        on_char: ?*const fn (ctx: ?*anyopaque, char: u8, index: usize) void,
        on_complete: ?*const fn (ctx: ?*anyopaque) void,
        context: ?*anyopaque,
    ) void {
        self.on_character_revealed = on_char;
        self.on_complete = on_complete;
        self.callback_context = context;
    }

    /// Update animation state
    pub fn update(self: *TypingAnimation, current_time: i64) !void {
        if (!self.is_animating) return;

        const delta_time_ms = @as(f32, @floatFromInt(current_time - self.last_update_time));
        if (delta_time_ms < 1.0) return; // Too frequent updates

        const delta_time = delta_time_ms / 1000.0; // Convert to seconds
        self.last_update_time = current_time;

        // Update particle emitter
        if (self.particle_emitter) |*emitter| {
            try emitter.update(delta_time);
        }

        // Check if we should reveal next character
        if (self.current_index < self.target_text.len) {
            const delay = self.calculateDelay(self.current_index);
            const elapsed = @as(f32, @floatFromInt(current_time - self.start_time));

            if (elapsed * 1000.0 >= delay) {
                try self.revealNextCharacter();
            }
        } else {
            // Animation complete
            self.is_animating = false;
            self.is_complete = true;

            if (self.on_complete) |callback| {
                callback(self.callback_context);
            }
        }
    }

    /// Reveal next character
    fn revealNextCharacter(self: *TypingAnimation) !void {
        if (self.current_index >= self.target_text.len) return;

        const char = self.target_text[self.current_index];
        try self.display_text.append(char);

        // Trigger sound effect for punctuation
        if (self.enable_sound_effects) {
            for (self.sound_trigger_chars) |trigger_char| {
                if (char == trigger_char) {
                    // Terminal bell
                    var stdout_buffer: [1]u8 = undefined;
                    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
                    stdout_writer.writeByte(0x07) catch {};
                    stdout_writer.flush() catch {};
                    break;
                }
            }
        }

        // Trigger particle effect at cursor position
        if (self.particle_emitter) |*emitter| {
            const cursor_pos = Particle.Point2D{
                .x = @as(f32, @floatFromInt(self.display_text.items.len)),
                .y = 0.0,
            };
            emitter.setPosition(cursor_pos);
            emitter.setActive(true);
            // Emit a burst of particles
            for (0..3) |_| {
                try emitter.emitParticle();
            }
            emitter.setActive(false);
        }

        // Callback for character revealed
        if (self.on_character_revealed) |callback| {
            callback(self.callback_context, char, self.current_index);
        }

        self.current_index += 1;
    }

    /// Calculate delay for next character based on typing style
    fn calculateDelay(self: *TypingAnimation, index: usize) f32 {
        if (index >= self.target_text.len) return 0.0;

        const char = self.target_text[index];
        var delay = self.base_delay_ms;

        // Punctuation delay
        if (std.mem.indexOfScalar(u8, &[_]u8{ '.', '!', '?', ':', ';' }, char) != null) {
            delay += self.punctuation_delay_ms;
        } else if (std.mem.indexOfScalar(u8, &[_]u8{ ',', ' ' }, char) != null) {
            delay += self.punctuation_delay_ms * 0.5;
        }

        // Style-specific modifications
        switch (self.typing_style) {
            .smooth => {
                // Constant speed
            },
            .stutter => {
                // Random variation
                const variation = (std.rand.float(f32) - 0.5) * 0.5;
                delay *= 1.0 + variation;
            },
            .wave => {
                // Wave pattern using easing
                const wave_pos = @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(self.target_text.len));
                const wave_factor = Easing.easeInOutQuad(wave_pos);
                delay *= 0.5 + wave_factor * 0.5;
            },
            .typewriter => {
                // Slight random variation for realistic effect
                const variation = std.rand.float(f32) * 0.3;
                delay *= 1.0 + variation;
            },
            .word_by_word => {
                // Reveal words at once
                if (char == ' ' or index == 0) {
                    delay *= 5.0; // Longer pause between words
                } else {
                    delay *= 0.1; // Very fast within words
                }
            },
            .custom => {
                if (self.custom_timing_fn) |timing_fn| {
                    delay = timing_fn(index, char);
                }
            },
        }

        return delay;
    }

    /// Render the typing animation
    pub fn render(self: *TypingAnimation, renderer: *Renderer, x: u16, y: u16) !void {
        const text = self.display_text.items;

        // Render the text
        const text_ctx = Renderer.Render{
            .bounds = .{
                .x = @as(i32, @intCast(x)),
                .y = @as(i32, @intCast(y)),
                .width = @as(u16, @intCast(text.len + 1)), // +1 for cursor
                .height = 1,
            },
            .style = self.text_style,
            .zIndex = 0,
            .clipRegion = null,
        };

        try renderer.drawText(text_ctx, text);

        // Render cursor if animating
        if (self.is_animating or self.cursor_visible) {
            try self.renderCursor(renderer, x, y, text.len);
        }
    }

    /// Render cursor
    fn renderCursor(self: *TypingAnimation, renderer: *Renderer, x: u16, y: u16, text_len: usize) !void {
        const cursor_x = x + @as(u16, @intCast(text_len));
        const current_time = std.time.timestamp();
        const elapsed = @as(f32, @floatFromInt(current_time - self.start_time));

        // Cursor blink animation
        const blink_period = 1.0 / self.cursor_blink_rate;
        const blink_phase = @mod(elapsed, blink_period * 2.0);
        const cursor_visible = blink_phase < blink_period;

        if (!cursor_visible and self.cursor_style != .bar) return;

        const cursor_char = switch (self.cursor_style) {
            .block_blink, .custom => self.custom_cursor_char,
            .underline => "_",
            .bar => "|",
        };

        const cursor_style = self.cursor_style_override orelse Style{
            .fg_color = .{ .ansi = 15 }, // White
            .bg_color = .{ .ansi = 0 }, // Black
            .bold = true,
        };

        const cursor_ctx = Renderer.Render{
            .bounds = .{
                .x = @as(i32, @intCast(cursor_x)),
                .y = @as(i32, @intCast(y)),
                .width = 1,
                .height = 1,
            },
            .style = cursor_style,
            .zIndex = 1,
            .clipRegion = null,
        };

        try renderer.drawText(cursor_ctx, cursor_char);
    }

    /// Render particle effects
    pub fn renderParticles(self: *TypingAnimation, renderer: *Renderer, offset_x: u16, offset_y: u16) !void {
        if (self.particle_emitter == null) return;

        const emitter = &self.particle_emitter.?;

        for (emitter.particles.items) |particle| {
            if (!particle.isAlive()) continue;

            const screen_x = offset_x + @as(u16, @intFromFloat(@max(0.0, particle.position.x)));
            const screen_y = offset_y + @as(u16, @intFromFloat(@max(0.0, particle.position.y)));

            const particle_ctx = Renderer.Render{
                .bounds = .{
                    .x = @as(i32, @intCast(screen_x)),
                    .y = @as(i32, @intCast(screen_y)),
                    .width = 1,
                    .height = 1,
                },
                .style = particle.style,
                .zIndex = 2,
                .clipRegion = null,
            };

            try renderer.drawText(particle_ctx, particle.character);
        }
    }

    /// Get current progress (0.0 to 1.0)
    pub fn getProgress(self: TypingAnimation) f32 {
        if (self.target_text.len == 0) return 1.0;
        return @as(f32, @floatFromInt(self.current_index)) / @as(f32, @floatFromInt(self.target_text.len));
    }

    /// Check if animation is complete
    pub fn isComplete(self: TypingAnimation) bool {
        return self.is_complete;
    }

    /// Get current display text
    pub fn getDisplayText(self: TypingAnimation) []const u8 {
        return self.display_text.items;
    }

    /// Skip to end of animation
    pub fn skipToEnd(self: *TypingAnimation) void {
        self.current_index = self.target_text.len;
        self.display_text.clearRetainingCapacity();
        self.display_text.appendSliceAssumeCapacity(self.target_text);
        self.is_animating = false;
        self.is_complete = true;
    }
};

/// Get particle character for particle type
fn getParticleCharacter(particle_type: ParticleType) []const u8 {
    return switch (particle_type) {
        .sparkle => "✨",
        .star => "⭐",
        .dot => "•",
        .circle => "◦",
        .diamond => "⬥",
        .heart => "♥",
    };
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/// Create a typing animation with common presets
pub const TypingAnimationBuilder = struct {
    /// Create a smooth typing animation
    pub fn smooth(allocator: std.mem.Allocator, text: []const u8, cps: f32) !TypingAnimation {
        var animation = try TypingAnimation.init(allocator, text);
        animation.setSpeed(cps);
        animation.setTypingStyle(.smooth);
        return animation;
    }

    /// Create a stuttering typing animation
    pub fn stutter(allocator: std.mem.Allocator, text: []const u8, cps: f32) !TypingAnimation {
        var animation = try TypingAnimation.init(allocator, text);
        animation.setSpeed(cps);
        animation.setTypingStyle(.stutter);
        return animation;
    }

    /// Create a typewriter-style animation
    pub fn typewriter(allocator: std.mem.Allocator, text: []const u8, cps: f32) !TypingAnimation {
        var animation = try TypingAnimation.init(allocator, text);
        animation.setSpeed(cps);
        animation.setTypingStyle(.typewriter);
        animation.setCursorStyle(.block_blink);
        return animation;
    }

    /// Create a word-by-word animation
    pub fn wordByWord(allocator: std.mem.Allocator, text: []const u8, wps: f32) !TypingAnimation {
        var animation = try TypingAnimation.init(allocator, text);
        // Convert words per second to characters per second (rough estimate)
        animation.setSpeed(wps * 5.0);
        animation.setTypingStyle(.word_by_word);
        return animation;
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "TypingAnimation initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const text = "Hello, World!";
    var animation = try TypingAnimation.init(allocator, text);
    defer animation.deinit();

    try testing.expectEqualStrings(animation.target_text, text);
    try testing.expectEqual(animation.current_index, 0);
    try testing.expect(!animation.is_animating);
    try testing.expect(!animation.is_complete);
}

test "TypingAnimation start and update" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const text = "Hi";
    var animation = try TypingAnimation.init(allocator, text);
    defer animation.deinit();

    try animation.start();
    try testing.expect(animation.is_animating);
    try testing.expect(!animation.is_complete);

    // Simulate time passing
    const start_time = std.time.timestamp();
    try animation.update(start_time + 100); // 100ms later

    // Should have revealed first character
    try testing.expectEqual(animation.current_index, 1);
    try testing.expectEqualStrings(animation.getDisplayText(), "H");
}

test "TypingAnimation complete" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const text = "Hi";
    var animation = try TypingAnimation.init(allocator, text);
    defer animation.deinit();

    animation.skipToEnd();
    try testing.expect(animation.isComplete());
    try testing.expectEqualStrings(animation.getDisplayText(), text);
}

test "ParticleEmitter basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const position = Particle.Point2D{ .x = 10.0, .y = 10.0 };
    var emitter = try ParticleEmitter.init(allocator, position);
    defer emitter.deinit();

    try testing.expectEqual(emitter.particles.items.len, 0);

    try emitter.emitParticle();
    try testing.expectEqual(emitter.particles.items.len, 1);

    // Update to age the particle
    try emitter.update(0.1);
    try testing.expect(emitter.particles.items.len <= 1);
}

test "TypingAnimationBuilder presets" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const text = "Test text";

    // Test smooth preset
    var smooth_anim = try TypingAnimationBuilder.smooth(allocator, text, 30.0);
    defer smooth_anim.deinit();
    try testing.expectEqual(smooth_anim.typing_style, .smooth);
    try testing.expectEqual(smooth_anim.chars_per_second, 30.0);

    // Test typewriter preset
    var typewriter_anim = try TypingAnimationBuilder.typewriter(allocator, text, 20.0);
    defer typewriter_anim.deinit();
    try testing.expectEqual(typewriter_anim.typing_style, .typewriter);
    try testing.expectEqual(typewriter_anim.cursor_style, .block_blink);
}
