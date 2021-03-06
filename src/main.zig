const std = @import("std");
const Allocator = std.mem.Allocator;

//;

const lib = @import("lib.zig");

//;

pub fn readFile(allocator: Allocator, filename: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(filename, .{ .read = true });
    defer file.close();
    return file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

pub fn demo(allocator: Allocator) !void {
    var to_load: ?[:0]u8 = null;
    var i: usize = 0;
    var args = std.process.args();
    while (args.next(allocator)) |arg_err| {
        const arg = try arg_err;
        if (i == 1) {
            to_load = arg;
        } else {
            allocator.free(arg);
        }
        i += 1;
    }

    var vm = try lib.VM.init(allocator);
    defer vm.deinit();

    if (to_load) |filename| {
        var f = try readFile(allocator, filename);
        vm.source_user_input = lib.VM.forth_false;
        vm.source_ptr = @ptrToInt(f.ptr);
        vm.source_len = f.len;
        vm.source_in = 0;
        vm.interpret() catch |err| switch (err) {
            error.WordNotFound => {
                std.debug.print("word not found: {s}\n", .{vm.word_not_found});
                return err;
            },
            else => return err,
        };
    }

    vm.source_user_input = lib.VM.forth_true;
    try vm.refill();
    try vm.drop();
    vm.interpret() catch |err| switch (err) {
        error.WordNotFound => {
            std.debug.print("word not found: {s}\n", .{vm.word_not_found});
            return err;
        },
        else => return err,
    };
}

test "" {
    std.debug.print("\n\n", .{});
    try demo(std.testing.allocator);
}

pub fn main() !void {
    try demo(std.heap.c_allocator);
}
