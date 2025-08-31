//! Layout caching system for performance optimization
//!
//! This module provides a caching layer for the TUI layout engine to avoid
//! redundant layout calculations when the same layout parameters are used repeatedly.
//!
//! ## Features
//!
//! - **Cache Key**: Based on container bounds, direction, padding, gap, alignment, and children specifications
//! - **LRU Eviction**: Prevents unbounded memory growth with configurable capacity
//! - **Statistics**: Tracks cache hits/misses for performance monitoring
//! - **Invalidation**: Methods to clear specific entries or entire cache
//! - **Memory Management**: Proper cleanup and allocator usage following Zig 0.15.1 patterns

const std = @import("std");
const Bounds = @import("bounds.zig").Bounds;
const layout = @import("layout.zig");

/// Cache key representing the input parameters for a layout calculation
pub const CacheKey = struct {
    bounds: Bounds,
    direction: layout.Direction,
    padding: u32,
    gap: u32,
    alignment: layout.Alignment,
    children_hash: u64, // Hash of children sizes and constraints

    /// Compute hash for the cache key
    pub fn hash(self: CacheKey) u64 {
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, self.bounds);
        std.hash.autoHash(&hasher, self.direction);
        std.hash.autoHash(&hasher, self.padding);
        std.hash.autoHash(&hasher, self.gap);
        std.hash.autoHash(&hasher, self.alignment);
        std.hash.autoHash(&hasher, self.children_hash);
        return hasher.final();
    }

    /// Check equality between two cache keys
    pub fn eql(self: CacheKey, other: CacheKey) bool {
        return std.meta.eql(self, other);
    }
};

/// Cache entry containing computed layout results
pub const CacheEntry = struct {
    computed_bounds: []Bounds,

    /// Deinitialize the cache entry
    pub fn deinit(self: *CacheEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.computed_bounds);
    }
};

/// LRU cache node for maintaining eviction order
const LruNode = struct {
    key_hash: u64,
    prev: ?*LruNode,
    next: ?*LruNode,
};

/// Layout cache with LRU eviction policy
pub const LayoutCache = struct {
    allocator: std.mem.Allocator,
    map: std.HashMap(u64, CacheEntry, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage),
    lru_head: ?*LruNode,
    lru_tail: ?*LruNode,
    capacity: usize,
    stats: CacheStats,

    /// Cache statistics for monitoring performance
    pub const CacheStats = struct {
        hits: u64 = 0,
        misses: u64 = 0,
        evictions: u64 = 0,

        /// Get cache hit rate as a percentage
        pub fn hitRate(self: CacheStats) f32 {
            const total = self.hits + self.misses;
            if (total == 0) return 0.0;
            return @as(f32, @floatFromInt(self.hits)) / @as(f32, @floatFromInt(total)) * 100.0;
        }

        /// Reset statistics
        pub fn reset(self: *CacheStats) void {
            self.hits = 0;
            self.misses = 0;
            self.evictions = 0;
        }
    };

    /// Initialize a new layout cache
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !LayoutCache {
        return LayoutCache{
            .allocator = allocator,
            .map = std.HashMap(u64, CacheEntry, std.hash_map.AutoContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .lru_head = null,
            .lru_tail = null,
            .capacity = capacity,
            .stats = CacheStats{},
        };
    }

    /// Deinitialize the cache and free all resources
    pub fn deinit(self: *LayoutCache) void {
        // Free all cache entries
        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.map.deinit();

        // Free LRU nodes
        var node = self.lru_head;
        while (node) |n| {
            const next = n.next;
            self.allocator.destroy(n);
            node = next;
        }
    }

    /// Get cached layout results if available
    pub fn get(self: *LayoutCache, key: CacheKey) ?[]const Bounds {
        const key_hash = key.hash();
        if (self.map.getPtr(key_hash)) |entry| {
            // Move to front of LRU list
            self.moveToFront(key_hash);
            self.stats.hits += 1;
            return entry.computed_bounds;
        }
        self.stats.misses += 1;
        return null;
    }

    /// Store layout results in cache
    pub fn put(self: *LayoutCache, key: CacheKey, computed_bounds: []const Bounds) !void {
        const key_hash = key.hash();

        // Check if key already exists
        if (self.map.getPtr(key_hash)) |_| {
            // Update existing entry
            self.moveToFront(key_hash);
            return;
        }

        // Evict if at capacity
        if (self.map.count() >= self.capacity) {
            try self.evictLeastRecentlyUsed();
        }

        // Create new LRU node
        const node = try self.allocator.create(LruNode);
        node.* = LruNode{
            .key_hash = key_hash,
            .prev = null,
            .next = self.lru_head,
        };

        if (self.lru_head) |head| {
            head.prev = node;
        } else {
            self.lru_tail = node;
        }
        self.lru_head = node;

        // Store in map
        const bounds_copy = try self.allocator.dupe(Bounds, computed_bounds);
        try self.map.put(key_hash, CacheEntry{
            .computed_bounds = bounds_copy,
        });
    }

    /// Invalidate a specific cache entry
    pub fn invalidate(self: *LayoutCache, key: CacheKey) void {
        const key_hash = key.hash();
        if (self.map.fetchRemove(key_hash)) |kv| {
            kv.value.deinit(self.allocator);
            self.removeFromLru(key_hash);
        }
    }

    /// Clear all cache entries
    pub fn clear(self: *LayoutCache) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.map.clearRetainingCapacity();

        // Free LRU nodes
        var node = self.lru_head;
        while (node) |n| {
            const next = n.next;
            self.allocator.destroy(n);
            node = next;
        }
        self.lru_head = null;
        self.lru_tail = null;
    }

    /// Get current cache statistics
    pub fn getStats(self: LayoutCache) CacheStats {
        return self.stats;
    }

    /// Compute hash for children specifications
    pub fn hashChildren(children: []const layout.Layout.LayoutItem) u64 {
        var hasher = std.hash.Wyhash.init(0);
        for (children) |child| {
            std.hash.autoHash(&hasher, child.size);
            std.hash.autoHash(&hasher, child.min_width);
            std.hash.autoHash(&hasher, child.min_height);
            std.hash.autoHash(&hasher, child.max_width);
            std.hash.autoHash(&hasher, child.max_height);
        }
        return hasher.final();
    }

    /// Move a key to the front of the LRU list
    fn moveToFront(self: *LayoutCache, key_hash: u64) void {
        // Find the node
        var node = self.lru_head;
        while (node) |n| {
            if (n.key_hash == key_hash) {
                // Remove from current position
                if (n.prev) |prev| {
                    prev.next = n.next;
                } else {
                    self.lru_head = n.next;
                }
                if (n.next) |next| {
                    next.prev = n.prev;
                } else {
                    self.lru_tail = n.prev;
                }

                // Move to front
                n.prev = null;
                n.next = self.lru_head;
                if (self.lru_head) |head| {
                    head.prev = n;
                } else {
                    self.lru_tail = n;
                }
                self.lru_head = n;
                return;
            }
            node = n.next;
        }
    }

    /// Remove a key from the LRU list
    fn removeFromLru(self: *LayoutCache, key_hash: u64) void {
        var node = self.lru_head;
        while (node) |n| {
            if (n.key_hash == key_hash) {
                if (n.prev) |prev| {
                    prev.next = n.next;
                } else {
                    self.lru_head = n.next;
                }
                if (n.next) |next| {
                    next.prev = n.prev;
                } else {
                    self.lru_tail = n.prev;
                }
                self.allocator.destroy(n);
                return;
            }
            node = n.next;
        }
    }

    /// Evict the least recently used entry
    fn evictLeastRecentlyUsed(self: *LayoutCache) !void {
        if (self.lru_tail) |tail| {
            const key_hash = tail.key_hash;
            if (self.map.fetchRemove(key_hash)) |kv| {
                kv.value.deinit(self.allocator);
                self.stats.evictions += 1;
            }
            self.removeFromLru(key_hash);
        }
    }
};

// Tests for the layout cache
test "cache basic operations" {
    var cache = try LayoutCache.init(std.testing.allocator, 10);
    defer cache.deinit();

    const key = CacheKey{
        .bounds = Bounds.init(0, 0, 100, 50),
        .direction = .row,
        .padding = 5,
        .gap = 2,
        .alignment = .start,
        .children_hash = 12345,
    };

    const bounds = [_]Bounds{
        Bounds.init(5, 5, 20, 40),
        Bounds.init(27, 5, 30, 40),
    };

    // Test miss
    try std.testing.expect(cache.get(key) == null);
    try std.testing.expect(cache.stats.misses == 1);

    // Store in cache
    try cache.put(key, &bounds);

    // Test hit
    if (cache.get(key)) |cached_bounds| {
        try std.testing.expectEqual(bounds.len, cached_bounds.len);
        for (bounds, 0..) |b, i| {
            try std.testing.expectEqual(b, cached_bounds[i]);
        }
    }
    try std.testing.expect(cache.stats.hits == 1);
}

test "cache eviction" {
    var cache = try LayoutCache.init(std.testing.allocator, 2);
    defer cache.deinit();

    const key1 = CacheKey{
        .bounds = Bounds.init(0, 0, 100, 50),
        .direction = .row,
        .padding = 5,
        .gap = 2,
        .alignment = .start,
        .children_hash = 1,
    };

    const key2 = CacheKey{
        .bounds = Bounds.init(0, 0, 100, 50),
        .direction = .row,
        .padding = 5,
        .gap = 2,
        .alignment = .start,
        .children_hash = 2,
    };

    const key3 = CacheKey{
        .bounds = Bounds.init(0, 0, 100, 50),
        .direction = .row,
        .padding = 5,
        .gap = 2,
        .alignment = .start,
        .children_hash = 3,
    };

    const bounds = [_]Bounds{Bounds.init(0, 0, 10, 10)};

    try cache.put(key1, &bounds);
    try cache.put(key2, &bounds);
    try cache.put(key3, &bounds); // Should evict key1

    try std.testing.expect(cache.get(key1) == null); // Evicted
    try std.testing.expect(cache.get(key2) != null);
    try std.testing.expect(cache.get(key3) != null);
    try std.testing.expect(cache.stats.evictions == 1);
}

test "cache invalidation" {
    var cache = try LayoutCache.init(std.testing.allocator, 10);
    defer cache.deinit();

    const key = CacheKey{
        .bounds = Bounds.init(0, 0, 100, 50),
        .direction = .row,
        .padding = 5,
        .gap = 2,
        .alignment = .start,
        .children_hash = 12345,
    };

    const bounds = [_]Bounds{Bounds.init(0, 0, 10, 10)};

    try cache.put(key, &bounds);
    try std.testing.expect(cache.get(key) != null);

    cache.invalidate(key);
    try std.testing.expect(cache.get(key) == null);
}

test "cache statistics" {
    var cache = try LayoutCache.init(std.testing.allocator, 10);
    defer cache.deinit();

    const key = CacheKey{
        .bounds = Bounds.init(0, 0, 100, 50),
        .direction = .row,
        .padding = 5,
        .gap = 2,
        .alignment = .start,
        .children_hash = 12345,
    };

    _ = [_]Bounds{Bounds.init(0, 0, 10, 10)}; // Test bounds creation

    // Miss
    _ = cache.get(key);
    // Hit
    _ = cache.get(key);

    const stats = cache.getStats();
    try std.testing.expectEqual(stats.hits, 1);
    try std.testing.expectEqual(stats.misses, 1);
    try std.testing.expectEqual(stats.hitRate(), 50.0);
}
