const std = @import("std");

const parser = @import("../netsurf.zig");

const jsruntime = @import("jsruntime");
const Case = jsruntime.test_utils.Case;
const checkCases = jsruntime.test_utils.checkCases;
const generate = @import("../generate.zig");

const utils = @import("utils.z");
const Element = @import("element.zig").Element;
const Union = @import("element.zig").Union;

const Matcher = union(enum) {
    matchByTagName: MatchByTagName,
    matchByClassName: MatchByClassName,
    matchTrue: struct {},

    pub fn match(self: Matcher, node: *parser.Node) !bool {
        switch (self) {
            inline .matchTrue => return true,
            inline else => |case| return case.match(node),
        }
    }

    pub fn deinit(self: Matcher, alloc: std.mem.Allocator) void {
        switch (self) {
            .matchTrue => return,
            inline else => |case| return case.deinit(alloc),
        }
    }
};

pub const MatchByTagName = struct {
    // tag is used to select node against their name.
    // tag comparison is case insensitive.
    tag: []const u8,
    is_wildcard: bool,

    fn init(alloc: std.mem.Allocator, tag_name: []const u8) !MatchByTagName {
        const tag_name_alloc = try alloc.alloc(u8, tag_name.len);
        @memcpy(tag_name_alloc, tag_name);
        return MatchByTagName{
            .tag = tag_name_alloc,
            .is_wildcard = std.mem.eql(u8, tag_name, "*"),
        };
    }

    pub fn match(self: MatchByTagName, node: *parser.Node) !bool {
        return self.is_wildcard or std.ascii.eqlIgnoreCase(self.tag, try parser.nodeName(node));
    }

    fn deinit(self: MatchByTagName, alloc: std.mem.Allocator) void {
        alloc.free(self.tag);
    }
};

pub fn HTMLCollectionByTagName(
    alloc: std.mem.Allocator,
    root: *parser.Node,
    tag_name: []const u8,
    include_root: bool,
) !HTMLCollection {
    return HTMLCollection{
        .root = root,
        .walker = Walker{ .walkerDepthFirst = .{} },
        .matcher = Matcher{
            .matchByTagName = try MatchByTagName.init(alloc, tag_name),
        },
        .include_root = include_root,
    };
}

pub const MatchByClassName = struct {
    classNames: []const u8,

    fn init(alloc: std.mem.Allocator, classNames: []const u8) !MatchByClassName {
        const class_names_alloc = try alloc.alloc(u8, classNames.len);
        @memcpy(class_names_alloc, classNames);
        return MatchByClassName{
            .classNames = class_names_alloc,
        };
    }

    pub fn match(self: MatchByClassName, node: *parser.Node) !bool {
        var it = std.mem.splitAny(u8, self.classNames, " ");
        const e = parser.nodeToElement(node);
        while (it.next()) |c| {
            if (!try parser.elementHasClass(e, c)) {
                return false;
            }
        }

        return true;
    }

    fn deinit(self: MatchByClassName, alloc: std.mem.Allocator) void {
        alloc.free(self.classNames);
    }
};

pub fn HTMLCollectionByClassName(
    alloc: std.mem.Allocator,
    root: *parser.Node,
    classNames: []const u8,
    include_root: bool,
) !HTMLCollection {
    return HTMLCollection{
        .root = root,
        .walker = Walker{ .walkerDepthFirst = .{} },
        .matcher = Matcher{
            .matchByClassName = try MatchByClassName.init(alloc, classNames),
        },
        .include_root = include_root,
    };
}

const Walker = union(enum) {
    walkerDepthFirst: WalkerDepthFirst,

    pub fn get_next(self: Walker, root: *parser.Node, cur: ?*parser.Node) !?*parser.Node {
        switch (self) {
            inline else => |case| return case.get_next(root, cur),
        }
    }
};

// WalkerDepthFirst iterates over the DOM tree to return the next following
// node or null at the end.
//
// This implementation is a zig version of Netsurf code.
// http://source.netsurf-browser.org/libdom.git/tree/src/html/html_collection.c#n177
//
// The iteration is a depth first as required by the specification.
// https://dom.spec.whatwg.org/#htmlcollection
// https://dom.spec.whatwg.org/#concept-tree-order
pub const WalkerDepthFirst = struct {
    pub fn get_next(_: WalkerDepthFirst, root: *parser.Node, cur: ?*parser.Node) !?*parser.Node {
        var n = cur orelse root;

        // TODO deinit next
        if (try parser.nodeFirstChild(n)) |next| {
            return next;
        }

        // TODO deinit next
        if (try parser.nodeNextSibling(n)) |next| {
            return next;
        }

        // TODO deinit parent
        // Back to the parent of cur.
        // If cur has no parent, then the iteration is over.
        var parent = try parser.nodeParentNode(n) orelse return null;

        // TODO deinit lastchild
        var lastchild = try parser.nodeLastChild(parent);
        while (n != root and n == lastchild) {
            n = parent;

            // TODO deinit parent
            // Back to the prev's parent.
            // If prev has no parent, then the loop must stop.
            parent = try parser.nodeParentNode(n) orelse break;

            // TODO deinit lastchild
            lastchild = try parser.nodeLastChild(parent);
        }

        if (n == root) {
            return null;
        }

        return try parser.nodeNextSibling(n);
    }
};

// WEB IDL https://dom.spec.whatwg.org/#htmlcollection
// HTMLCollection is re implemented in zig here because libdom
// dom_html_collection expects a comparison function callback as arguement.
// But we wanted a dynamically comparison here, according to the match tagname.
pub const HTMLCollection = struct {
    pub const mem_guarantied = true;

    matcher: Matcher,
    walker: Walker,

    root: *parser.Node,

    // By default the HTMLCollection walk on the root's descendant only.
    // But on somes cases, like for dom document, we want to walk over the root
    // itself.
    include_root: bool = false,

    // save a state for the collection to improve the _item speed.
    cur_idx: ?u32 = undefined,
    cur_node: ?*parser.Node = undefined,

    // start returns the first node to walk on.
    fn start(self: HTMLCollection) !?*parser.Node {
        if (self.include_root) {
            return self.root;
        }

        return try self.walker.get_next(self.root, null);
    }

    /// get_length computes the collection's length dynamically according to
    /// the current root structure.
    // TODO: nodes retrieved must be de-referenced.
    pub fn get_length(self: *HTMLCollection) !u32 {
        var len: u32 = 0;
        var node = try self.start() orelse return 0;

        while (true) {
            if (try parser.nodeType(node) == .element) {
                if (try self.matcher.match(node)) {
                    len += 1;
                }
            }

            node = try self.walker.get_next(self.root, node) orelse break;
        }

        return len;
    }

    pub fn _item(self: *HTMLCollection, index: u32) !?Union {
        var i: u32 = 0;
        var node: *parser.Node = undefined;

        // Use the current state to improve speed if possible.
        if (self.cur_idx != null and index >= self.cur_idx.?) {
            i = self.cur_idx.?;
            node = self.cur_node.?;
        } else {
            node = try self.start() orelse return null;
        }

        while (true) {
            if (try parser.nodeType(node) == .element) {
                if (try self.matcher.match(node)) {
                    // check if we found the searched element.
                    if (i == index) {
                        // save the current state
                        self.cur_node = node;
                        self.cur_idx = i;

                        const e = @as(*parser.Element, @ptrCast(node));
                        return try Element.toInterface(e);
                    }

                    i += 1;
                }
            }

            node = try self.walker.get_next(self.root, node) orelse break;
        }

        return null;
    }

    pub fn _namedItem(self: *HTMLCollection, name: []const u8) !?Union {
        if (name.len == 0) {
            return null;
        }

        var node = try self.start() orelse return null;

        while (true) {
            if (try parser.nodeType(node) == .element) {
                if (try self.matcher.match(node)) {
                    const elem = @as(*parser.Element, @ptrCast(node));

                    var attr = try parser.elementGetAttribute(elem, "id");
                    // check if the node id corresponds to the name argument.
                    if (attr != null and std.mem.eql(u8, name, attr.?)) {
                        return try Element.toInterface(elem);
                    }

                    attr = try parser.elementGetAttribute(elem, "name");
                    // check if the node id corresponds to the name argument.
                    if (attr != null and std.mem.eql(u8, name, attr.?)) {
                        return try Element.toInterface(elem);
                    }
                }
            }

            node = try self.walker.get_next(self.root, node) orelse break;
        }

        return null;
    }

    pub fn deinit(self: *HTMLCollection, alloc: std.mem.Allocator) void {
        self.matcher.deinit(alloc);
    }
};

// Tests
// -----

pub fn testExecFn(
    _: std.mem.Allocator,
    js_env: *jsruntime.Env,
    comptime _: []jsruntime.API,
) !void {
    var getElementsByTagName = [_]Case{
        .{ .src = "let getElementsByTagName = document.getElementsByTagName('p')", .ex = "undefined" },
        .{ .src = "getElementsByTagName.length", .ex = "2" },
        .{ .src = "let getElementsByTagNameCI = document.getElementsByTagName('P')", .ex = "undefined" },
        .{ .src = "getElementsByTagNameCI.length", .ex = "2" },
        .{ .src = "getElementsByTagName.item(0).localName", .ex = "p" },
        .{ .src = "getElementsByTagName.item(1).localName", .ex = "p" },
        .{ .src = "let getElementsByTagNameAll = document.getElementsByTagName('*')", .ex = "undefined" },
        .{ .src = "getElementsByTagNameAll.length", .ex = "8" },
        .{ .src = "getElementsByTagNameAll.item(0).localName", .ex = "html" },
        .{ .src = "getElementsByTagNameAll.item(0).localName", .ex = "html" },
        .{ .src = "getElementsByTagNameAll.item(1).localName", .ex = "head" },
        .{ .src = "getElementsByTagNameAll.item(0).localName", .ex = "html" },
        .{ .src = "getElementsByTagNameAll.item(2).localName", .ex = "body" },
        .{ .src = "getElementsByTagNameAll.item(3).localName", .ex = "div" },
        .{ .src = "getElementsByTagNameAll.item(7).localName", .ex = "p" },
        .{ .src = "getElementsByTagNameAll.namedItem('para-empty-child').localName", .ex = "span" },

        // check liveness
        .{ .src = "let content = document.getElementById('content')", .ex = "undefined" },
        .{ .src = "let pe = document.getElementById('para-empty')", .ex = "undefined" },
        .{ .src = "let p = document.createElement('p')", .ex = "undefined" },
        .{ .src = "p.textContent = 'OK live'", .ex = "OK live" },
        .{ .src = "getElementsByTagName.item(1).textContent", .ex = " And" },
        .{ .src = "content.appendChild(p) != undefined", .ex = "true" },
        .{ .src = "getElementsByTagName.length", .ex = "3" },
        .{ .src = "getElementsByTagName.item(2).textContent", .ex = "OK live" },
        .{ .src = "content.insertBefore(p, pe) != undefined", .ex = "true" },
        .{ .src = "getElementsByTagName.item(0).textContent", .ex = "OK live" },
    };
    try checkCases(js_env, &getElementsByTagName);
}
