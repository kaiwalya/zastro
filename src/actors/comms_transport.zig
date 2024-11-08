const std = @import("std");

pub const Transport = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const Address = []const u8;
    pub const Payload = []const u8;

    pub const SendError = error{SendFailure};
    pub const RecvError = error{RecvFailure};

    pub const VTable = struct {
        send: *const fn(self: *anyopaque, to: Address, bytes: Payload) SendError!void,
        recv: *const fn(self: *anyopaque, from: Address) RecvError ! Payload,
        done: *const fn(self: *anyopaque, payload: Payload) RecvError ! void,
        peek: *const fn(self: *anyopaque, from: Address) RecvError ! usize,
    };

    pub fn send(self: @This(), to: Address, bytes: Payload) SendError!void {
        return self.vtable.send(self.ptr, to, bytes);
    }

    pub fn recv(self: @This(), from: Address) RecvError!Payload {
        return self.vtable.recv(self.ptr, from);
    }

    pub fn done(self: @This(), payload: Payload) RecvError!void {
        return self.vtable.done(self.ptr, payload);
    }

    pub fn peek(self: @This(), from: Address) RecvError ! usize {
        return self.vtable.peek(self.ptr, from);
    }

    pub fn fromPtr(implRef: anytype) Transport {
        const Impl: type = @TypeOf(implRef.*);

        const ImplWrapperFuncs = comptime struct {
            fn send(obj: *anyopaque, to: Address, payload: Payload) SendError ! void {
                const t: *Impl = @ptrCast(@alignCast(obj));
                return t.send(to, payload);
            }

            fn recv(obj: *anyopaque, from: Address) RecvError ! Payload {
                const t: *Impl = @ptrCast(@alignCast(obj));
                return t.recv(from);
            }

            fn done(obj: *anyopaque, payload: Payload) RecvError ! void {
                const t: *Impl = @ptrCast(@alignCast(obj));
                return t.done(payload);
            }

            fn peek(obj: *anyopaque, from: Address) RecvError ! usize {
                const t: *Impl = @ptrCast(@alignCast(obj));
                return t.peek(from);
            }

        };
        const TVtable: Transport.VTable = .{
            .send = ImplWrapperFuncs.send,
            .recv = ImplWrapperFuncs.recv,
            .done = ImplWrapperFuncs.done,
            .peek = ImplWrapperFuncs.peek,
        };

        return .{
            .ptr = implRef,
            .vtable =  &TVtable
        };
    }
};

test "basics" {
    const FakeImpl = struct {
        allocator: std.mem.Allocator,

        const RecvError = Transport.RecvError;
        const SendError = Transport.SendError;

        pub fn send(_: *@This(), to: Transport.Address, payload: Transport.Payload) SendError!void {
            std.debug.print("sending {d} bytes to {s}\n", . {payload.len, to});
        }

        pub fn recv(self: *@This(), from: Transport.Address) RecvError ! Transport.Payload {
            const ret = self.allocator.alloc(u8, 1) catch return RecvError.RecvFailure;
            std.debug.print("received {d} bytes from {s}\n", .{ret.len, from});
            return ret;
        }

        pub fn done(self: *@This(), payload: Transport.Payload) RecvError ! void {
            return self.allocator.free(payload);
        }

        pub fn peek(_: *@This(), _: Transport.Address) RecvError ! usize {
            return 1;
        }

        pub fn asTransport(self: *@This()) Transport {
            return Transport.fromPtr(self);
        }
    };


    var impl = FakeImpl {.allocator = std.testing.allocator};
    const transport = impl.asTransport();
    try transport.send("remote", "test");
    try std.testing.expectEqual(try transport.peek("remote"), 1);
    const d = try transport.recv("remote");
    try transport.done(d);
}