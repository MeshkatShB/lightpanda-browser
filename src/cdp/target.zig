// Copyright (C) 2023-2024  Lightpanda (Selecy SAS)
//
// Francis Bouvier <francis@lightpanda.io>
// Pierre Tachoire <pierre@lightpanda.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");

const server = @import("../server.zig");
const Ctx = server.Ctx;
const cdp = @import("cdp.zig");
const result = cdp.result;
const stringify = cdp.stringify;
const IncomingMessage = @import("msg.zig").IncomingMessage;
const Input = @import("msg.zig").Input;

const log = std.log.scoped(.cdp);

const Methods = enum {
    setDiscoverTargets,
    setAutoAttach,
    attachToTarget,
    getTargetInfo,
    getBrowserContexts,
    createBrowserContext,
    disposeBrowserContext,
    createTarget,
    closeTarget,
    sendMessageToTarget,
    detachFromTarget,
};

pub fn target(
    alloc: std.mem.Allocator,
    msg: *IncomingMessage,
    action: []const u8,
    ctx: *Ctx,
) ![]const u8 {
    const method = std.meta.stringToEnum(Methods, action) orelse
        return error.UnknownMethod;
    return switch (method) {
        .setDiscoverTargets => setDiscoverTargets(alloc, msg, ctx),
        .setAutoAttach => setAutoAttach(alloc, msg, ctx),
        .attachToTarget => attachToTarget(alloc, msg, ctx),
        .getTargetInfo => getTargetInfo(alloc, msg, ctx),
        .getBrowserContexts => getBrowserContexts(alloc, msg, ctx),
        .createBrowserContext => createBrowserContext(alloc, msg, ctx),
        .disposeBrowserContext => disposeBrowserContext(alloc, msg, ctx),
        .createTarget => createTarget(alloc, msg, ctx),
        .closeTarget => closeTarget(alloc, msg, ctx),
        .sendMessageToTarget => sendMessageToTarget(alloc, msg, ctx),
        .detachFromTarget => detachFromTarget(alloc, msg, ctx),
    };
}

// TODO: hard coded IDs
pub const PageTargetID = "PAGETARGETIDB638E9DC0F52DDC";
pub const BrowserTargetID = "browser9-targ-et6f-id0e-83f3ab73a30c";
pub const BrowserContextID = "BROWSERCONTEXTIDA95049E9DFE95EA9";

// TODO: noop method
fn setDiscoverTargets(
    alloc: std.mem.Allocator,
    msg: *IncomingMessage,
    _: *Ctx,
) ![]const u8 {
    // input
    const input = try Input(void).get(alloc, msg);
    defer input.deinit();
    log.debug("Req > id {d}, method {s}", .{ input.id, "target.setDiscoverTargets" });

    // output
    return result(alloc, input.id, null, null, input.sessionId);
}

const AttachToTarget = struct {
    sessionId: []const u8,
    targetInfo: struct {
        targetId: []const u8,
        type: []const u8 = "page",
        title: []const u8,
        url: []const u8,
        attached: bool = true,
        canAccessOpener: bool = false,
        browserContextId: []const u8,
    },
    waitingForDebugger: bool = false,
};

const TargetCreated = struct {
    sessionId: []const u8,
    targetInfo: struct {
        targetId: []const u8,
        type: []const u8 = "page",
        title: []const u8,
        url: []const u8,
        attached: bool = true,
        canAccessOpener: bool = false,
        browserContextId: []const u8,
    },
};

const TargetFilter = struct {
    type: ?[]const u8 = null,
    exclude: ?bool = null,
};

// TODO: noop method
fn setAutoAttach(
    alloc: std.mem.Allocator,
    msg: *IncomingMessage,
    ctx: *Ctx,
) ![]const u8 {
    // input
    const Params = struct {
        autoAttach: bool,
        waitForDebuggerOnStart: bool,
        flatten: bool = true,
        filter: ?[]TargetFilter = null,
    };
    const input = try Input(Params).get(alloc, msg);
    defer input.deinit();
    log.debug("Req > id {d}, method {s}", .{ input.id, "target.setAutoAttach" });

    // attachedToTarget event
    if (input.sessionId == null) {
        const attached = AttachToTarget{
            .sessionId = cdp.BrowserSessionID,
            .targetInfo = .{
                .targetId = PageTargetID,
                .title = "about:blank",
                .url = cdp.URLBase,
                .browserContextId = BrowserContextID,
            },
        };
        try cdp.sendEvent(alloc, ctx, "Target.attachedToTarget", AttachToTarget, attached, null);
    }

    // output
    return result(alloc, input.id, null, null, input.sessionId);
}

// TODO: noop method
fn attachToTarget(
    alloc: std.mem.Allocator,
    msg: *IncomingMessage,
    ctx: *Ctx,
) ![]const u8 {

    // input
    const Params = struct {
        targetId: []const u8,
        flatten: bool = true,
    };
    const input = try Input(Params).get(alloc, msg);
    defer input.deinit();
    log.debug("Req > id {d}, method {s}", .{ input.id, "target.attachToTarget" });

    // attachedToTarget event
    if (input.sessionId == null) {
        const attached = AttachToTarget{
            .sessionId = cdp.BrowserSessionID,
            .targetInfo = .{
                .targetId = input.params.targetId,
                .title = "about:blank",
                .url = cdp.URLBase,
                .browserContextId = BrowserContextID,
            },
        };
        try cdp.sendEvent(alloc, ctx, "Target.attachedToTarget", AttachToTarget, attached, null);
    }

    // output
    const SessionId = struct {
        sessionId: []const u8,
    };
    const output = SessionId{
        .sessionId = input.sessionId orelse cdp.BrowserSessionID,
    };
    return result(alloc, input.id, SessionId, output, null);
}

fn getTargetInfo(
    alloc: std.mem.Allocator,
    msg: *IncomingMessage,
    _: *Ctx,
) ![]const u8 {
    // input
    const Params = struct {
        targetId: ?[]const u8 = null,
    };
    const input = try Input(?Params).get(alloc, msg);
    defer input.deinit();
    log.debug("Req > id {d}, method {s}", .{ input.id, "target.getTargetInfo" });

    // output
    const TargetInfo = struct {
        targetId: []const u8,
        type: []const u8,
        title: []const u8 = "",
        url: []const u8 = "",
        attached: bool = true,
        openerId: ?[]const u8 = null,
        canAccessOpener: bool = false,
        openerFrameId: ?[]const u8 = null,
        browserContextId: ?[]const u8 = null,
        subtype: ?[]const u8 = null,
    };
    const targetInfo = TargetInfo{
        .targetId = BrowserTargetID,
        .type = "browser",
    };
    return result(alloc, input.id, TargetInfo, targetInfo, null);
}

// Browser context are not handled and not in the roadmap for now
// The following methods are "fake"

// TODO: noop method
fn getBrowserContexts(
    alloc: std.mem.Allocator,
    msg: *IncomingMessage,
    ctx: *Ctx,
) ![]const u8 {
    // input
    const input = try Input(void).get(alloc, msg);
    defer input.deinit();
    log.debug("Req > id {d}, method {s}", .{ input.id, "target.getBrowserContexts" });

    // ouptut
    const Resp = struct {
        browserContextIds: [][]const u8,
    };
    var resp: Resp = undefined;
    if (ctx.state.contextID) |contextID| {
        var contextIDs = [1][]const u8{contextID};
        resp = .{ .browserContextIds = &contextIDs };
    } else {
        const contextIDs = [0][]const u8{};
        resp = .{ .browserContextIds = &contextIDs };
    }
    return result(alloc, input.id, Resp, resp, null);
}

const ContextID = "CONTEXTIDDCCDD11109E2D4FEFBE4F89";

// TODO: noop method
fn createBrowserContext(
    alloc: std.mem.Allocator,
    msg: *IncomingMessage,
    ctx: *Ctx,
) ![]const u8 {
    // input
    const Params = struct {
        disposeOnDetach: bool = false,
        proxyServer: ?[]const u8 = null,
        proxyBypassList: ?[]const u8 = null,
        originsWithUniversalNetworkAccess: ?[][]const u8 = null,
    };
    const input = try Input(Params).get(alloc, msg);
    defer input.deinit();
    log.debug("Req > id {d}, method {s}", .{ input.id, "target.createBrowserContext" });

    ctx.state.contextID = ContextID;

    // output
    const Resp = struct {
        browserContextId: []const u8 = ContextID,

        pub fn format(
            self: @This(),
            comptime _: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.writeAll("cdp.target.createBrowserContext { ");
            try writer.writeAll(".browserContextId = ");
            try std.fmt.formatText(self.browserContextId, "s", options, writer);
            try writer.writeAll(" }");
        }
    };
    return result(alloc, input.id, Resp, Resp{}, input.sessionId);
}

fn disposeBrowserContext(
    alloc: std.mem.Allocator,
    msg: *IncomingMessage,
    ctx: *Ctx,
) ![]const u8 {
    // input
    const Params = struct {
        browserContextId: []const u8,
    };
    const input = try Input(Params).get(alloc, msg);
    defer input.deinit();
    log.debug("Req > id {d}, method {s}", .{ input.id, "target.disposeBrowserContext" });

    // output
    const res = try result(alloc, input.id, null, .{}, null);
    try ctx.send(res);

    return error.DisposeBrowserContext;
}

// TODO: hard coded IDs
const TargetID = "TARGETID460A8F29706A2ADF14316298";
const LoaderID = "LOADERID42AA389647D702B4D805F49A";

fn createTarget(
    alloc: std.mem.Allocator,
    msg: *IncomingMessage,
    ctx: *Ctx,
) ![]const u8 {
    // input
    const Params = struct {
        url: []const u8,
        width: ?u64 = null,
        height: ?u64 = null,
        browserContextId: ?[]const u8 = null,
        enableBeginFrameControl: bool = false,
        newWindow: bool = false,
        background: bool = false,
        forTab: ?bool = null,
    };
    const input = try Input(Params).get(alloc, msg);
    defer input.deinit();
    log.debug("Req > id {d}, method {s}", .{ input.id, "target.createTarget" });

    // change CDP state
    ctx.state.frameID = TargetID;
    ctx.state.url = "about:blank";
    ctx.state.securityOrigin = "://";
    ctx.state.secureContextType = "InsecureScheme";
    ctx.state.loaderID = LoaderID;

    if (msg.sessionId) |s| {
        ctx.state.sessionID = cdp.SessionID.parse(s) catch |err| {
            log.err("parse sessionID: {s} {any}", .{ s, err });
            return err;
        };
    }

    // TODO stop the previous page instead?
    if (ctx.browser.session.page != null) return error.pageAlreadyExists;

    // create the page
    const p = try ctx.browser.session.createPage();
    ctx.state.executionContextId += 1;
    // start the js env
    const auxData = try std.fmt.allocPrint(
        alloc,
        // NOTE: we assume this is the default web page
        "{{\"isDefault\":true,\"type\":\"default\",\"frameId\":\"{s}\"}}",
        .{ctx.state.frameID},
    );
    defer alloc.free(auxData);
    try p.start(auxData);

    // send targetCreated event
    const created = TargetCreated{
        .sessionId = cdp.ContextSessionID,
        .targetInfo = .{
            .targetId = ctx.state.frameID,
            .title = "about:blank",
            .url = ctx.state.url,
            .browserContextId = input.params.browserContextId orelse ContextID,
            .attached = true,
        },
    };
    try cdp.sendEvent(alloc, ctx, "Target.targetCreated", TargetCreated, created, input.sessionId);

    // send attachToTarget event
    const attached = AttachToTarget{
        .sessionId = cdp.ContextSessionID,
        .targetInfo = .{
            .targetId = ctx.state.frameID,
            .title = "about:blank",
            .url = ctx.state.url,
            .browserContextId = input.params.browserContextId orelse ContextID,
            .attached = true,
        },
        .waitingForDebugger = true,
    };
    try cdp.sendEvent(alloc, ctx, "Target.attachedToTarget", AttachToTarget, attached, input.sessionId);

    // output
    const Resp = struct {
        targetId: []const u8 = TargetID,

        pub fn format(
            self: @This(),
            comptime _: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.writeAll("cdp.target.createTarget { ");
            try writer.writeAll(".targetId = ");
            try std.fmt.formatText(self.targetId, "s", options, writer);
            try writer.writeAll(" }");
        }
    };
    return result(alloc, input.id, Resp, Resp{}, input.sessionId);
}

fn closeTarget(
    alloc: std.mem.Allocator,
    msg: *IncomingMessage,
    ctx: *Ctx,
) ![]const u8 {
    // input
    const Params = struct {
        targetId: []const u8,
    };
    const input = try Input(Params).get(alloc, msg);
    defer input.deinit();
    log.debug("Req > id {d}, method {s}", .{ input.id, "target.closeTarget" });

    // output
    const Resp = struct {
        success: bool = true,
    };
    const res = try result(alloc, input.id, Resp, Resp{}, null);
    try ctx.send(res);

    // Inspector.detached event
    const InspectorDetached = struct {
        reason: []const u8 = "Render process gone.",
    };
    try cdp.sendEvent(
        alloc,
        ctx,
        "Inspector.detached",
        InspectorDetached,
        .{},
        input.sessionId orelse cdp.ContextSessionID,
    );

    // detachedFromTarget event
    const TargetDetached = struct {
        sessionId: []const u8,
        targetId: []const u8,
    };
    try cdp.sendEvent(
        alloc,
        ctx,
        "Target.detachedFromTarget",
        TargetDetached,
        .{
            .sessionId = input.sessionId orelse cdp.ContextSessionID,
            .targetId = input.params.targetId,
        },
        null,
    );

    if (ctx.browser.session.page != null) ctx.browser.session.page.?.end();

    return "";
}

fn sendMessageToTarget(
    alloc: std.mem.Allocator,
    msg: *IncomingMessage,
    ctx: *Ctx,
) ![]const u8 {
    // input
    const Params = struct {
        message: []const u8,
        sessionId: []const u8,
    };
    const input = try Input(Params).get(alloc, msg);
    defer input.deinit();
    log.debug("Req > id {d}, method {s} ({s})", .{ input.id, "target.sendMessageToTarget", input.params.message });

    // get the wrapped message.
    var wmsg = IncomingMessage.init(alloc, input.params.message);
    defer wmsg.deinit();

    const res = cdp.dispatch(alloc, &wmsg, ctx) catch |e| {
        log.err("send message {d} ({s}): {any}", .{ input.id, input.params.message, e });
        // TODO dispatch error correctly.
        return e;
    };

    // receivedMessageFromTarget event
    const ReceivedMessageFromTarget = struct {
        message: []const u8,
        sessionId: []const u8,
    };
    try cdp.sendEvent(
        alloc,
        ctx,
        "Target.receivedMessageFromTarget",
        ReceivedMessageFromTarget,
        .{
            .message = res,
            .sessionId = input.params.sessionId,
        },
        null,
    );

    return "";
}

// noop
fn detachFromTarget(
    alloc: std.mem.Allocator,
    msg: *IncomingMessage,
    _: *Ctx,
) ![]const u8 {
    // input
    const input = try Input(void).get(alloc, msg);
    defer input.deinit();
    log.debug("Req > id {d}, method {s}", .{ input.id, "target.detachFromTarget" });

    // output
    return result(alloc, input.id, bool, true, input.sessionId);
}
