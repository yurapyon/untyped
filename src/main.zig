const std = @import("std");
const Allocator = std.mem.Allocator;

//;

pub fn memCastOne(comptime T: type, ptr: *u8) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), ptr));
}

pub fn memCastSlice(comptime T: type, ptr: *u8, len: usize) []T {
    const ret: []T = undefined;
    const T_ptr = @ptrCast([*]T, @alignCast(@alignOf(T), ptr));
    ret.ptr = T_ptr;
    ret.len = len;
    return ret;
}

//;

pub const VM = struct {
    const Self = @This();

    const Error = error{
        StackUnderflow,
        StackOverflow,
        ReturnStackUnderflow,
        ReturnStackOverflow,
        AddressOutOfBounds,
    } || Allocator.Error;

    const Cell = u64;

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
    stack: []Cell,
    rstack: []Cell,
    line_buf: []u8,
    dictionary: []u8,

    pub fn init(allocator: *Allocator) Allocator.Error!Self {
        var ret: Self = undefined;
        ret.allocator = allocator;
        ret.mem = try allocator.alloc(u8, mem_size);
        ret.latest = memCastOne(Cell, &ret.mem[latest_pos]);
        ret.here = memCastOne(Cell, &ret.mem[here_pos]);
        ret.base = memCastOne(Cell, &ret.mem[base_pos]);
        ret.state = memCastOne(Cell, &ret.mem[state_pos]);
        ret.sp = memCastOne(Cell, &ret.mem[sp_pos]);
        ret.rsp = memCastOne(Cell, &ret.mem[rsp_pos]);
        ret.line_buf_len = memCastOne(Cell, &ret.mem[line_buf_len_pos]);
        ret.stack = memCastSlice(Cell, &ret.mem[stack_start], stack_size);
        ret.rstack = memCastSlice(Cell, &ret.mem[rstack_start], rstack_size);
        ret.line_buf = ret.mem[line_buf_start..(line_buf_start + line_buf_size)];
        ret.dictionary = ret.mem[dictionary_start..];
        return ret;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.mem);
    }

    //;

    pub fn pop(self: *Self) Error!Cell {
        if (self.sp.* == 0) {
            return error.StackUnderflow;
        }
        const ret = self.stack[self.sp.*];
        self.sp.* -= 1;
        return ret;
    }

    pub fn push(self: *Self, val: Cell) Error!void {
        if (self.sp.* >= stack_size) {
            return error.StackOverflow;
        }
        self.stack[self.sp.*] = val;
        self.sp.* += 1;
    }

    pub fn rpop(self: *Self) Error!Cell {
        if (self.rsp.* == 0) {
            return error.ReturnStackUnderflow;
        }
        const ret = self.rstack[self.rsp.*];
        self.rsp.* -= 1;
        return ret;
    }

    pub fn rpush(self: *Self, val: Cell) Error!void {
        if (self.rsp.* >= stack_size) {
            return error.ReturnStackOverflow;
        }
        self.rstack[self.rsp.*] = val;
        self.rsp.* += 1;
    }

    //;

    pub fn readMem(self: *Self, addr: Cell) Error!Cell {
        if (addr >= mem_size) {
            return error.AddressOutOfBounds;
        }
        return memCastOne(Cell, &self.mem[addr]);
    }

    pub fn writeMem(self: *Self, addr: Cell, val: Cell) Error!void {
        if (addr >= mem_size) {
            return error.AddressOutOfBounds;
        }
        var c = memCastOne(Cell, &self.mem[addr]);
        c.* = val;
    }

    // TODO EOF getc
    // getc from stdin?
    pub fn nextWord(self: *Self) Error!usize {
        var len: Cell = 0;
        var ch = undefined;

        while (true) {
            ch = getc();
            if (ch == EOF) {
                break;
            } else if (ch == ' ' or ch == '\n') {
                continue;
            } else if (ch == '\\') {
                while (ch != EOF) : (ch = getc()) {
                    if (ch == '\n') {
                        break;
                    }
                }
            } else {
                break;
            }
        }

        while (true) {
            if (ch == ' ' or ch == '\n' or ch == EOF) {
                break;
            }
            // TODO is this an error?
            if (len >= line_buf_size) {
                break;
            }
            self.line_buf[len] = ch;
            len += 1;
            ch = getc();
        }

        self.line_buf_len.* = len;
        return len;
    }
};
