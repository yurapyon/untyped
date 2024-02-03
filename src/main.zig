const std = @import("std");
const Allocator = std.mem.Allocator;

//;

const lib = @import("lib.zig");

//;

// TODO commandline args

pub fn readFile(allocator: Allocator, filename: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(filename, .{ .mode = .read_only });
    defer file.close();
    return file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

pub fn demo(allocator: Allocator) !void {
    std.debug.print("untyped\n", .{});

    var to_load: ?[:0]const u8 = null;
    var i: usize = 0;
    var args = std.process.args();
    while (args.next()) |arg| {
        if (i == 1) {
            to_load = arg;
        }
        i += 1;
    }

    var vm: lib.VM = undefined;
    try vm.init(allocator);
    defer vm.deinit();

    if (to_load) |filename| {
        var f = try readFile(allocator, filename);
        defer allocator.free(f);
        vm.interpretBuffer(f) catch |err| switch (err) {
            error.WordNotFound => {
                std.debug.print("word not found: {s}\n", .{vm.word_not_found});
                return err;
            },
            else => return err,
        };
    }

    if (vm.should_bye) {
        return;
    }

    vm.source_user_input = lib.VM.forth_true;
    try vm.refill();
    try vm.drop();
    while (!vm.should_bye) {
        vm.interpret() catch |err| switch (err) {
            error.WordNotFound => {
                std.debug.print("word not found: {s}\n", .{vm.word_not_found});
                // return err;
            },
            else => return err,
        };
    }
}

test {
    std.debug.print("\n\n", .{});
    try demo(std.testing.allocator);
}

pub fn main() !void {
    try demo(std.heap.c_allocator);
}
