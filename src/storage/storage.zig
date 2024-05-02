const std = @import("std");

const jsruntime = @import("jsruntime");
const Case = jsruntime.test_utils.Case;
const checkCases = jsruntime.test_utils.checkCases;
const generate = @import("../generate.zig");

const DOMError = @import("../netsurf.zig").DOMError;

const log = std.log.scoped(.storage);

pub const Interfaces = generate.Tuple(.{
    Bottle,
});

// See https://storage.spec.whatwg.org/#model for storage hierarchy.
// A Shed contains map of Shelves. The key is the document's origin.
// A Shelf contains on default Bucket (it could contain many in the future).
// A Bucket contains a local and a session Bottle.
// A Bottle stores a map of strings and is exposed to the JS.

pub const Shed = struct {
    const Map = std.StringHashMapUnmanaged(Shelf);

    alloc: std.mem.Allocator,
    map: Map,

    pub fn init(alloc: std.mem.Allocator) Shed {
        return .{
            .alloc = alloc,
            .map = .{},
        };
    }

    pub fn deinit(self: *Shed) void {
        // loop hover each KV and free the memory.
        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
            self.alloc.free(entry.key_ptr.*);
        }
        self.map.deinit(self.alloc);
    }

    pub fn getOrPut(self: *Shed, origin: []const u8) !*Shelf {
        const shelf = self.map.getPtr(origin);
        if (shelf) |s| return s;

        const oorigin = try self.alloc.dupe(u8, origin);
        try self.map.put(self.alloc, oorigin, Shelf.init(self.alloc));
        return self.map.getPtr(origin).?;
    }
};

pub const Shelf = struct {
    bucket: Bucket,

    pub fn init(alloc: std.mem.Allocator) Shelf {
        return .{ .bucket = Bucket.init(alloc) };
    }

    pub fn deinit(self: *Shelf) void {
        self.bucket.deinit();
    }
};

pub const Bucket = struct {
    local: Bottle,
    session: Bottle,

    pub fn init(alloc: std.mem.Allocator) Bucket {
        return .{
            .local = Bottle.init(alloc),
            .session = Bottle.init(alloc),
        };
    }

    pub fn deinit(self: *Bucket) void {
        self.local.deinit();
        self.session.deinit();
    }
};

// https://html.spec.whatwg.org/multipage/webstorage.html#the-storage-interface
pub const Bottle = struct {
    pub const mem_guarantied = true;
    const Map = std.StringHashMapUnmanaged([]const u8);

    // allocator is stored. we don't use the JS env allocator b/c the storage
    // data could exists longer than a js env lifetime.
    alloc: std.mem.Allocator,
    map: Map,

    pub fn init(alloc: std.mem.Allocator) Bottle {
        return .{
            .alloc = alloc,
            .map = .{},
        };
    }

    // loop hover each KV and free the memory.
    fn free(self: *Bottle) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
            self.alloc.free(entry.value_ptr.*);
        }
    }

    pub fn deinit(self: *Bottle) void {
        self.free();
        self.map.deinit(self.alloc);
    }

    pub fn get_length(self: *Bottle) u32 {
        return @intCast(self.map.count());
    }

    pub fn _key(self: *Bottle, idx: u32) ?[]const u8 {
        if (idx >= self.map.count()) return null;

        var it = self.map.valueIterator();
        var i: u32 = 0;
        while (it.next()) |v| {
            if (i == idx) return v.*;
            i += 1;
        }
        unreachable;
    }

    pub fn _getItem(self: *Bottle, k: []const u8) ?[]const u8 {
        return self.map.get(k);
    }

    pub fn _setItem(self: *Bottle, k: []const u8, v: []const u8) !void {
        const old = self.map.get(k);
        if (old != null and std.mem.eql(u8, v, old.?)) return;

        // owns k and v by copying them.
        const kk = try self.alloc.dupe(u8, k);
        errdefer self.alloc.free(kk);
        const vv = try self.alloc.dupe(u8, v);
        errdefer self.alloc.free(vv);

        self.map.put(self.alloc, kk, vv) catch |e| {
            log.debug("set item: {any}", .{e});
            return DOMError.QuotaExceeded;
        };

        // > Broadcast this with key, oldValue, and value.
        // https://html.spec.whatwg.org/multipage/webstorage.html#the-storageevent-interface
        //
        // > The storage event of the Window interface fires when a storage
        // > area (localStorage or sessionStorage) has been modified in the
        // > context of another document.
        // https://developer.mozilla.org/en-US/docs/Web/API/Window/storage_event
        //
        // So for now, we won't impement the feature.
    }

    pub fn _removeItem(self: *Bottle, k: []const u8) !void {
        const old = self.map.fetchRemove(k);
        if (old == null) return;

        // > Broadcast this with key, oldValue, and null.
        // https://html.spec.whatwg.org/multipage/webstorage.html#the-storageevent-interface
        //
        // > The storage event of the Window interface fires when a storage
        // > area (localStorage or sessionStorage) has been modified in the
        // > context of another document.
        // https://developer.mozilla.org/en-US/docs/Web/API/Window/storage_event
        //
        // So for now, we won't impement the feature.
    }

    pub fn _clear(self: *Bottle) void {
        self.free();
        self.map.clearRetainingCapacity();

        // > Broadcast this with null, null, and null.
        // https://html.spec.whatwg.org/multipage/webstorage.html#the-storageevent-interface
        //
        // > The storage event of the Window interface fires when a storage
        // > area (localStorage or sessionStorage) has been modified in the
        // > context of another document.
        // https://developer.mozilla.org/en-US/docs/Web/API/Window/storage_event
        //
        // So for now, we won't impement the feature.
    }
};

// Tests
// -----

pub fn testExecFn(
    _: std.mem.Allocator,
    js_env: *jsruntime.Env,
) anyerror!void {
    var storage = [_]Case{
        .{ .src = "localStorage.length", .ex = "0" },

        .{ .src = "localStorage.setItem('foo', 'bar')", .ex = "undefined" },
        .{ .src = "localStorage.length", .ex = "1" },
        .{ .src = "localStorage.getItem('foo')", .ex = "bar" },
        .{ .src = "localStorage.removeItem('foo')", .ex = "undefined" },
        .{ .src = "localStorage.length", .ex = "0" },

        // .{ .src = "localStorage['foo'] = 'bar'", .ex = "undefined" },
        // .{ .src = "localStorage['foo']", .ex = "bar" },
        // .{ .src = "localStorage.length", .ex = "1" },

        .{ .src = "localStorage.clear()", .ex = "undefined" },
        .{ .src = "localStorage.length", .ex = "0" },
    };
    try checkCases(js_env, &storage);
}

test "storage bottle" {
    var bottle = Bottle.init(std.testing.allocator);
    defer bottle.deinit();

    try std.testing.expect(0 == bottle.get_length());
    try std.testing.expect(null == bottle._getItem("foo"));

    try bottle._setItem("foo", "bar");
    try std.testing.expect(std.mem.eql(u8, "bar", bottle._getItem("foo").?));

    try bottle._removeItem("foo");

    try std.testing.expect(0 == bottle.get_length());
    try std.testing.expect(null == bottle._getItem("foo"));
}
