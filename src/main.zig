const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

//;

// TODO
//   float stack
//   limit word len (go with 64 i guess?)
//   instead of line_buf_len should it be a ptr to the top

// sp points to 1 beyond the top of the stack
//   should i keep it this way?
// rsp is the same

// self.base.* needs to be <= 255 because of zig.fmt.parseInt

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
        NoInputBuffer,
        WordNotFound,
        EndOfInput,
    } || Allocator.Error;

    // TODO make sure @sizeOf(usize) == @sizeOf(Cell)
    const Cell = u64;
    const Builtin = fn (self: *Self) Error!void;

    const forth_false: Cell = 0;
    const forth_true = ~forth_false;

    const builtin_fn_id = 0;

    const find_info_not_found = 0;
    const find_info_immediate = 1;
    const find_info_not_immediate = ~@as(Cell, 0);

    const word_immediate_flag = 0x2;
    const word_hidden_flag = 0x1;

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
    last_input: ?[]u8,
    input_at: usize,

    // execution
    last_ip: Cell,
    next: Cell,
    exec_cfa: Cell,
    exec_cmd: Cell,

    quit_address: Cell,
    docol_address: Cell,
    exit_address: Cell,
    lit_address: Cell,
    should_stop_interpreting: bool,

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

    pub fn init(allocator: *Allocator) Allocator.Error!Self {
        var ret: Self = undefined;

        ret.allocator = allocator;
        ret.last_input = null;
        ret.input_at = 0;
        ret.last_ip = 0;
        ret.next = 0;
        ret.should_stop_interpreting = true;

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
        // TODO dont do alignment math here
        //        just let misalignment be caught by inttoptr
        if (self.sp.* >= @ptrToInt(self.stack) + stack_size - @sizeOf(Cell) - 1) {
            return error.StackOverflow;
        }
        @intToPtr(*Cell, self.sp.*).* = val;
        self.sp.* += @sizeOf(Cell);
    }

    pub fn rpop(self: *Self) Error!Cell {
        if (self.rsp.* <= @ptrToInt(self.rstack)) {
            return error.StackUnderflow;
        }
        self.rsp.* -= @sizeOf(Cell);
        const ret = @intToPtr(*const Cell, self.rsp.*).*;
        return ret;
    }

    pub fn rpush(self: *Self, val: Cell) Error!void {
        // TODO dont do alignment math here
        //        just let misalignment be caught by inttoptr
        if (self.rsp.* >= @ptrToInt(self.rstack) + rstack_size - @sizeOf(Cell) - 1) {
            return error.StackOverflow;
        }
        @intToPtr(*Cell, self.rsp.*).* = val;
        self.rsp.* += @sizeOf(Cell);
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

    // TODO for read and write cell, just check if addr is within
    //        memory start and end, alignment check will test for invalid alignment
    //          if desired *cell is only partly within memory
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
        self.should_stop_interpreting = false;
    }

    pub fn readNextWord(self: *Self) Error!usize {
        if (self.last_input == null) {
            return error.NoInputBuffer;
        }

        const input = self.last_input.?;

        var len: Cell = 0;
        var ch: u8 = undefined;

        while (true) {
            if (self.input_at >= input.len) {
                // self.line_buf_len.* = 0;
                // return 0;
                return error.EndOfInput;
            }

            ch = input[self.input_at];

            if (ch == ' ' or ch == '\n') {
                self.input_at += 1;
                continue;
            } else if (ch == '\\') {
                while (true) {
                    if (self.input_at >= input.len) {
                        // self.line_buf_len.* = 0;
                        // return 0;
                        return error.EndOfInput;
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

    pub fn stringAt(addr: Cell, len: Cell) []u8 {
        var str: []u8 = undefined;
        str.ptr = @intToPtr([*]u8, addr);
        str.len = len;
        return str;
    }

    // word header is:
    // |        | | | | | | | ... | ...
    //  ^        ^ ^ ^       ^     ^
    //  addr of  | | name    |     code
    //  previous | name len  padding to @alignOf(Cell)
    //  word     flags

    // builtins are:
    // | WORD HEADER ... | builtin_fn_id | fn_ptr |

    // forth words are:
    // | WORD HEADER ... | DOCOL  | code ... | EXIT |

    // code is executed 'immediately' if the first cell in its cfa is builtin_fn_id

    pub fn createWordHeader(
        self: *Self,
        name: []const u8,
        flags: u8,
    ) Error!void {
        // TODO check word len isnt too long?
        const new_latest = self.here.*;
        try self.push(self.latest.*);
        try self.comma();
        try self.push(flags);
        try self.commaByte();
        try self.push(name.len);
        try self.commaByte();

        for (name) |ch| {
            try self.push(ch);
            try self.commaByte();
        }

        while ((self.here.* % @alignOf(Cell)) != 0) {
            try self.push(0);
            try self.commaByte();
        }

        self.latest.* = new_latest;
    }

    pub fn wordHeaderPrevious(addr: Cell) Cell {
        return @intToPtr(*const Cell, addr).*;
    }

    // TODO do this differently, ie return a *u8 {{{
    pub fn wordHeaderFlags(addr: Cell) u8 {
        return @intToPtr(*const u8, addr + @sizeOf(Cell)).*;
    }

    pub fn wordHeaderSetFlags(addr: Cell, to: u8) void {
        @intToPtr(*u8, addr + @sizeOf(Cell)).* = to;
    }
    // }}}

    pub fn wordHeaderName(addr: Cell) []u8 {
        var name: []u8 = undefined;
        name.ptr = @intToPtr([*]u8, addr + @sizeOf(Cell) + 2);
        name.len = @intToPtr(*u8, addr + @sizeOf(Cell) + 1).*;
        return name;
    }

    pub fn wordHeaderCodeFieldAddress(addr: Cell) Cell {
        const name = wordHeaderName(addr);
        const name_end_addr = @ptrToInt(name.ptr) + name.len;
        const off_aligned = @alignOf(Cell) - (name_end_addr % @alignOf(Cell));
        return if (off_aligned == @alignOf(Cell)) name_end_addr else name_end_addr + off_aligned;
    }

    pub fn createBuiltin(
        self: *Self,
        name: []const u8,
        flags: u8,
        func: *const Builtin,
    ) Error!void {
        try self.createWordHeader(name, flags);
        try self.push(builtin_fn_id);
        try self.comma();
        try self.push(@ptrToInt(func));
        try self.comma();
    }

    pub fn builtinFnPtrAddress(cfa: Cell) Cell {
        return cfa + @sizeOf(Cell);
    }

    pub fn builtinFnPtr(cfa: Cell) *const Builtin {
        const fn_ptr = @intToPtr(*const Cell, builtinFnPtrAddress(cfa)).*;
        return @intToPtr(*const Builtin, fn_ptr);
    }

    // if word not found, will return 0
    // TODO return ?Cell ?
    pub fn findWord(self: *Self, addr: Cell, len: Cell) Error!Cell {
        const name = stringAt(addr, len);

        var check = self.latest.*;
        while (check != 0) : (check = wordHeaderPrevious(check)) {
            const check_name = wordHeaderName(check);
            const flags = wordHeaderFlags(check);
            if (check_name.len != len) continue;
            if ((flags & word_hidden_flag) != 0) continue;

            var name_matches: bool = true;
            var i: usize = 0;
            for (name) |name_ch| {
                if (std.ascii.toUpper(check_name[i]) != std.ascii.toUpper(name_ch)) {
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

    pub fn showStack(self: *Self) Error!void {
        self.debugPrintStack();
    }

    pub fn docol(self: *Self) Error!void {
        try self.rpush(self.last_ip);
        self.next = self.exec_cfa + @sizeOf(Cell);
    }

    pub fn exit(self: *Self) Error!void {
        self.next = try self.rpop();
    }

    pub fn define(self: *Self) Error!void {
        try self.word();
        var len = try self.pop();
        var addr = try self.pop();
        try self.createWordHeader(stringAt(addr, len), 0);
    }

    pub fn pushLatest(self: *Self) Error!void {
        try self.push(@ptrToInt(self.latest));
    }

    pub fn hidden(self: *Self) Error!void {
        const addr = try self.pop();
        const flags = wordHeaderFlags(addr);
        wordHeaderSetFlags(addr, flags ^ word_hidden_flag);
    }

    pub fn immediate(self: *Self) Error!void {
        // TODO should this take an addr like hidden
        // const addr = try self.pop();
        const flags = wordHeaderFlags(self.latest.*);
        wordHeaderSetFlags(self.latest.*, flags ^ word_immediate_flag);
    }

    pub fn lBracket(self: *Self) Error!void {
        self.state.* = forth_false;
    }

    pub fn rBracket(self: *Self) Error!void {
        self.state.* = forth_true;
    }

    pub fn colon(self: *Self) Error!void {
        try self.define();
        try self.push(self.docol_address);
        try self.comma();
        try self.pushLatest();
        try self.fetch();
        try self.hidden();
        try self.rBracket();
    }

    pub fn semicolon(self: *Self) Error!void {
        try self.push(self.exit_address);
        try self.comma();
        try self.pushLatest();
        try self.fetch();
        try self.hidden();
        try self.lBracket();
    }

    pub fn fetch(self: *Self) Error!void {
        const addr = try self.pop();
        try self.push(try self.checkedReadCell(addr));
    }

    pub fn fetchByte(self: *Self) Error!void {
        const addr = try self.pop();
        try self.push(try self.checkedReadByte(addr));
    }

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
            try self.push(find_info_not_found);
        } else {
            const flags = wordHeaderFlags(ret);
            const is_immediate = (flags & word_immediate_flag) != 0;

            try self.push(ret);
            try self.push(if (is_immediate) find_info_immediate else find_info_not_immediate);
        }
    }

    pub fn lit(self: *Self) Error!void {
        try self.push(try self.checkedReadCell(self.next));
        self.next += @sizeOf(Cell);
    }

    pub fn cfa_(self: *Self) Error!void {
        const addr = try self.pop();
        try self.push(wordHeaderCodeFieldAddress(addr));
    }

    pub fn tick(self: *Self) Error!void {
        try self.word();
        try self.find();
        // TODO handle not found
        _ = try self.pop();
        try self.cfa_();

        if (self.state.* == forth_true) {
            try self.push(self.lit_address);
            try self.comma();
            try self.comma();
        }
    }

    pub fn quit(self: *Self) Error!void {
        self.rsp.* = @ptrToInt(self.rstack);
        try self.interpret();
    }

    pub fn interpret(self: *Self) Error!void {
        while (!self.should_stop_interpreting) {
            const is_compiling = self.state.* != forth_false;

            self.last_ip = self.quit_address;
            self.next = self.quit_address;

            self.word() catch |err| switch (err) {
                error.EndOfInput => {
                    self.should_stop_interpreting = true;
                    break;
                },
                else => return err,
            };
            // TODO check we actually have a word here
            try self.find();

            const find_info = try self.pop();
            const addr = try self.pop();
            if (find_info != find_info_not_found) {
                const flags = wordHeaderFlags(addr);
                const is_immediate = (flags & word_immediate_flag) != 0;
                const cfa = wordHeaderCodeFieldAddress(addr);
                const cmd = cfa;
                if (is_compiling and !is_immediate) {
                    try self.push(cfa);
                    try self.comma();
                } else {
                    // TODO this is the 'inner interpreter'
                    //        or EXECUTE
                    // TODO exec_cfa should be exec_cmd_addr
                    self.exec_cfa = cfa;
                    self.exec_cmd = cmd;
                    while (true) {
                        if (self.exec_cfa == self.quit_address) break;
                        if ((try self.checkedReadCell(self.exec_cmd)) == builtin_fn_id) {
                            const fn_ptr = builtinFnPtr(self.exec_cmd);
                            try fn_ptr.*(self);
                        } else {
                            self.last_ip = self.next;
                            self.next = self.exec_cmd;
                        }

                        self.exec_cfa = self.next;
                        self.exec_cmd = try self.checkedReadCell(self.exec_cfa);
                        self.next += @sizeOf(Cell);
                    }
                }
            } else {
                // TODO just uses line_buf directly
                //        is this ok?
                var str: []const u8 = undefined;
                str.ptr = self.line_buf;
                str.len = self.line_buf_len.*;
                const maybe_num = std.fmt.parseInt(Cell, str, @intCast(u8, self.base.* & 0xff)) catch null;
                if (maybe_num) |num| {
                    if (is_compiling) {
                        try self.push(self.lit_address);
                        try self.comma();
                        try self.push(num);
                        try self.comma();
                    } else {
                        try self.push(num);
                    }
                } else {
                    // TODO word not found errors for comments and \n and trailing whitespace??
                    return error.WordNotFound;
                }
            }
        }
    }

    //;

    pub fn bye(self: *Self) Error!void {
        self.should_stop_interpreting = true;
    }

    pub fn here(self: *Self) Error!void {
        try self.push(@ptrToInt(self.here));
    }

    pub fn dup(self: *Self) Error!void {
        const a = try self.pop();
        try self.push(a);
        try self.push(a);
    }

    pub fn over(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(b);
        try self.push(a);
        try self.push(b);
    }

    pub fn cell(self: *Self) Error!void {
        try self.push(@sizeOf(Cell));
    }

    pub fn plus(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(a +% b);
    }

    pub fn times(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(a *% b);
    }

    pub fn type_(self: *Self) Error!void {
        const len = try self.pop();
        const addr = try self.pop();
        std.debug.print("{}", .{stringAt(addr, len)});
    }
};

pub fn demo(allocator: *Allocator) !void {
    var vm = try VM.init(allocator);
    defer vm.deinit();

    try vm.createBuiltin("docol", 0, &VM.docol);
    vm.docol_address = VM.wordHeaderCodeFieldAddress(vm.latest.*);
    try vm.createBuiltin("lit", 0, &VM.lit);
    vm.lit_address = VM.wordHeaderCodeFieldAddress(vm.latest.*);
    try vm.createBuiltin("exit", 0, &VM.exit);
    vm.exit_address = VM.wordHeaderCodeFieldAddress(vm.latest.*);
    try vm.createBuiltin("quit", 0, &VM.quit);
    vm.quit_address = VM.wordHeaderCodeFieldAddress(vm.latest.*);

    try vm.createBuiltin("define", 0, &VM.define);
    try vm.createBuiltin("@", 0, &VM.fetch);
    try vm.createBuiltin("!", 0, &VM.store);
    try vm.createBuiltin("c@", 0, &VM.fetchByte);
    try vm.createBuiltin("c!", 0, &VM.storeByte);
    try vm.createBuiltin(",", 0, &VM.comma);
    try vm.createBuiltin("c,", 0, &VM.commaByte);
    try vm.createBuiltin("'", VM.word_immediate_flag, &VM.tick);
    try vm.createBuiltin("[", VM.word_immediate_flag, &VM.lBracket);
    try vm.createBuiltin("]", 0, &VM.rBracket);
    try vm.createBuiltin(":", 0, &VM.colon);
    try vm.createBuiltin(";", VM.word_immediate_flag, &VM.semicolon);
    try vm.createBuiltin("immediate", VM.word_immediate_flag, &VM.immediate);

    try vm.createBuiltin("bye", 0, &VM.bye);
    try vm.createBuiltin(".s", 0, &VM.showStack);
    try vm.createBuiltin("dup", 0, &VM.dup);
    try vm.createBuiltin("over", 0, &VM.over);
    try vm.createBuiltin("cell", 0, &VM.cell);
    try vm.createBuiltin("here", 0, &VM.here);
    try vm.createBuiltin("+", 0, &VM.plus);
    try vm.createBuiltin("*", 0, &VM.times);
    try vm.readInput(
        \\: ['] ' lit , ; immediate
        \\: cells cell * ;
        \\                                           \\ TODO why is this 3
        \\: create define ['] docol , ['] lit , here @ 3 cells + , ['] exit , ['] exit , ;
        \\ \\ : constant create , does> ____ ;
        \\create asdf 1234 , asdf asdf @ .s \\ comment
    );
    // try vm.readInput(": cells cell * ; : create define ' docol , ' lit , here @ 3 cells + , ' exit , ' exit , ; create asdf");
    // try vm.readInput("define asdf");
    // try vm.readInput(": hello 5 snd + ; hello .s");
    try vm.quit();

    //     try vm.createWordHeader("defined", 0);
    //     try vm.createWordHeader("next", VM.word_hidden_flag);
    //     try vm.createWordHeader("next2", VM.word_immediate_flag);
    //
    //     try vm.readInput("defined not next next2");
    //     try vm.word();
    //     vm.debugPrintStack();
    //     try vm.find();
    //     vm.debugPrintStack();
    //     try vm.word();
    //     vm.debugPrintStack();
    //     try vm.find();
    //     vm.debugPrintStack();
    //     try vm.word();
    //     vm.debugPrintStack();
    //     try vm.find();
    //     vm.debugPrintStack();
    //     try vm.word();
    //     vm.debugPrintStack();
    //     try vm.find();
    //     vm.debugPrintStack();

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
