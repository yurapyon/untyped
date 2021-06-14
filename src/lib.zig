const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

//;

// TODO
//   float stack
//   limit word len (go with 64 i guess?)
//     think its limited to 255 because len is a byte
//   instead of line_buf_len should it be a ptr to the top
//   key?
//   , and c, can be written in forth
//   find just returns t/f
//   change stle of line comments ?
//     \ is annoying, # would work
//   have a way to notify on overwrite name

// sp points to 1 beyond the top of the stack
//   should i keep it this way?
// rsp is the same

// state == forth_true in compilation state

pub const VM = struct {
    const Self = @This();

    pub const Error = error{
        // TODO
        // Misalignment
        // TODO specialize these errors per stack
        StackUnderflow,
        StackOverflow,

        ReturnStackUnderflow,
        ReturnStackOverflow,
        WordTooLong,
        NoInputBuffer,
        WordNotFound,
        EndOfInput,
        InvalidNumber,
    } || Allocator.Error;

    pub const baseLib = @embedFile("base.fs");

    // TODO make sure @sizeOf(usize) == @sizeOf(Cell)
    //                @sizeOf(Float) <= @sizeOf(Cell)
    pub const Cell = u64;
    pub const SCell = i64;
    pub const Builtin = fn (self: *Self) Error!void;
    pub const Float = f64;

    pub const forth_false: Cell = 0;
    pub const forth_true = ~forth_false;

    // TODO use doBuiltin dummy function address
    const builtin_fn_id = 0;

    const find_info_not_found = 0;
    const find_info_immediate = 1;
    const find_info_not_immediate = ~@as(Cell, 0);

    const word_immediate_flag = 0x2;
    const word_hidden_flag = 0x1;

    const mem_size = 4 * 1024 * 1024;
    const stack_size = 192 * @sizeOf(Cell);
    const rstack_size = 64 * @sizeOf(Cell);
    const fstack_size = 64 * @sizeOf(Float);
    // TODO this determines dictionary start
    //        has to be cell aligned
    const line_buf_size = 128;

    const latest_pos = 0 * @sizeOf(Cell);
    const here_pos = 1 * @sizeOf(Cell);
    const base_pos = 2 * @sizeOf(Cell);
    const state_pos = 3 * @sizeOf(Cell);
    const sp_pos = 4 * @sizeOf(Cell);
    const rsp_pos = 5 * @sizeOf(Cell);
    const fsp_pos = 6 * @sizeOf(Cell);
    const line_buf_len_pos = 7 * @sizeOf(Cell);
    const stack_start = 8 * @sizeOf(Cell);
    const rstack_start = stack_start + stack_size;
    const fstack_start = rstack_start + rstack_size;
    const line_buf_start = fstack_start + fstack_size;
    const dictionary_start = line_buf_start + line_buf_size;

    pub const ParseNumberResult = union(enum) {
        Float: Float,
        Cell: Cell,
    };

    allocator: *Allocator,
    last_input: ?[]u8,
    input_at: usize,

    // execution
    last_ip: Cell,
    next: Cell,
    exec_cfa: Cell,
    exec_cmd: Cell,

    lit_address: Cell,
    litFloat_address: Cell,
    quit_address: Cell,
    should_stop_interpreting: bool,

    mem: []u8,
    latest: *Cell,
    here: *Cell,
    base: *Cell,
    state: *Cell,
    sp: *Cell,
    rsp: *Cell,
    fsp: *Cell,
    line_buf_len: *Cell,
    stack: [*]Cell,
    rstack: [*]Cell,
    fstack: [*]Float,
    line_buf: [*]u8,
    dictionary: [*]u8,

    pub fn init(allocator: *Allocator) Error!Self {
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
        ret.fsp = @ptrCast(*Cell, @alignCast(@alignOf(Cell), &ret.mem[fsp_pos]));
        ret.line_buf_len = @ptrCast(*Cell, @alignCast(@alignOf(Cell), &ret.mem[line_buf_len_pos]));
        ret.stack = @ptrCast([*]Cell, @alignCast(@alignOf(Cell), &ret.mem[stack_start]));
        ret.rstack = @ptrCast([*]Cell, @alignCast(@alignOf(Cell), &ret.mem[rstack_start]));
        ret.fstack = @ptrCast([*]Float, @alignCast(@alignOf(Cell), &ret.mem[fstack_start]));
        ret.line_buf = @ptrCast([*]u8, &ret.mem[line_buf_start]);
        ret.dictionary = @ptrCast([*]u8, &ret.mem[dictionary_start]);

        // init vars
        ret.latest.* = 0;
        ret.here.* = @ptrToInt(ret.dictionary);
        ret.base.* = 10;
        ret.state.* = forth_false;
        ret.sp.* = @ptrToInt(ret.stack);
        ret.rsp.* = @ptrToInt(ret.rstack);
        ret.fsp.* = @ptrToInt(ret.fstack);
        ret.line_buf_len.* = 0;

        // TODO make all this catch unreachable
        try ret.initBuiltins();
        try ret.readInput(baseLib);
        try ret.quit();

        return ret;
    }

    pub fn deinit(self: *Self) void {
        if (self.last_input) |input| {
            self.allocator.free(input);
        }
        self.allocator.free(self.mem);
    }

    fn initBuiltins(self: *Self) Error!void {
        try self.createBuiltin("lit", 0, &lit);
        self.lit_address = wordHeaderCodeFieldAddress(self.latest.*);
        try self.createBuiltin("litfloat", 0, &litFloat);
        self.litFloat_address = wordHeaderCodeFieldAddress(self.latest.*);
        try self.createBuiltin("quit", 0, &quit);
        self.quit_address = wordHeaderCodeFieldAddress(self.latest.*);

        try self.createBuiltin("mem", 0, &memStart);
        try self.createBuiltin("mem-size", 0, &memSize);
        try self.createBuiltin("dictionary", 0, &dictionaryStart);
        try self.createBuiltin("state", 0, &state);
        try self.createBuiltin("latest", 0, &latest);
        try self.createBuiltin("here", 0, &here);
        try self.createBuiltin("base", 0, &base);
        try self.createBuiltin("s0", 0, &s0);
        try self.createBuiltin("sp", 0, &sp);
        try self.createBuiltin("sp@", 0, &spFetch);
        try self.createBuiltin("sp!", 0, &spStore);
        try self.createBuiltin("rs0", 0, &rs0);
        try self.createBuiltin("rsp", 0, &rsp);
        try self.createBuiltin("fs0", 0, &fs0);
        try self.createBuiltin("fsp", 0, &fsp);

        try self.createBuiltin("dup", 0, &dup);
        try self.createBuiltin("?dup", 0, &dupMaybe);
        try self.createBuiltin("drop", 0, &drop);
        try self.createBuiltin("swap", 0, &swap);
        try self.createBuiltin("over", 0, &over);
        try self.createBuiltin("tuck", 0, &tuck);
        try self.createBuiltin("nip", 0, &nip);
        try self.createBuiltin("rot", 0, &rot);
        try self.createBuiltin("-rot", 0, &nrot);
        try self.createBuiltin("pick", 0, &pick);
        try self.createBuiltin("2swap", 0, &swap2);

        try self.createBuiltin(">R", 0, &toR);
        try self.createBuiltin("R>", 0, &fromR);
        try self.createBuiltin("R@", 0, &rFetch);
        // TODO 2r> 2>r

        try self.createBuiltin("docol", 0, &docol);
        try self.createBuiltin("exit", 0, &exit);
        try self.createBuiltin("define", 0, &define);
        try self.createBuiltin("word", 0, &word);
        try self.createBuiltin("find", 0, &find);
        try self.createBuiltin("@", 0, &fetch);
        try self.createBuiltin("!", 0, &store);
        try self.createBuiltin("c@", 0, &fetchByte);
        try self.createBuiltin("c!", 0, &storeByte);
        try self.createBuiltin(",", 0, &comma);
        try self.createBuiltin("c,", 0, &commaByte);
        try self.createBuiltin("'", 0, &tick);
        try self.createBuiltin("[']", word_immediate_flag, &bracketTick);
        try self.createBuiltin("[", word_immediate_flag, &lBracket);
        try self.createBuiltin("]", 0, &rBracket);

        try self.createBuiltin("flag,immediate", 0, &immediateFlag);
        try self.createBuiltin("flag,hidden", 0, &hiddenFlag);
        try self.createBuiltin("make-immediate", 0, &makeImmediate);
        try self.createBuiltin("hide", 0, &hide);

        try self.createBuiltin(">cfa", 0, &cfa_);
        try self.createBuiltin("branch", 0, &branch);
        try self.createBuiltin("0branch", 0, &zbranch);

        try self.createBuiltin("bye", 0, &bye);
        // TODO interpret
        try self.createBuiltin("execute", 0, &execute);

        try self.createBuiltin("true", 0, &true_);
        try self.createBuiltin("false", 0, &false_);
        try self.createBuiltin("=", 0, &equal);
        try self.createBuiltin("<>", 0, &notEqual);
        try self.createBuiltin("<", 0, &lt);
        try self.createBuiltin(">", 0, &gt);
        try self.createBuiltin("u<", 0, &ult);
        try self.createBuiltin("u>", 0, &ugt);
        try self.createBuiltin("and", 0, &and_);
        try self.createBuiltin("or", 0, &or_);
        try self.createBuiltin("xor", 0, &xor);
        try self.createBuiltin("invert", 0, &invert);
        try self.createBuiltin("lshift", 0, &lshift);
        try self.createBuiltin("rshift", 0, &rshift);

        try self.createBuiltin("+", 0, &plus);
        try self.createBuiltin("-", 0, &minus);
        try self.createBuiltin("*", 0, &times);
        try self.createBuiltin("/mod", 0, &divMod);
        try self.createBuiltin("cell", 0, &cell);
        // try self.createBuiltin("number", 0, &number);

        try self.createBuiltin(".s", 0, &showStack);

        try self.createBuiltin("litstring", 0, &litString);
        try self.createBuiltin("type", 0, &type_);
        try self.createBuiltin("key", 0, &key);
        try self.createBuiltin("char", 0, &char);
        try self.createBuiltin("emit", 0, &emit);

        try self.createBuiltin("allocate", 0, &allocate);
        try self.createBuiltin("free", 0, &free);
        // TODO resize
        try self.createBuiltin("cmove>", 0, &cmoveUp);
        try self.createBuiltin("cmove<", 0, &cmoveDown);

        try self.createBuiltin("f.", 0, &printFloat);
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
        if (self.sp.* >= @ptrToInt(self.stack) + stack_size) {
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
        if (self.rsp.* >= @ptrToInt(self.rstack) + rstack_size) {
            return error.StackOverflow;
        }
        @intToPtr(*Cell, self.rsp.*).* = val;
        self.rsp.* += @sizeOf(Cell);
    }

    pub fn fpop(self: *Self) Error!Float {
        if (self.fsp.* <= @ptrToInt(self.fstack)) {
            return error.StackUnderflow;
        }
        self.fsp.* -= @sizeOf(Float);
        const ret = @intToPtr(*const Float, self.fsp.*).*;
        return ret;
    }

    pub fn fpush(self: *Self, val: Float) Error!void {
        if (self.fsp.* >= @ptrToInt(self.fstack) + fstack_size) {
            return error.StackOverflow;
        }
        @intToPtr(*Float, self.fsp.*).* = val;
        self.fsp.* += @sizeOf(Float);
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

    // TODO
    // for read/write cell
    //   put alignment error in VM.Error ?
    //   probably yeah,
    //   instead of getting segfaults for things accidentally left on rstack, will be alignment error

    pub fn checkedReadCell(self: *Self, addr: Cell) Error!Cell {
        return @intToPtr(*const Cell, addr).*;
    }

    pub fn checkedReadByte(self: *Self, addr: Cell) Error!u8 {
        return @intToPtr(*const u8, addr).*;
    }

    pub fn checkedWriteCell(self: *Self, addr: Cell, val: Cell) Error!void {
        @intToPtr(*Cell, addr).* = val;
    }

    pub fn checkedWriteByte(self: *Self, addr: Cell, val: u8) Error!void {
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

    pub fn readNextChar(self: *Self) Error!u8 {
        if (self.last_input) |input| {
            if (self.input_at >= input.len) {
                return error.EndOfInput;
            }

            const ch = input[self.input_at];
            self.input_at += 1;
            return ch;
        } else {
            return error.NoInputBuffer;
        }
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
                return error.EndOfInput;
            }

            ch = input[self.input_at];

            if (ch == ' ' or ch == '\n') {
                self.input_at += 1;
                continue;
            } else if (ch == '\\') {
                while (true) {
                    if (self.input_at >= input.len) {
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

    // TODO rename/refactor somehow
    // slice at
    pub fn stringAt(addr: Cell, len: Cell) []u8 {
        var str: []u8 = undefined;
        str.ptr = @intToPtr([*]u8, addr);
        str.len = len;
        return str;
    }

    pub fn alignAddr(comptime T: type, addr: Cell) Cell {
        const off_aligned = @alignOf(T) - (addr % @alignOf(T));
        return if (off_aligned == @alignOf(T)) addr else addr + off_aligned;
    }

    pub fn parseNumber(str: []const u8, base_: Cell) Error!ParseNumberResult {
        var is_negative = false;
        var acc: Cell = 0;
        var read_at: usize = 0;

        if (str[str.len - 1] == 'f') {
            // dont allow f
            if (str.len == 1) {
                return error.InvalidNumber;
            }
            // only allow 0-9 - .
            for (str[0..(str.len - 1)]) |ch| {
                switch (ch) {
                    '0'...'9', '.', '+', '-' => {},
                    else => return error.InvalidNumber,
                }
            }
            // dont allow .f +f -f
            if (str.len == 2 and
                (str[0] == '.' or str[0] == '+' or str[0] == '-'))
            {
                return error.InvalidNumber;
            }

            const fl = std.fmt.parseFloat(Float, str[0..(str.len - 1)]) catch |_| {
                return error.InvalidNumber;
            };
            return ParseNumberResult{ .Float = fl };
        }

        if (str[0] == '-') {
            is_negative = true;
            read_at += 1;
        } else if (str[0] == '+') {
            read_at += 1;
        }

        while (read_at < str.len) : (read_at += 1) {
            const ch = str[read_at];
            const digit = switch (ch) {
                '0'...'9' => ch - '0',
                'A'...'Z' => ch - 'A' + 10,
                'a'...'z' => ch - 'a' + 10,
                else => return error.InvalidNumber,
            };
            if (digit > base_) return error.InvalidNumber;
            acc = acc * base_ + digit;
        }

        return ParseNumberResult{ .Cell = if (is_negative) 0 -% acc else acc };
    }

    pub fn pushString(self: *Self, str: []const u8) Error!void {
        try self.push(@ptrToInt(str.ptr));
        try self.push(str.len);
    }

    //;

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
        self.here.* = alignAddr(Cell, self.here.*);
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
        return alignAddr(Cell, name_end_addr);
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

        if (check == 0) {
            return error.WordNotFound;
        } else {
            return check;
        }
    }

    // builtins

    pub fn lit(self: *Self) Error!void {
        try self.push(try self.checkedReadCell(self.next));
        self.next += @sizeOf(Cell);
    }

    pub fn quit(self: *Self) Error!void {
        self.rsp.* = @ptrToInt(self.rstack);
        // TODO do i need to explicitly call interpret
        try self.interpret();
    }

    //;

    pub fn memStart(self: *Self) Error!void {
        try self.push(@ptrToInt(self.mem.ptr));
    }

    pub fn memSize(self: *Self) Error!void {
        try self.push(mem_size);
    }

    pub fn dictionaryStart(self: *Self) Error!void {
        try self.push(@ptrToInt(self.dictionary));
    }

    pub fn state(self: *Self) Error!void {
        try self.push(@ptrToInt(self.state));
    }

    pub fn latest(self: *Self) Error!void {
        try self.push(@ptrToInt(self.latest));
    }

    pub fn here(self: *Self) Error!void {
        try self.push(@ptrToInt(self.here));
    }

    pub fn base(self: *Self) Error!void {
        try self.push(@ptrToInt(self.base));
    }

    pub fn s0(self: *Self) Error!void {
        try self.push(@ptrToInt(self.stack));
    }

    pub fn sp(self: *Self) Error!void {
        try self.push(@ptrToInt(self.sp));
    }

    pub fn spFetch(self: *Self) Error!void {
        try self.push(self.sp.*);
    }

    pub fn spStore(self: *Self) Error!void {
        const val = try self.pop();
        self.sp.* = val;
    }

    pub fn rs0(self: *Self) Error!void {
        try self.push(@ptrToInt(self.rstack));
    }

    pub fn rsp(self: *Self) Error!void {
        try self.push(@ptrToInt(self.rsp));
    }

    pub fn fs0(self: *Self) Error!void {
        try self.push(@ptrToInt(self.fstack));
    }

    pub fn fsp(self: *Self) Error!void {
        try self.push(@ptrToInt(self.fsp));
    }

    //;

    pub fn dup(self: *Self) Error!void {
        const a = try self.pop();
        try self.push(a);
        try self.push(a);
    }

    pub fn dupMaybe(self: *Self) Error!void {
        const a = try self.pop();
        try self.push(a);
        if (a != forth_false) {
            try self.push(a);
        }
    }

    pub fn drop(self: *Self) Error!void {
        _ = try self.pop();
    }

    pub fn swap(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(a);
        try self.push(b);
    }

    pub fn over(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(b);
        try self.push(a);
        try self.push(b);
    }

    pub fn tuck(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(a);
        try self.push(b);
        try self.push(a);
    }

    pub fn nip(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(a);
    }

    // c b a > b a c
    pub fn rot(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        const c = try self.pop();
        try self.push(b);
        try self.push(a);
        try self.push(c);
    }

    // c b a > a c b
    pub fn nrot(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        const c = try self.pop();
        try self.push(a);
        try self.push(c);
        try self.push(b);
    }

    pub fn pick(self: *Self) Error!void {
        const at = try self.pop();
        const tos = self.sp.*;
        const offset = (1 + at) * @sizeOf(Cell);
        try self.push(try self.checkedReadCell(tos - offset));
    }

    pub fn swap2(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        const c = try self.pop();
        const d = try self.pop();
        try self.push(b);
        try self.push(a);
        try self.push(d);
        try self.push(c);
    }

    //;

    pub fn toR(self: *Self) Error!void {
        try self.rpush(try self.pop());
    }

    pub fn fromR(self: *Self) Error!void {
        try self.push(try self.rpop());
    }

    pub fn rFetch(self: *Self) Error!void {
        try self.push(try self.checkedReadCell(self.rsp.* - @sizeOf(Cell)));
    }

    //;

    pub fn docol(self: *Self) Error!void {
        try self.rpush(self.last_ip);
        self.next = self.exec_cfa + @sizeOf(Cell);
    }

    pub fn exit(self: *Self) Error!void {
        self.next = try self.rpop();
    }

    pub fn define(self: *Self) Error!void {
        const len = try self.pop();
        const addr = try self.pop();
        if (len == 0) {
            try self.createWordHeader("", 0);
        } else {
            try self.createWordHeader(stringAt(addr, len), 0);
        }
    }

    // note:
    //   the next word you read after calling 'word' messes with the line_buf
    //   word doesnt really work ehn interpreting
    //   could maybe be fixed by double buffering
    pub fn word(self: *Self) Error!void {
        const len = try self.readNextWord();
        try self.push(@ptrToInt(self.line_buf));
        try self.push(len);
    }

    pub fn find(self: *Self) Error!void {
        const len = try self.pop();
        const addr = try self.pop();
        const ret = self.findWord(addr, len) catch |err| {
            switch (err) {
                error.WordNotFound => {
                    try self.push(addr);
                    try self.push(find_info_not_found);
                    return;
                },
                else => return err,
            }
        };

        const flags = wordHeaderFlags(ret);
        const is_immediate = (flags & word_immediate_flag) != 0;
        try self.push(ret);
        try self.push(if (is_immediate) find_info_immediate else find_info_not_immediate);
    }

    pub fn fetch(self: *Self) Error!void {
        const addr = try self.pop();
        try self.push(try self.checkedReadCell(addr));
    }

    pub fn store(self: *Self) Error!void {
        const addr = try self.pop();
        const val = try self.pop();
        try self.checkedWriteCell(addr, val);
    }

    pub fn fetchByte(self: *Self) Error!void {
        const addr = try self.pop();
        try self.push(try self.checkedReadByte(addr));
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

    pub fn tick(self: *Self) Error!void {
        try self.word();
        try self.find();
        if ((try self.pop()) == find_info_not_found) {
            return error.WordNotFound;
        }
        try self.cfa_();
    }

    pub fn bracketTick(self: *Self) Error!void {
        try self.tick();
        try self.push(self.lit_address);
        try self.comma();
        try self.comma();
    }

    pub fn lBracket(self: *Self) Error!void {
        self.state.* = forth_false;
    }

    pub fn rBracket(self: *Self) Error!void {
        self.state.* = forth_true;
    }

    pub fn immediateFlag(self: *Self) Error!void {
        try self.push(word_immediate_flag);
    }

    pub fn hiddenFlag(self: *Self) Error!void {
        try self.push(word_hidden_flag);
    }

    pub fn makeImmediate(self: *Self) Error!void {
        const addr = try self.pop();
        const flags = wordHeaderFlags(addr);
        wordHeaderSetFlags(self.latest.*, flags ^ word_immediate_flag);
    }

    pub fn hide(self: *Self) Error!void {
        const addr = try self.pop();
        const flags = wordHeaderFlags(addr);
        wordHeaderSetFlags(addr, flags ^ word_hidden_flag);
    }

    pub fn cfa_(self: *Self) Error!void {
        const addr = try self.pop();
        try self.push(wordHeaderCodeFieldAddress(addr));
    }

    pub fn branch(self: *Self) Error!void {
        self.next +%= try self.checkedReadCell(self.next);
    }

    pub fn zbranch(self: *Self) Error!void {
        if ((try self.pop()) == forth_false) {
            self.next +%= try self.checkedReadCell(self.next);
        } else {
            self.next += @sizeOf(Cell);
        }
    }

    //;

    // TODO move up
    pub fn executeCfa(self: *Self, cfa: Cell) Error!void {
        self.last_ip = self.quit_address;
        self.next = self.quit_address;
        self.exec_cfa = cfa;
        self.exec_cmd = cfa;
        while (!self.should_stop_interpreting) {
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

    pub fn bye(self: *Self) Error!void {
        self.should_stop_interpreting = true;
    }

    pub fn interpret(self: *Self) Error!void {
        while (!self.should_stop_interpreting) {
            const is_compiling = self.state.* != forth_false;

            self.word() catch |err| switch (err) {
                error.EndOfInput => {
                    self.should_stop_interpreting = true;
                    break;
                },
                else => return err,
            };
            self.input_at += 1;
            try self.find();

            const find_info = try self.pop();
            const addr = try self.pop();
            if (find_info != find_info_not_found) {
                const flags = wordHeaderFlags(addr);
                const is_immediate = (flags & word_immediate_flag) != 0;
                const cfa = wordHeaderCodeFieldAddress(addr);
                if (is_compiling and !is_immediate) {
                    try self.push(cfa);
                    try self.comma();
                } else {
                    try self.executeCfa(cfa);
                }
            } else {
                // note: assumes self.word() reads into line_buf
                //   and that that isnt changed by the time you get here
                var str: []const u8 = undefined;
                str.ptr = self.line_buf;
                str.len = self.line_buf_len.*;
                const maybe_num = parseNumber(str, self.base.*) catch null;
                if (maybe_num) |num| {
                    if (is_compiling) {
                        switch (num) {
                            .Cell => |c| {
                                try self.push(self.lit_address);
                                try self.comma();
                                try self.push(c);
                                try self.comma();
                            },
                            .Float => |f| {
                                try self.push(self.litFloat_address);
                                try self.comma();
                                try self.push(floatToCell(f));
                                try self.comma();
                            },
                        }
                    } else {
                        switch (num) {
                            .Cell => |c| try self.push(c),
                            .Float => |f| try self.fpush(f),
                        }
                    }
                } else {
                    std.debug.print("word not found: '{}'\n", .{str});
                    return error.WordNotFound;
                }
            }
        }
    }

    pub fn execute(self: *Self) Error!void {
        const addr = try self.pop();
        const prev_next = self.next;
        try self.executeCfa(addr);
        self.next = prev_next;
    }

    //;

    pub fn true_(self: *Self) Error!void {
        try self.push(forth_true);
    }

    pub fn false_(self: *Self) Error!void {
        try self.push(forth_false);
    }

    pub fn equal(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(if (a == b) forth_true else forth_false);
    }

    pub fn notEqual(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(if (a != b) forth_true else forth_false);
    }

    pub fn lt(self: *Self) Error!void {
        const a = @bitCast(SCell, try self.pop());
        const b = @bitCast(SCell, try self.pop());
        try self.push(if (b < a) forth_true else forth_false);
    }

    pub fn gt(self: *Self) Error!void {
        const a = @bitCast(SCell, try self.pop());
        const b = @bitCast(SCell, try self.pop());
        try self.push(if (b > a) forth_true else forth_false);
    }

    pub fn ult(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(if (b < a) forth_true else forth_false);
    }

    pub fn ugt(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(if (b > a) forth_true else forth_false);
    }

    pub fn and_(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(a & b);
    }

    pub fn or_(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(a | b);
    }

    pub fn xor(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(a ^ b);
    }

    pub fn invert(self: *Self) Error!void {
        const a = try self.pop();
        try self.push(~a);
    }

    pub fn lshift(self: *Self) Error!void {
        const ct = try self.pop();
        const a = try self.pop();
        try self.push(a >> @intCast(u6, ct & 0x3f));
    }

    pub fn rshift(self: *Self) Error!void {
        const ct = try self.pop();
        const a = try self.pop();
        try self.push(a << @intCast(u6, ct & 0x3f));
    }

    //;

    pub fn plus(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(a +% b);
    }

    pub fn minus(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(b -% a);
    }

    pub fn times(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(a *% b);
    }

    pub fn divMod(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        const q = b / a;
        const mod = b % a;
        try self.push(mod);
        try self.push(q);
    }

    pub fn cell(self: *Self) Error!void {
        try self.push(@sizeOf(Cell));
    }

    // TODO do this according to forth specs
    //      handle floats
    // pub fn number(self: *Self) Error!void {
    // const len = try self.pop();
    // const addr = try self.pop();
    // try self.push(try parseNumber(stringAt(addr, len), self.base.*));
    // }

    //;

    pub fn showStack(self: *Self) Error!void {
        self.debugPrintStack();
    }

    //;

    pub fn litString(self: *Self) Error!void {
        const len = try self.checkedReadCell(self.next);
        self.next += @sizeOf(Cell);
        try self.push(self.next);
        try self.push(len);
        self.next += len;
        self.next = alignAddr(Cell, self.next);
    }

    pub fn type_(self: *Self) Error!void {
        const len = try self.pop();
        const addr = try self.pop();
        std.debug.print("{}", .{stringAt(addr, len)});
    }

    pub fn key(self: *Self) Error!void {
        const ch = try self.readNextChar();
        try self.push(ch);
    }

    pub fn char(self: *Self) Error!void {
        try self.word();
        const len = try self.pop();
        const addr = try self.pop();
        try self.push(stringAt(addr, len)[0]);
    }

    pub fn emit(self: *Self) Error!void {
        std.debug.print("{c}", .{@intCast(u8, (try self.pop()) & 0xff)});
    }

    //;

    pub fn allocate(self: *Self) Error!void {
        const size = try self.pop();
        var mem = self.allocator.allocWithOptions(
            u8,
            size + @sizeOf(Cell),
            @alignOf(Cell),
            null,
        ) catch |err| {
            switch (err) {
                error.OutOfMemory => {
                    try self.push(0);
                    try self.push(forth_false);
                    return;
                },
            }
        };
        const size_ptr = @ptrCast(*Cell, @alignCast(@alignOf(Cell), mem.ptr));
        size_ptr.* = size;
        const data_ptr = mem.ptr + @sizeOf(Cell);
        try self.push(@ptrToInt(data_ptr));
        try self.push(forth_true);
    }

    pub fn free(self: *Self) Error!void {
        const addr = try self.pop();
        const data_ptr = @intToPtr([*]u8, addr);
        const mem_ptr = data_ptr - @sizeOf(Cell);
        const size_ptr = @ptrCast(*Cell, @alignCast(@alignOf(Cell), mem_ptr));
        var mem: []u8 = undefined;
        mem.ptr = mem_ptr;
        mem.len = size_ptr.*;
        self.allocator.free(mem);
    }

    pub fn cmoveUp(self: *Self) Error!void {
        const dest = @intToPtr([*]u8, try self.pop());
        const len = try self.pop();
        const src = @intToPtr([*]u8, try self.pop());
        {
            @setRuntimeSafety(false);
            var i: usize = 0;
            while (i < len) : (i += 1) {
                dest[i] = src[i];
            }
        }
    }

    pub fn cmoveDown(self: *Self) Error!void {
        const dest = @intToPtr([*]u8, try self.pop());
        const len = try self.pop();
        const src = @intToPtr([*]u8, try self.pop());
        {
            @setRuntimeSafety(false);
            var i: usize = len - 1;
            while (i >= len) : (i -= 1) {
                dest[i] = src[i];
            }
        }
    }

    // ===

    pub fn floatToCell(f: Float) Cell {
        // TODO handle if @sizeOf(Float) != @sizeOf(Cell)
        return @bitCast(Cell, f);
    }

    pub fn cellToFloat(c: Cell) Float {
        return @bitCast(Float, c);
    }

    pub fn litFloat(self: *Self) Error!void {
        try self.fpush(cellToFloat(try self.checkedReadCell(self.next)));
        self.next += @sizeOf(Cell);
    }

    pub fn printFloat(self: *Self) Error!void {
        const float = try self.fpop();
        std.debug.print("{d}", .{float});
    }

    pub fn float(self: *Self) Error!void {
        try self.push(@sizeOf(Float));
    }
};
