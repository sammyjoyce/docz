const std = @import("std");
const math = std.math;

/// Advanced easing functions for smooth animations
/// Based on Robert Penner's easing equations and modern animation libraries
pub const Easing = struct {

    // Linear (no easing)
    pub fn linear(t: f32) f32 {
        return t;
    }

    // Quadratic easing (power of 2)
    pub fn easeInQuad(t: f32) f32 {
        return t * t;
    }

    pub fn easeOutQuad(t: f32) f32 {
        return t * (2.0 - t);
    }

    pub fn easeInOutQuad(t: f32) f32 {
        return if (t < 0.5) 2.0 * t * t else -1.0 + (4.0 - 2.0 * t) * t;
    }

    // Cubic easing (power of 3)
    pub fn easeInCubic(t: f32) f32 {
        return t * t * t;
    }

    pub fn easeOutCubic(t: f32) f32 {
        const p = t - 1.0;
        return p * p * p + 1.0;
    }

    pub fn easeInOutCubic(t: f32) f32 {
        return if (t < 0.5) 4.0 * t * t * t else (t - 1.0) * (2.0 * t - 2.0) * (2.0 * t - 2.0) + 1.0;
    }

    // Quartic easing (power of 4)
    pub fn easeInQuart(t: f32) f32 {
        return t * t * t * t;
    }

    pub fn easeOutQuart(t: f32) f32 {
        const p = t - 1.0;
        return 1.0 - p * p * p * p;
    }

    pub fn easeInOutQuart(t: f32) f32 {
        const p = t - 1.0;
        return if (t < 0.5) 8.0 * t * t * t * t else 1.0 - 8.0 * p * p * p * p;
    }

    // Quintic easing (power of 5)
    pub fn easeInQuint(t: f32) f32 {
        return t * t * t * t * t;
    }

    pub fn easeOutQuint(t: f32) f32 {
        const p = t - 1.0;
        return p * p * p * p * p + 1.0;
    }

    pub fn easeInOutQuint(t: f32) f32 {
        const p = t - 1.0;
        return if (t < 0.5) 16.0 * t * t * t * t * t else 1.0 + 16.0 * p * p * p * p * p;
    }

    // Exponential easing
    pub fn easeInExpo(t: f32) f32 {
        return if (t == 0.0) 0.0 else math.pow(f32, 2.0, 10.0 * t - 10.0);
    }

    pub fn easeOutExpo(t: f32) f32 {
        return if (t == 1.0) 1.0 else 1.0 - math.pow(f32, 2.0, -10.0 * t);
    }

    pub fn easeInOutExpo(t: f32) f32 {
        if (t == 0.0) return 0.0;
        if (t == 1.0) return 1.0;
        return if (t < 0.5)
            math.pow(f32, 2.0, 20.0 * t - 10.0) / 2.0
        else
            (2.0 - math.pow(f32, 2.0, -20.0 * t + 10.0)) / 2.0;
    }

    // Circular easing
    pub fn easeInCirc(t: f32) f32 {
        return 1.0 - @sqrt(1.0 - t * t);
    }

    pub fn easeOutCirc(t: f32) f32 {
        const p = t - 1.0;
        return @sqrt(1.0 - p * p);
    }

    pub fn easeInOutCirc(t: f32) f32 {
        return if (t < 0.5)
            (1.0 - @sqrt(1.0 - 4.0 * t * t)) / 2.0
        else
            (@sqrt(1.0 - math.pow(f32, -2.0 * t + 2.0, 2.0)) + 1.0) / 2.0;
    }

    // Elastic easing (spring-like)
    pub fn easeInElastic(t: f32) f32 {
        const c4 = (2.0 * math.pi) / 3.0;
        if (t == 0.0) return 0.0;
        if (t == 1.0) return 1.0;
        return -math.pow(f32, 2.0, 10.0 * t - 10.0) * @sin((t * 10.0 - 10.75) * c4);
    }

    pub fn easeOutElastic(t: f32) f32 {
        const c4 = (2.0 * math.pi) / 3.0;
        if (t == 0.0) return 0.0;
        if (t == 1.0) return 1.0;
        return math.pow(f32, 2.0, -10.0 * t) * @sin((t * 10.0 - 0.75) * c4) + 1.0;
    }

    pub fn easeInOutElastic(t: f32) f32 {
        const c5 = (2.0 * math.pi) / 4.5;
        if (t == 0.0) return 0.0;
        if (t == 1.0) return 1.0;
        return if (t < 0.5)
            -(math.pow(f32, 2.0, 20.0 * t - 10.0) * @sin((20.0 * t - 11.125) * c5)) / 2.0
        else
            (math.pow(f32, 2.0, -20.0 * t + 10.0) * @sin((20.0 * t - 11.125) * c5)) / 2.0 + 1.0;
    }

    // Back easing (overshooting)
    pub fn easeInBack(t: f32) f32 {
        const c1 = 1.70158;
        const c3 = c1 + 1.0;
        return c3 * t * t * t - c1 * t * t;
    }

    pub fn easeOutBack(t: f32) f32 {
        const c1 = 1.70158;
        const c3 = c1 + 1.0;
        const p = t - 1.0;
        return 1.0 + c3 * p * p * p + c1 * p * p;
    }

    pub fn easeInOutBack(t: f32) f32 {
        const c1 = 1.70158;
        const c2 = c1 * 1.525;
        return if (t < 0.5)
            (math.pow(f32, 2.0 * t, 2.0) * ((c2 + 1.0) * 2.0 * t - c2)) / 2.0
        else
            (math.pow(f32, 2.0 * t - 2.0, 2.0) * ((c2 + 1.0) * (t * 2.0 - 2.0) + c2) + 2.0) / 2.0;
    }

    // Bounce easing
    pub fn easeInBounce(t: f32) f32 {
        return 1.0 - easeOutBounce(1.0 - t);
    }

    pub fn easeOutBounce(t: f32) f32 {
        const n1 = 7.5625;
        const d1 = 2.75;

        if (t < 1.0 / d1) {
            return n1 * t * t;
        } else if (t < 2.0 / d1) {
            const p = t - 1.5 / d1;
            return n1 * p * p + 0.75;
        } else if (t < 2.5 / d1) {
            const p = t - 2.25 / d1;
            return n1 * p * p + 0.9375;
        } else {
            const p = t - 2.625 / d1;
            return n1 * p * p + 0.984375;
        }
    }

    pub fn easeInOutBounce(t: f32) f32 {
        return if (t < 0.5)
            (1.0 - easeOutBounce(1.0 - 2.0 * t)) / 2.0
        else
            (1.0 + easeOutBounce(2.0 * t - 1.0)) / 2.0;
    }

    /// Spring physics animation
    pub const Spring = struct {
        stiffness: f32 = 100.0,
        damping: f32 = 10.0,
        mass: f32 = 1.0,

        pub fn calculate(self: Spring, t: f32) f32 {
            const omega = @sqrt(self.stiffness / self.mass);
            const zeta = self.damping / (2.0 * @sqrt(self.stiffness * self.mass));

            if (zeta < 1.0) {
                // Underdamped
                const omega_d = omega * @sqrt(1.0 - zeta * zeta);
                const amplitude = 1.0 / omega_d;
                const decay = @exp(-zeta * omega * t);
                return 1.0 - decay * (amplitude * @sin(omega_d * t) + @cos(omega_d * t));
            } else if (zeta == 1.0) {
                // Critically damped
                return 1.0 - @exp(-omega * t) * (1.0 + omega * t);
            } else {
                // Overdamped
                const r1 = -omega * (zeta - @sqrt(zeta * zeta - 1.0));
                const r2 = -omega * (zeta + @sqrt(zeta * zeta - 1.0));
                const c1 = (r2) / (r2 - r1);
                const c2 = -(r1) / (r2 - r1);
                return 1.0 - c1 * @exp(r1 * t) - c2 * @exp(r2 * t);
            }
        }
    };

    /// Bezier curve easing
    pub const Bezier = struct {
        x1: f32,
        y1: f32,
        x2: f32,
        y2: f32,

        pub fn calculate(self: Bezier, t: f32) f32 {
            // Simplified cubic bezier calculation
            // For production, use Newton-Raphson method for better accuracy
            const t2 = t * t;
            const t3 = t2 * t;
            const mt = 1.0 - t;
            const mt2 = mt * mt;

            return self.y1 * 3.0 * mt2 * t + self.y2 * 3.0 * mt * t2 + t3;
        }

        /// Common presets
        pub const ease = Bezier{ .x1 = 0.25, .y1 = 0.1, .x2 = 0.25, .y2 = 1.0 };
        pub const ease_in = Bezier{ .x1 = 0.42, .y1 = 0.0, .x2 = 1.0, .y2 = 1.0 };
        pub const ease_out = Bezier{ .x1 = 0.0, .y1 = 0.0, .x2 = 0.58, .y2 = 1.0 };
        pub const ease_in_out = Bezier{ .x1 = 0.42, .y1 = 0.0, .x2 = 0.58, .y2 = 1.0 };
    };

    /// Get easing function by name
    pub fn getByName(name: []const u8) ?*const fn (f32) f32 {
        const map = std.ComptimeStringMap(*const fn (f32) f32, .{
            .{ "linear", linear },
            .{ "easeInQuad", easeInQuad },
            .{ "easeOutQuad", easeOutQuad },
            .{ "easeInOutQuad", easeInOutQuad },
            .{ "easeInCubic", easeInCubic },
            .{ "easeOutCubic", easeOutCubic },
            .{ "easeInOutCubic", easeInOutCubic },
            .{ "easeInQuart", easeInQuart },
            .{ "easeOutQuart", easeOutQuart },
            .{ "easeInOutQuart", easeInOutQuart },
            .{ "easeInQuint", easeInQuint },
            .{ "easeOutQuint", easeOutQuint },
            .{ "easeInOutQuint", easeInOutQuint },
            .{ "easeInExpo", easeInExpo },
            .{ "easeOutExpo", easeOutExpo },
            .{ "easeInOutExpo", easeInOutExpo },
            .{ "easeInCirc", easeInCirc },
            .{ "easeOutCirc", easeOutCirc },
            .{ "easeInOutCirc", easeInOutCirc },
            .{ "easeInElastic", easeInElastic },
            .{ "easeOutElastic", easeOutElastic },
            .{ "easeInOutElastic", easeInOutElastic },
            .{ "easeInBack", easeInBack },
            .{ "easeOutBack", easeOutBack },
            .{ "easeInOutBack", easeInOutBack },
            .{ "easeInBounce", easeInBounce },
            .{ "easeOutBounce", easeOutBounce },
            .{ "easeInOutBounce", easeInOutBounce },
        });
        return map.get(name);
    }
};

// Tests
test "Easing functions boundary values" {
    const testing = @import("std").testing;

    // All easing functions should return 0 at t=0 and 1 at t=1
    const functions = [_]*const fn (f32) f32{
        Easing.linear,
        Easing.easeInQuad,
        Easing.easeOutQuad,
        Easing.easeInOutQuad,
        Easing.easeInCubic,
        Easing.easeOutCubic,
        Easing.easeInOutCubic,
        Easing.easeInCirc,
        Easing.easeOutCirc,
        Easing.easeInOutCirc,
    };

    for (functions) |func| {
        try testing.expectApproxEqAbs(func(0.0), 0.0, 0.0001);
        try testing.expectApproxEqAbs(func(1.0), 1.0, 0.0001);
    }
}

test "Spring physics" {
    const testing = @import("std").testing;

    const spring = Easing.Spring{
        .stiffness = 100.0,
        .damping = 10.0,
        .mass = 1.0,
    };

    // Spring should start at 0 and approach 1
    try testing.expectApproxEqAbs(spring.calculate(0.0), 0.0, 0.0001);
    try testing.expect(spring.calculate(1.0) > 0.5);
}
