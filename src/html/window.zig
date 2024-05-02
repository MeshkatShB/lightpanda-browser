const std = @import("std");

const parser = @import("../netsurf.zig");

const EventTarget = @import("../dom/event_target.zig").EventTarget;

const storage = @import("../storage/storage.zig");

// https://dom.spec.whatwg.org/#interface-window-extensions
// https://html.spec.whatwg.org/multipage/nav-history-apis.html#window
pub const Window = struct {
    pub const prototype = *EventTarget;
    pub const mem_guarantied = true;
    pub const global_type = true;

    // Extend libdom event target for pure zig struct.
    base: parser.EventTargetTBase = parser.EventTargetTBase{},

    document: ?*parser.DocumentHTML = null,
    target: []const u8,

    storageShelf: ?*storage.Shelf = null,

    pub fn create(target: ?[]const u8) Window {
        return Window{
            .target = target orelse "",
        };
    }

    pub fn replaceDocument(self: *Window, doc: *parser.DocumentHTML) void {
        self.document = doc;
    }

    pub fn setStorageShelf(self: *Window, shelf: *storage.Shelf) void {
        self.storageShelf = shelf;
    }

    pub fn get_window(self: *Window) *Window {
        return self;
    }

    pub fn get_self(self: *Window) *Window {
        return self;
    }

    pub fn get_parent(self: *Window) *Window {
        return self;
    }

    pub fn get_document(self: *Window) ?*parser.DocumentHTML {
        return self.document;
    }

    pub fn get_name(self: *Window) []const u8 {
        return self.target;
    }

    pub fn get_localStorage(self: *Window) !*storage.Bottle {
        if (self.storageShelf == null) return parser.DOMError.NotSupported;
        return &self.storageShelf.?.bucket.local;
    }

    pub fn get_sessionStorage(self: *Window) !*storage.Bottle {
        if (self.storageShelf == null) return parser.DOMError.NotSupported;
        return &self.storageShelf.?.bucket.session;
    }
};
