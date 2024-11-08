const std = @import("std");
const actors = @import("actors/root.zig");

pub fn connection_thread(host_name: []const u8, host_port: u16) void {
    const allocator = std.heap.page_allocator;

    const addresses = std.net.getAddressList(allocator, host_name, host_port) catch {
        std.debug.print("Could not resolve {s}:{d}\n", .{host_name, host_port});
        return;
    };

    defer addresses.deinit();

    var address: std.posix.sockaddr = undefined;
    for (addresses.addrs) |addr| {
        std.debug.print("discovered address with family {}\n", .{addr.any});
        if (addr.any.family == std.os.linux.AF.INET) {
            address = addr.any;
        }
    }

    const sock = std.posix.socket(
        std.os.linux.AF.INET,
        std.os.linux.SOCK.STREAM,
        std.os.linux.IPPROTO.TCP
    ) catch |e| {
        std.debug.print("Could not create a tcp socket {}\n", .{e});
        return;
    };

    std.posix.connect(sock, &address, @sizeOf(@TypeOf(address))) catch |err| {
        std.debug.print("Could not connect to server {}\n", .{err});
        return;
    };
    defer std.posix.close(sock);

    var flags = std.posix.fcntl(sock, std.posix.F.GETFL, 0) catch |e| {
        std.debug.print("Could not get socket flags {}\n", .{e});
        return;
    };

    flags = flags | 1 << @bitOffsetOf(std.posix.O, "NONBLOCK");
    _ = std.posix.fcntl(sock, std.posix.F.SETFL, flags) catch |e| {
        std.debug.print("Could not set socket flags {}\n", .{e});
        return;
    };


    _ = std.posix.write(sock, "<getProperties version=\"1.7\"/><enableBLOB>Also</enableBLOB>") catch {
        std.debug.print("Could not write getProperties to ${s}:${d}\n", .{host_name, host_port});
        return;
    };

    var buffer: [1024*1024*4]u8 = undefined;
    var bytes_read: usize = undefined;
    var i:u32 = 0;
    while(true) {
        bytes_read = 0;

        // std.debug.print("Starting read\n", .{});
        bytes_read = recv_block: {

            const result = std.posix.recv(sock, buffer[0..], 0) catch |err| {
                if (err == error.WouldBlock) {
                    break :recv_block 0;
                }
                std.debug.print("error {} occured while reading socket\n", .{err});
                break;
            };

            break :recv_block result;
        };

        if (bytes_read > 0) {
            std.debug.print("{d}/{d} bytes read {d}\n", .{bytes_read, buffer.len, i});
            //const valid_buffer = buffer[0..bytes_read];
            //const stdout = std.io.getStdOut();

            // _ = stdout.writeAll(valid_buffer) catch {
            //     std.debug.print("could not write to stdout\n", .{});
            //     break;
            // };
            //
            // _ = stdout.writeAll("\n----\n") catch {
            //     std.debug.print("could not write to stdout\n", .{});
            //     break;
            // };
        }

        if (bytes_read < buffer.len) {
            // std.debug.print("t sleeping\n", .{});
            std.time.sleep(100 * std.time.ns_per_ms);
            i = i + 1;
        }
    }
}


pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const status = gpa.deinit();
        std.debug.print("main exiting, allocator status: {}", . {status});
    }

    const i = try allocator.alloc(usize, 1);
    allocator.free(i);


    // var sys = ActorSystem.init(allocator);
    // try sys.addClass(NoOpActorClass.asActorClass());
    // var sys_affordance = sys.asAffordance();
    // const alias = sys_affordance.createActor("noop", "noop", "");
    // if (alias) |alias_sure| {
    //     sys_affordance.sendData(alias_sure, "");
    // }





    //
    // // const host_name = "mobile-mini.local";
    // const host_name = "localhost";
    // const host_port = 7624;
    //
    //
    //
    // {
    //     const t = std.Thread.spawn(.{ .allocator = allocator}, connection_thread, .{host_name, host_port}) catch {
    //         std.debug.print("error spawning thread", . {});
    //         return;
    //     };
    //
    //     // defer t.detach();
    //
    //     t.join();
    //
    //     // var i: u32 = 0;
    //     // while(i < 10) {
    //     //     std.debug.print("main sleeping\n", .{});
    //     //     std.time.sleep(std.time.ns_per_s);
    //     //     i = i + 1;
    //     // }
    //
    // }
    //
    //
    // std.debug.print("sleeping last time\n", .{});
    // std.time.sleep(std.time.ns_per_s * 5);


    // // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    // 
    // // stdout is for the actual output of your application, for example if you
    // // are implementing gzip, then only the compressed bytes should be sent to
    // // stdout, not any debugging messages.
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();
    // 
    // try stdout.print("Run `zig build test` to run the tests.\n", .{});
    // 
    // try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

