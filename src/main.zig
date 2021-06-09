const std = @import("std");
const Allocator = std.mem.Allocator;

//;

pub fn memCastOne(comptime T: type, ptr: *u8) *T {
    return @ptrCast(T, @alignCast(@alignOf(@typeInfo(T).Pointer.child), ptr));
}

// pub fn memCastSlice(comptime T: type, ptr: *u8, len: usize) []T {
//     var ret: []T = undefined;
//     const T_ptr = @ptrCast([*]T, @alignCast(@alignOf(T), ptr));
//     ret.ptr = T_ptr;
//     ret.len = len;
//     return ret;
// }

//;

// TODO
//   float stack
//   limit word len to 32
//   instead of line_buf_len should it be a ptr to the top

// sp points to 1 beyond the top of the stack
//   should i keep it this way?

// state == -1 in compilation state

pub const VM = struct {
    const Self = @This();

    const Error = error{
        StackUnderflow,
        StackOverflow,
        ReturnStackUnderflow,
        ReturnStackOverflow,
        AddressOutOfBounds,
        WordTooLong,
        EmptyInputBuffer,
    } || Allocator.Error;

    // TODO make sure @sizeOf(usize) == @sizeOf(Cell)
    const Cell = u64;

    const forth_false: Cell = 0;
    const forth_true = ~forth_false;

    const word_immediate_flag = 0x80;
    const word_hidden_flag = 0x40;
    const word_len_mask = 0x3f;

    const mem_size = 4 * 1024 * 1024;
    const stack_size = 192 * @sizeOf(Cell);
    const rstack_size = 64 * @sizeOf(Cell);
    const line_buf_size = 128;

    const latest_pos = 0 * @sizeOf(Cell);
    const here_pos = 1 * @sizeOf(Cell);
    const base_pos = 2 * @sizeOf(Cell);
    const state_pos = 3 * @sizeOf(Cell);
    const sp_pos = 4 * @sizeOf(Cell);
    const rsp_pos = 5 * @sizeOf(Cell);
    const line_buf_len_pos = 6 * @sizeOf(Cell);
    const stack_start = 7 * @sizeOf(Cell);
    const rstack_start = stack_start + stack_size;
    const line_buf_start = rstack_start + rstack_size;
    const dictionary_start = line_buf_start + line_buf_size;

    allocator: *Allocator,
    mem: []u8,

    latest: *Cell,
    here: *Cell,
    base: *Cell,
    state: *Cell,
    sp: *Cell,
    rsp: *Cell,
    line_buf_len: *Cell,
    stack: [*]Cell,
    rstack: [*]Cell,
    line_buf: [*]u8,
    dictionary: [*]u8,

    last_input: ?[]u8,
    input_at: usize,

    pub fn init(allocator: *Allocator) Allocator.Error!Self {
        var ret: Self = undefined;
        ret.allocator = allocator;
        ret.mem = try allocator.allocWithOptions(u8, mem_size, @alignOf(Cell), null);
        ret.latest = @ptrCast(*Cell, @alignCast(@alignOf(Cell), &ret.mem[latest_pos]));
        ret.here = @ptrCast(*Cell, @alignCast(@alignOf(Cell), &ret.mem[here_pos]));
        ret.base = @ptrCast(*Cell, @alignCast(@alignOf(Cell), &ret.mem[base_pos]));
        ret.state = @ptrCast(*Cell, @alignCast(@alignOf(Cell), &ret.mem[state_pos]));
        ret.sp = @ptrCast(*Cell, @alignCast(@alignOf(Cell), &ret.mem[sp_pos]));
        ret.rsp = @ptrCast(*Cell, @alignCast(@alignOf(Cell), &ret.mem[rsp_pos]));
        ret.line_buf_len = @ptrCast(*Cell, @alignCast(@alignOf(Cell), &ret.mem[line_buf_len_pos]));
        ret.stack = @ptrCast([*]Cell, @alignCast(@alignOf(Cell), &ret.mem[stack_start]));
        ret.rstack = @ptrCast([*]Cell, @alignCast(@alignOf(Cell), &ret.mem[rstack_start]));
        ret.line_buf = @ptrCast([*]u8, &ret.mem[line_buf_start]);
        ret.dictionary = @ptrCast([*]u8, &ret.mem[dictionary_start]);
        ret.last_input = null;
        ret.input_at = 0;

        // init vars
        ret.latest.* = 0;
        ret.here.* = @ptrToInt(ret.dictionary);
        ret.base.* = 10;
        ret.state.* = forth_false;
        ret.sp.* = @ptrToInt(ret.stack);
        ret.rsp.* = @ptrToInt(ret.rstack);
        ret.line_buf_len.* = 0;

        return ret;
    }

    pub fn deinit(self: *Self) void {
        if (self.last_input) |input| {
            self.allocator.free(input);
        }
        self.allocator.free(self.mem);
    }

    //;

    pub fn pop(self: *Self) Error!Cell {
        if (self.sp.* <= @ptrToInt(self.stack)) {
            return error.StackUnderflow;
        }
        self.sp.* -= @sizeOf(Cell);
        const ret = @intToPtr(*const Cell, self.sp.*).*;
        return ret;
    }

    pub fn push(self: *Self, val: Cell) Error!void {
        if (self.sp.* >= @ptrToInt(self.stack) + stack_size - @sizeOf(Cell) - 1) {
            return error.StackOverflow;
        }
        @intToPtr(*Cell, self.sp.*).* = val;
        self.sp.* += @sizeOf(Cell);
    }

    pub fn rpop(self: *Self) Error!Cell {
        // TODO fix
        if (self.rsp.* == 0) {
            return error.ReturnStackUnderflow;
        }
        const ret = self.rstack[self.rsp.*];
        self.rsp.* -= 1;
        return ret;
    }

    pub fn rpush(self: *Self, val: Cell) Error!void {
        // TODO fix
        if (self.rsp.* >= rstack_size) {
            return error.ReturnStackOverflow;
        }
        self.rstack[self.rsp.*] = val;
        self.rsp.* += 1;
    }

    //;

    pub fn debugPrintStack(self: *Self) void {
        const len = (self.sp.* - @ptrToInt(self.stack)) / @sizeOf(Cell);
        std.debug.print("stack: len: {}\n", .{len});
        var i = len;
        var p = @ptrToInt(self.stack);
        while (p < self.sp.*) : (p += @sizeOf(Cell)) {
            i -= 1;
            std.debug.print("{}: 0x{x:.>16} {}\n", .{
                i,
                @intToPtr(*const Cell, p).*,
                @intToPtr(*const Cell, p).*,
            });
        }
    }

    //;

    pub fn checkedReadCell(self: *Self, addr: Cell) Error!Cell {
        if (addr < @ptrToInt(self.mem.ptr) or
            addr >= @ptrToInt(self.mem.ptr) + mem_size - @sizeOf(Cell) + 1)
        {
            return error.AddressOutOfBounds;
        }
        return @intToPtr(*const Cell, addr).*;
    }

    pub fn checkedReadByte(self: *Self, addr: Cell) Error!u8 {
        if (addr < @ptrToInt(self.mem.ptr) or
            addr >= @ptrToInt(self.mem.ptr) + mem_size)
        {
            return error.AddressOutOfBounds;
        }
        return @intToPtr(*const u8, addr).*;
    }

    pub fn checkedWriteCell(self: *Self, addr: Cell, val: Cell) Error!void {
        if (addr < @ptrToInt(self.mem.ptr) or
            addr >= @ptrToInt(self.mem.ptr) + mem_size - @sizeOf(Cell) + 1)
        {
            return error.AddressOutOfBounds;
        }
        @intToPtr(*Cell, addr).* = val;
    }

    pub fn checkedWriteByte(self: *Self, addr: Cell, val: u8) Error!void {
        if (addr < @ptrToInt(self.mem.ptr) or
            addr >= @ptrToInt(self.mem.ptr) + mem_size)
        {
            return error.AddressOutOfBounds;
        }
        @intToPtr(*u8, addr).* = val;
    }

    pub fn readInput(self: *Self, buf: []const u8) Allocator.Error!void {
        if (self.last_input) |input| {
            self.allocator.free(input);
        }
        self.last_input = try self.allocator.dupe(u8, buf);
        self.input_at = 0;
    }

    pub fn readNextWord(self: *Self) Error!usize {
        if (self.last_input == null) {
            return error.EmptyInputBuffer;
        }

        const input = self.last_input.?;

        var len: Cell = 0;
        var ch: u8 = undefined;

        while (true) {
            if (self.input_at >= input.len) {
                self.line_buf_len.* = 0;
                return 0;
            }

            ch = input[self.input_at];

            if (ch == ' ' or ch == '\n') {
                self.input_at += 1;
                continue;
            } else if (ch == '\\') {
                while (true) {
                    if (self.input_at >= input.len) {
                        self.line_buf_len.* = 0;
                        return 0;
                    }

                    ch = input[self.input_at];

                    if (ch == '\n') {
                        break;
                    }
                    self.input_at += 1;
                }
            } else {
                break;
            }
            self.input_at += 1;
        }

        while (true) {
            if (self.input_at >= input.len) {
                break;
            }

            ch = input[self.input_at];

            if (ch == ' ' or ch == '\n') {
                break;
            }

            if (len >= line_buf_size) {
                return error.WordTooLong;
            }

            self.line_buf[len] = ch;
            len += 1;

            self.input_at += 1;
        }

        self.line_buf_len.* = len;
        return len;
    }

    pub fn createWordHeader(
        self: *Self,
        name: []const u8,
        flags: u8,
    ) Error!void {
        // TODO check word len isnt too long?
        const new_latest = self.here.*;
        try self.push(self.latest.*);
        try self.comma();
        try self.push(flags | (name.len & word_len_mask));
        try self.commaByte();

        for (name) |ch| {
            try self.push(ch);
            try self.commaByte();
        }

        while ((self.here.* % @sizeOf(Cell)) != 0) {
            try self.push(0);
            try self.commaByte();
        }

        self.latest.* = new_latest;
    }

    // if word not found, will return 0
    pub fn findWord(self: *Self, addr: Cell, len: Cell) Error!Cell {
        var name: []const u8 = undefined;
        name.ptr = @intToPtr([*]const u8, addr);
        name.len = len;

        var check = self.latest.*;
        while (check != 0) : (check = try self.checkedReadCell(check)) {
            const mem_ptr = @intToPtr([*]const u8, check);
            const check_flags = mem_ptr[@sizeOf(Cell)];
            if ((check_flags & word_len_mask) != len) continue;
            if ((check_flags & word_hidden_flag) != 0) continue;

            var name_matches: bool = true;
            var i: usize = 0;
            for (name) |name_ch| {
                const mem_ch = mem_ptr[@sizeOf(Cell) + 1 + i];
                if (std.ascii.toUpper(mem_ch) != std.ascii.toUpper(name_ch)) {
                    name_matches = false;
                    break;
                }
                i += 1;
            }

            if (name_matches) {
                break;
            }
        }
        return check;
    }

    // builtins

    pub fn store(self: *Self) Error!void {
        const addr = try self.pop();
        const val = try self.pop();
        try self.checkedWriteCell(addr, val);
    }

    pub fn storeByte(self: *Self) Error!void {
        const addr = try self.pop();
        const val = try self.pop();
        try self.checkedWriteByte(addr, @intCast(u8, val & 0xff));
    }

    pub fn comma(self: *Self) Error!void {
        try self.push(self.here.*);
        try self.store();
        self.here.* += @sizeOf(Cell);
    }

    pub fn commaByte(self: *Self) Error!void {
        try self.push(self.here.*);
        try self.storeByte();
        self.here.* += 1;
    }

    pub fn word(self: *Self) Error!void {
        const len = try self.readNextWord();
        try self.push(@ptrToInt(self.line_buf));
        try self.push(len);
    }

    pub fn find(self: *Self) Error!void {
        const len = try self.pop();
        const addr = try self.pop();
        const ret = try self.findWord(addr, len);
        if (ret == 0) {
            try self.push(addr);
            try self.push(forth_false);
        } else {
            const mem_ptr = @intToPtr([*]const u8, ret);
            const flags = mem_ptr[@sizeOf(Cell)];
            const is_immediate = (flags & word_immediate_flag) != 0;

            try self.push(ret);
            try self.push(if (is_immediate) 1 else forth_true);
        }
    }

    pub fn type_(self: *Self) Error!void {
        const len = try self.pop();
        const addr = try self.pop();
        var slc: []u8 = undefined;
        slc.ptr = @intToPtr([*]const u8, addr);
        slc.len = len;
        std.debug.print("{}", .{slc});
    }

    // TODO is there a way to not use zig stack
    //        for is interpretting code calls quit alot
    //        kindof a non issue
    pub fn quit(self: *Self) Error!void {
        self.rsp.* = @ptrToInt(self.rstack);
        try self.interpret();
    }

    pub fn interpret(self: *Self) Error!void {
        // TODO allow exit
        while (true) {
            try self.word();
            try self.find();
        }
    }
};

pub fn demo(allocator: *Allocator) !void {
    var vm = try VM.init(allocator);
    defer vm.deinit();

    try vm.createWordHeader("defined", 0);
    try vm.createWordHeader("next", VM.word_hidden_flag);
    try vm.createWordHeader("next2", VM.word_immediate_flag);

    try vm.readInput("defined not next next2");
    try vm.word();
    vm.debugPrintStack();
    try vm.find();
    vm.debugPrintStack();
    try vm.word();
    vm.debugPrintStack();
    try vm.find();
    vm.debugPrintStack();
    try vm.word();
    vm.debugPrintStack();
    try vm.find();
    vm.debugPrintStack();
    try vm.word();
    vm.debugPrintStack();
    try vm.find();
    vm.debugPrintStack();

    //     try vm.word();
    //     vm.debugPrintStack();
    //     try vm.type_();

    // var len = try vm.readNextWord();
    // while (len > 0) {
    // std.debug.print("{}\n", .{vm.line_buf[0..len]});
    // len = try vm.readNextWord();
    // }
}

test "" {
    std.debug.print("\n\n", .{});

    try demo(std.testing.allocator);
}

pub fn main() !void {
    try demo(std.heap.c_allocator);
}
