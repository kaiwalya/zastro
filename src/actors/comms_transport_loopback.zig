
const std = @import("std");
const transport = @import("./comms_transport.zig");

const Transport = transport.Transport;
const Address = Transport.Address;
const Payload = Transport.Payload;
const RecvError = Transport.RecvError;
const SendError = Transport.SendError;
const PayloadList = std.ArrayList(Payload);
fn make_payload_list(allocator: std.mem.Allocator) PayloadList {
    return PayloadList.init(allocator);
}

const LoopbackTransport = struct {

    allocator: std.mem.Allocator,
    store: std.StringHashMap(PayloadList),
    pending_free: PayloadList,

    pub fn init(allocator: std.mem.Allocator) LoopbackTransport {
        return . {
            .allocator = allocator,
            .store = std.StringHashMap(PayloadList).init(allocator),
            .pending_free = make_payload_list(allocator)
        };
    }


    pub fn deinit(self: *@This()) void {
        var it = self.store.valueIterator();
        while(it.next()) |v| {
            for (v.items) |p| {
                self.allocator.free(p);
            }
            v.deinit();
        }
        self.store.deinit();

        if (self.pending_free.items.len > 0) {
            std.debug.print("deinit called before all borrowed slices were returned. There will be {d} leaks\n", .{self.pending_free.items.len});
        }
        self.pending_free.deinit();
    }

    fn get_payloads(self: *@This(), address: Address, create: bool) !?*PayloadList {
        const v = self.store.getEntry(address);
        if (v) |vv| {
            return vv.value_ptr;
        }

        if (create) {
            const new_entry = make_payload_list(self.allocator);
            try self.store.put(address, new_entry);
            const payload = try self.get_payloads(address, false);
            return payload;
        }

        return null;
    }

    pub fn send(self: *@This(), to: Address, payload: Payload) SendError!void {
        const copy = self.allocator.alloc(@TypeOf(payload[0]), payload.len) catch return SendError.SendFailure;
        @memcpy(copy, payload);
        const payloads = self.get_payloads(to, true) catch return SendError.SendFailure;
        payloads.?.insert(0, copy) catch return SendError.SendFailure;
        //payloads.?.append(copy) catch return SendError.SendFailure;
        std.debug.print("sending {d} bytes to {s}\n", . {payload.len, to});
    }

    pub fn recv(self: *@This(), from: Address) RecvError ! Payload {
        const payloads = self.get_payloads(from, false) catch return RecvError.RecvFailure;
        if (payloads == null or payloads.?.items.len == 0) {
            return RecvError.RecvFailure;
        }

        const ret = payloads.?.pop();
        self.pending_free.append(ret) catch return RecvError.RecvFailure;
        std.debug.print("received {d} bytes from {s}\n", .{ret.len, from});
        return ret;
    }

    pub fn done(self: *@This(), payload: Payload) RecvError ! void {
        for (self.pending_free.items, 0..) |p, idx| {
            if (p.ptr == payload.ptr) {
                _ = self.pending_free.swapRemove(idx);
                self.allocator.free(p);
                return;
            }
        }
        return RecvError.RecvFailure;
    }

    pub fn peek(self: *@This(), to: Address) RecvError ! usize {
        const v = self.get_payloads(to, false) catch return RecvError.RecvFailure;
        if (v) |vv| {
            return vv.items.len;
        }
        return 0;
    }

    pub fn asTransport(self: *@This()) Transport {
        return Transport.fromPtr(self);
    }
};


test "loopback" {
    var l: LoopbackTransport = LoopbackTransport.init(std.testing.allocator);
    defer l.deinit();

    const t = l.asTransport();
    try std.testing.expectEqual(0, try t.peek("remote"));

    try t.send("remote", "1234");
    try std.testing.expectEqual(1, try t.peek("remote"));

    try t.send("remote", "5678");
    try std.testing.expectEqual(2, try t.peek("remote"));

    const d = try t.recv("remote");
    try std.testing.expectEqualStrings(d, "1234");
    try t.done(d);

    try std.testing.expectEqual(try t.peek("remote"), 1);
}
