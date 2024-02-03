const std = @import("std");
const Allocator = std.mem.Allocator;

//;

// TODO new 2024
// aligned access
// -- Error reporting / stack trace
//      "can use the return stack"
//        xt's end up on the return stack but they dont have debug info
//        when you compile something it has references to xt's not words
//       xt's could have a word_header_offset, which is 0 for anonymous
//      debug info could be stored separately from word header
//      'execution stack' could be more reliable than return stack
// -- Shell functionality
// -- CLI or terminal drawing, gfx
// dont use std.debug.print
// -- Wordlists / modules
//    useful for if youre embedding and want to do hotreloads
//      this is about adding more builtins at runtime
//        wordlists in terms of 'modules made up of forth code'
//          could probably be implemented in forth
//      dynamic linking
//      separate things into separate libs
//        float stuff
//        file r/w stuff
//        other data sizes besides cell
//      reduce number of builtins ( can do this with modules )
//    need to extend the error type
//    global data in these modules needs to be allocated within vm memory

// TODO
// have a way to notify on overwrite name
//    hashtable
//    just do find on the word name before you define
// 2c, 4c,
// base.fs, find spots where errors are ignored and abort"
//   error handling in general
//   error ( num -- ) which passes error num to zig
//     can be used with zig enums
// ptrFromInt alignment errors
// figure out how jump relates to lit, and maybe make it more general
// mods with signed ints does not work

// bye is needed twice to quit for some reason   ? is this still the case

// ===

// stack pointers point to 1 beyond the top of the stack
//   should i keep it this way?

// return_to is generally in an invalid state until the end of executing an xt
//   might work to advance it early but idt it matters

// state == forth_true in compilation state

// alignedAccess should be used anywhere the address of an access can be influenced at runtime
//   which is pretty much everywhere

pub const VM = struct {
    const Self = @This();

    // TODO this can take options for memory size, float size, etc

    pub const Error = error{
        StackUnderflow,
        StackOverflow,
        StackIndexOutOfRange,

        WordTooLong,
        WordNotFound,
        InvalidNumber,
        InvalidFloat,
        ExecutionError,
        AlignmentError,

        EarlyBye,
        EndOfInput,
        Panic,
    } || Allocator.Error;

    pub const baseLib = @embedFile("base.fth");

    // TODO comptime make sure cell is u64
    pub const Cell = usize;
    pub const SCell = isize;
    pub const Builtin = fn (self: *Self) Error!void;
    pub const Float = f32;

    pub const forth_false: Cell = 0;
    pub const forth_true = ~forth_false;

    const word_max_len = std.math.maxInt(u8);
    const word_immediate_flag = 0x2;
    const word_hidden_flag = 0x1;

    const mem_size = 4 * 1024 * 1024;
    const stack_size = 192 * @sizeOf(Cell);
    const rstack_size = 64 * @sizeOf(Cell);
    // TODO these two need to be cell aligned
    const fstack_size = 64 * @sizeOf(Float);
    const input_buffer_size = 128;

    const stack_start = 0;
    const rstack_start = stack_start + stack_size;
    const fstack_start = rstack_start + rstack_size;
    const input_buffer_start = fstack_start + fstack_size;
    const dictionary_start = input_buffer_start + input_buffer_size;
    const dictionary_size = mem_size - dictionary_start;

    const file_read_flag = 0x1;
    const file_write_flag = 0x2;

    pub const XtType = enum(Cell) {
        zig,
        forth,
    };

    pub fn alignedAccess(comptime T: type, addr: Cell) !*T {
        if (addr % @alignOf(T) != 0) return error.AlignmentError;
        return @ptrFromInt(addr);
    }

    pub fn Stack(comptime T: type, comptime size: usize) type {
        return struct {
            const StackSelf = @This();

            stack: [*]T,
            top: Cell,

            pub fn init(self: *StackSelf, ptr: [*]T) void {
                self.stack = ptr;
                self.top = @intFromPtr(ptr);
            }

            pub fn clear(self: *StackSelf) void {
                self.top = @intFromPtr(self.stack);
            }

            pub fn depth(self: *StackSelf) usize {
                return (self.top - @intFromPtr(self.stack)) / @sizeOf(T);
            }

            pub fn toSlice(self: *StackSelf) []T {
                var ret: []T = undefined;
                ret.ptr = self.stack;
                ret.len = self.depth();
                return ret;
            }

            pub fn pop(self: *StackSelf) Error!T {
                if (self.top <= @intFromPtr(self.stack)) {
                    return error.StackUnderflow;
                }
                self.top -= @sizeOf(T);
                const ptr = try alignedAccess(T, self.top);
                return ptr.*;
            }

            pub fn push(self: *StackSelf, val: T) Error!void {
                if (self.top >= @intFromPtr(self.stack) + size) {
                    return error.StackOverflow;
                }
                const ptr = try alignedAccess(T, self.top);
                ptr.* = val;
                self.top += @sizeOf(T);
            }

            pub fn index(self: *const StackSelf, idx: Cell) Error!T {
                const addr = self.top - (idx + 1) * @sizeOf(T);
                if (addr < @intFromPtr(self.stack)) {
                    return error.StackIndexOutOfRange;
                }
                const ptr = try alignedAccess(T, addr);
                return ptr.*;
            }

            // Forth words

            pub fn s0(self: *StackSelf) Cell {
                return @intFromPtr(self.stack);
            }

            pub fn sp(self: *StackSelf) Cell {
                return @intFromPtr(&self.top);
            }

            pub fn dup(self: *StackSelf) Error!void {
                const a = try self.pop();
                try self.push(a);
                try self.push(a);
            }

            pub fn drop(self: *StackSelf) Error!void {
                _ = try self.pop();
            }

            pub fn swap(self: *StackSelf) Error!void {
                const a = try self.pop();
                const b = try self.pop();
                try self.push(a);
                try self.push(b);
            }

            pub fn over(self: *StackSelf) Error!void {
                const a = try self.pop();
                const b = try self.pop();
                try self.push(b);
                try self.push(a);
                try self.push(b);
            }

            pub fn tuck(self: *StackSelf) Error!void {
                const a = try self.pop();
                const b = try self.pop();
                try self.push(a);
                try self.push(b);
                try self.push(a);
            }

            pub fn nip(self: *StackSelf) Error!void {
                const a = try self.pop();
                _ = try self.pop();
                try self.push(a);
            }

            // c b a > b a c
            pub fn rot(self: *StackSelf) Error!void {
                const a = try self.pop();
                const b = try self.pop();
                const c = try self.pop();
                try self.push(b);
                try self.push(a);
                try self.push(c);
            }

            // c b a > a c b
            pub fn nrot(self: *StackSelf) Error!void {
                const a = try self.pop();
                const b = try self.pop();
                const c = try self.pop();
                try self.push(a);
                try self.push(c);
                try self.push(b);
            }

            pub fn pick(self: *StackSelf, at: usize) Error!void {
                const tos = self.top;
                const offset = (1 + at) * @sizeOf(T);
                const value = @as(*T, @ptrFromInt(tos - offset)).*;
                try self.push(value);
            }

            pub fn swap2(self: *StackSelf) Error!void {
                const a = try self.pop();
                const b = try self.pop();
                const c = try self.pop();
                const d = try self.pop();
                try self.push(b);
                try self.push(a);
                try self.push(d);
                try self.push(c);
            }
        };
    }

    pub const DStack = Stack(Cell, stack_size);
    pub const RStack = Stack(Cell, rstack_size);
    pub const FStack = Stack(Float, fstack_size);

    pub const Dictionary = struct {
        const DictionarySelf = @This();

        memory: []u8,
        latest: Cell,
        here: Cell,

        pub fn init(self: *DictionarySelf, memory: []u8, latest_: Cell) void {
            self.memory = memory;
            self.latest = latest_;
            self.here = @intFromPtr(self.memory.ptr);
        }
    };

    allocator: Allocator,

    // execution
    return_to: Cell,
    should_bye: bool,
    should_quit: bool,

    lit_address: Cell,
    litFloat_address: Cell,
    quit_address: Cell,

    mem: []u8,
    base: Cell,
    state: Cell,

    source_user_input: Cell,
    source_ptr: Cell,
    source_len: Cell,
    source_in: Cell,

    stack: DStack,
    rstack: RStack,
    fstack: FStack,
    input_buffer: [*]u8,

    main_dictionary: Dictionary,
    current_dictionary: *Dictionary,

    word_not_found: []u8,

    pub fn init(self: *Self, allocator: Allocator) Error!void {
        self.allocator = allocator;
        self.return_to = 0;

        self.mem = try allocator.allocWithOptions(u8, mem_size, @alignOf(WordHeader), null);
        self.stack.init(@ptrCast(@alignCast(&self.mem[stack_start])));
        self.rstack.init(@ptrCast(@alignCast(&self.mem[rstack_start])));
        self.fstack.init(@ptrCast(@alignCast(&self.mem[fstack_start])));
        self.input_buffer = @ptrCast(&self.mem[input_buffer_start]);

        self.main_dictionary.init(self.mem[dictionary_start..], 0);
        self.current_dictionary = &self.main_dictionary;

        // init vars
        self.base = 10;
        self.state = forth_false;

        try self.initBuiltins();
        self.interpretBuffer(baseLib) catch |err| switch (err) {
            error.WordNotFound => {
                std.debug.print("word not found: {s}\n", .{self.word_not_found});
                return err;
            },
            else => return err,
        };

        self.source_user_input = forth_true;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.mem);
    }

    fn initBuiltins(self: *Self) Error!void {
        // TODO rename forth-fn-id, forth-word-id or something idk
        try self.createBuiltin("forth-fn-id", 0, &forthFnId);
        try self.createBuiltin("exit", 0, &exit_);
        try self.createBuiltin("lit", 0, &lit);
        {
            const header: *const WordHeader = @ptrFromInt(self.current_dictionary.latest);
            self.lit_address = header.getCfa();
        }
        try self.createBuiltin("litfloat", 0, &litFloat);
        {
            const header: *const WordHeader = @ptrFromInt(self.current_dictionary.latest);
            self.litFloat_address = header.getCfa();
        }
        try self.createBuiltin("execute", 0, &executeForth);
        try self.createBuiltin("quit", 0, &quit);
        {
            const header: *const WordHeader = @ptrFromInt(self.current_dictionary.latest);
            self.quit_address = header.getCfa();
        }
        try self.createBuiltin("bye", 0, &bye);

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

        try self.createBuiltin(">r", 0, &toR);
        try self.createBuiltin("r>", 0, &fromR);
        try self.createBuiltin("r@", 0, &rFetch);

        try self.createBuiltin("define", 0, &define);
        try self.createBuiltin("word", 0, &word);
        try self.createBuiltin("next-char", 0, &nextCharForth);
        try self.createBuiltin("find", 0, &find);
        try self.createBuiltin("@", 0, &fetch);
        try self.createBuiltin("!", 0, &store);
        try self.createBuiltin(",", 0, &comma);
        try self.createBuiltin("c@", 0, &fetchByte);
        try self.createBuiltin("c!", 0, &storeByte);
        try self.createBuiltin("c,", 0, &commaByte);
        try self.createBuiltin("'", 0, &tick);
        try self.createBuiltin("[']", word_immediate_flag, &bracketTick);
        try self.createBuiltin("[", word_immediate_flag, &lBracket);
        try self.createBuiltin("]", 0, &rBracket);

        try self.createBuiltin("flag,immediate", 0, &immediateFlag);
        try self.createBuiltin("flag,hidden", 0, &hiddenFlag);
        try self.createBuiltin("make-immediate", 0, &makeImmediate);
        try self.createBuiltin("hide", 0, &hide);

        try self.createBuiltin(">cfa", 0, &getCfa);
        try self.createBuiltin("branch", 0, &branch);
        try self.createBuiltin("0branch", 0, &zbranch);
        try self.createBuiltin("jump", 0, &jump);
        try self.createBuiltin("nop", 0, &nop);

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
        try self.createBuiltin("u/mod", 0, &uDivMod);
        try self.createBuiltin("cell", 0, &cell);
        try self.createBuiltin(">number", 0, &parseNumberForth);
        try self.createBuiltin("+!", 0, &plusStore);

        try self.createBuiltin(".s-debug", 0, &showStack);

        try self.createBuiltin("litstring", 0, &litString);
        try self.createBuiltin("type", 0, &type_);
        // try self.createBuiltin("key", 0, &key);
        // try self.createBuiltin("key?", 0, &keyAvailable);
        try self.createBuiltin("char", 0, &char);
        try self.createBuiltin("emit", 0, &emit);

        try self.createBuiltin("allocate", 0, &allocate);
        try self.createBuiltin("free", 0, &free_);
        // TODO mem resize word
        try self.createBuiltin("cmove>", 0, &cmoveUp);
        try self.createBuiltin("cmove<", 0, &cmoveDown);
        try self.createBuiltin("mem=", 0, &memEql);

        // TODO float equality/epsilon
        //      i think pi and tau could be fconstants in forth
        try self.createBuiltin("f.", 0, &fPrint);
        try self.createBuiltin("f+", 0, &fPlus);
        try self.createBuiltin("f-", 0, &fMinus);
        try self.createBuiltin("f*", 0, &fTimes);
        try self.createBuiltin("f/", 0, &fDivide);
        try self.createBuiltin("float", 0, &fSize);
        try self.createBuiltin("fsin", 0, &fSin);
        try self.createBuiltin("pi", 0, &pi);
        try self.createBuiltin("tau", 0, &tau);
        try self.createBuiltin("f@", 0, &fFetch);
        try self.createBuiltin("f!", 0, &fStore);
        try self.createBuiltin("f,", 0, &fComma);
        try self.createBuiltin("f+!", 0, &fPlusStore);
        try self.createBuiltin(">float", 0, &fParse);
        try self.createBuiltin("fdup", 0, &fDup);
        try self.createBuiltin("fdrop", 0, &fDrop);
        try self.createBuiltin("fswap", 0, &fSwap);
        try self.createBuiltin("fover", 0, &fOver);
        try self.createBuiltin("frot", 0, &fRot);
        try self.createBuiltin("f-rot", 0, &fNRot);
        try self.createBuiltin("fpick", 0, &fPick);
        try self.createBuiltin("f>s", 0, &fToS);
        try self.createBuiltin("s>f", 0, &sToF);
        try self.createBuiltin("f<", 0, &flt);
        try self.createBuiltin("f>", 0, &fgt);
        try self.createBuiltin(".fs", 0, &fShowStack);
        try self.createBuiltin("ffloor", 0, &fFloor);
        try self.createBuiltin("fpow", 0, &fPow);

        try self.createBuiltin("r/o", 0, &fileRO);
        try self.createBuiltin("w/o", 0, &fileWO);
        try self.createBuiltin("r/w", 0, &fileRW);
        try self.createBuiltin("open-file", 0, &fileOpen);
        try self.createBuiltin("close-file", 0, &fileClose);
        // TODO test works
        try self.createBuiltin("reposition-file", 0, &fileReposition);
        try self.createBuiltin("file-size", 0, &fileSize);
        try self.createBuiltin("read-file", 0, &fileRead);
        try self.createBuiltin("read-line", 0, &fileReadLine);
        try self.createBuiltin("write-file", 0, &fileWrite);

        try self.createBuiltin("source-user-input", 0, &sourceUserInput);
        try self.createBuiltin("source-ptr", 0, &sourcePtr);
        try self.createBuiltin("source-len", 0, &sourceLen);
        try self.createBuiltin(">in", 0, &sourceIn);
        try self.createBuiltin("refill", 0, &refill);

        try self.createBuiltin("panic", 0, &panic_);

        try self.createBuiltin("sleep", 0, &sleep);

        try self.createBuiltin("calc-timestamp", 0, &calcTimestamp);
        try self.createBuiltin("now", 0, &now);
        try self.createBuiltin("timezone", 0, &timezone);

        try self.createBuiltin("alloc-dictionary", 0, &allocDictionary);
        try self.createBuiltin("free-dictionary", 0, &freeDictionary);
        try self.createBuiltin("use-dictionary", 0, &useDictionary);
        try self.createBuiltin("main-dictionary", 0, &mainDictionary);
    }

    //;

    pub fn pop(self: *Self) Error!Cell {
        return try self.stack.pop();
    }

    pub fn push(self: *Self, val: Cell) Error!void {
        try self.stack.push(val);
    }

    //;

    pub fn sliceAt(comptime T: type, addr: Cell, len: Cell) []T {
        var str: []T = undefined;
        str.ptr = @ptrFromInt(addr);
        str.len = len;
        return str;
    }

    pub fn alignAddr(comptime T: type, addr: Cell) Cell {
        const alignment_error = @alignOf(T) - (addr % @alignOf(T));
        return if (alignment_error == @alignOf(T)) addr else addr + alignment_error;
    }

    pub fn parseNumber(str: []const u8, base_: Cell) Error!Cell {
        var is_negative: bool = false;
        var read_at: usize = 0;
        var acc: Cell = 0;

        if (str[0] == '-') {
            is_negative = true;
            read_at += 1;
        } else if (str[0] == '+') {
            read_at += 1;
        }

        var effective_base = base_;
        if (str.len > 2) {
            if (std.mem.eql(u8, "0x", str[0..2])) {
                effective_base = 16;
                read_at += 2;
            } else if (std.mem.eql(u8, "0b", str[0..2])) {
                effective_base = 2;
                read_at += 2;
            }
        }

        while (read_at < str.len) : (read_at += 1) {
            const ch = str[read_at];
            const digit = switch (ch) {
                '0'...'9' => ch - '0',
                'A'...'Z' => ch - 'A' + 10,
                'a'...'z' => ch - 'a' + 10,
                else => return error.InvalidNumber,
            };
            if (digit > effective_base) return error.InvalidNumber;
            acc = acc * effective_base + digit;
        }

        return if (is_negative) 0 -% acc else acc;
    }

    pub fn parseFloat(str: []const u8) Error!Float {
        for (str) |ch| {
            switch (ch) {
                '0'...'9', '.', '+', '-' => {},
                else => return error.InvalidFloat,
            }
        }
        if (str.len == 1 and
            (str[0] == '+' or
            str[0] == '-' or
            str[0] == '.'))
        {
            return error.InvalidFloat;
        }
        return std.fmt.parseFloat(Float, str) catch {
            return error.InvalidFloat;
        };
    }

    pub fn pushString(self: *Self, str: []const u8) Error!void {
        try self.push(@intFromPtr(str.ptr));
        try self.push(str.len);
    }

    //;

    pub const WordHeader = packed struct {
        const WordHeaderSelf = @This();

        //       | WordHeader |
        // | ... |        | | |  ...  |0|  ...  | ...
        //  ^     ^        ^ ^ ^       ^ ^       ^
        //  |     addr of  | | name    | |       code
        //  |     previous | name_len  | 0 padding to @alignOf(Cell)
        //  |     word     flags       terminator
        //  padding to @alignOf(WordHeader)

        previous: Cell,
        flags: u8,
        name_len: u8,

        pub fn nameSlice(self: *WordHeaderSelf) []u8 {
            return sliceAt(u8, @intFromPtr(&self.name_len) + @sizeOf(u8), self.name_len);
        }

        pub fn nameSliceConst(self: *const WordHeaderSelf) []const u8 {
            return sliceAt(u8, @intFromPtr(&self.name_len) + @sizeOf(u8), self.name_len);
        }

        pub fn getCfa(self: *const WordHeaderSelf) Cell {
            const name = self.nameSliceConst();
            const name_end_addr = @intFromPtr(name.ptr) + name.len + 1;
            return alignAddr(Cell, name_end_addr);
        }
    };

    // NOTE: currently unused
    pub const Xt = packed struct {
        pub const Type = enum(Cell) { zig, forth };

        header_ptr: Cell,
        ty: Cell,
    };

    // builtins are:
    // | WORD HEADER ... | header_ptr | .zig   | fn_ptr |

    // forth words are:
    // | WORD HEADER ... | header_ptr | .forth | xt ... | EXIT |

    pub fn createWordHeader(
        self: *Self,
        name: []const u8,
        flags: u8,
    ) Error!void {
        self.current_dictionary.here = alignAddr(WordHeader, self.current_dictionary.here);
        const new_latest = self.current_dictionary.here;
        try self.push(self.current_dictionary.latest);
        try self.comma();
        try self.push(flags);
        try self.commaByte();
        try self.push(name.len);
        try self.commaByte();

        for (name) |ch| {
            try self.push(ch);
            try self.commaByte();
        }

        try self.push(0);
        try self.commaByte();

        while ((self.current_dictionary.here % @alignOf(Cell)) != 0) {
            try self.push(0);
            try self.commaByte();
        }

        self.current_dictionary.latest = new_latest;
    }

    pub fn createBuiltin(
        self: *Self,
        name: []const u8,
        flags: u8,
        func: *const Builtin,
    ) Error!void {
        try self.createWordHeader(name, flags);
        try self.push(@intFromEnum(XtType.zig));
        try self.comma();
        try self.push(@intFromPtr(func));
        try self.comma();
    }

    pub fn builtinFnPtrAddress(cfa: Cell) Cell {
        return cfa + @sizeOf(Cell);
    }

    pub fn builtinFnPtr(cfa: Cell) *const Builtin {
        const fn_ptr = @as(*const Cell, @ptrFromInt(builtinFnPtrAddress(cfa))).*;
        return @ptrFromInt(fn_ptr);
    }

    pub fn findWord(self: *Self, addr: Cell, len: Cell) Error!Cell {
        const to_find = sliceAt(u8, addr, len);

        // std.debug.print("{s} {}\n", .{ to_find, check, });

        var check = self.current_dictionary.latest;
        var header: *const WordHeader = undefined;
        while (check != 0) : (check = header.previous) {
            header = @ptrFromInt(check);
            const name = header.nameSliceConst();
            // std.debug.print("{s}\n", .{ name, });
            const flags = header.flags;
            if (name.len != len) continue;
            if ((flags & word_hidden_flag) != 0) continue;

            var name_matches: bool = true;
            for (to_find, name) |to_find_ch, name_ch| {
                if (std.ascii.toUpper(to_find_ch) != std.ascii.toUpper(name_ch)) {
                    name_matches = false;
                    break;
                }
            }

            if (name_matches) {
                break;
            }
        }

        if (check == 0) {
            self.word_not_found = to_find;
            return error.WordNotFound;
        } else {
            return check;
        }
    }

    // ===

    pub fn execute(self: *Self, xt: Cell) Error!void {
        const xt_type_ptr: *const XtType = @ptrFromInt(xt);
        const xt_type = xt_type_ptr.*;
        switch (xt_type) {
            .forth => {
                try self.rstack.push(self.return_to);
                self.return_to = xt;
            },
            .zig => {
                const zig_fn = builtinFnPtr(xt);
                try zig_fn(self);
            },
        }
    }

    pub fn executeLoop(self: *Self, xt: Cell) Error!void {
        var curr_xt = xt;
        self.return_to = 0;

        self.should_bye = false;
        self.should_quit = false;
        while (!self.should_bye and !self.should_quit) {
            try self.execute(curr_xt);
            if (self.return_to == 0) {
                try self.quit();
                break;
            }
            self.return_to += @sizeOf(Cell);
            curr_xt = @as(*Cell, @ptrFromInt(self.return_to)).*;
        }
    }

    // 'quit' stops the current execution loop and goes back to top level interpreter
    // 'bye' quits everything

    pub fn interpret(self: *Self) Error!void {
        self.should_bye = false;
        var out_of_input = false;
        while (!self.should_bye and !out_of_input) {
            try self.word();
            const word_len = try self.stack.index(0);
            const word_addr = try self.stack.index(1);
            if (word_len == 0) {
                _ = try self.pop();
                _ = try self.pop();
                try self.refill();
                const res = try self.pop();
                if (res == forth_false) {
                    out_of_input = true;
                }
                continue;
            }

            try self.find();

            const was_found = try self.pop();
            const addr = try self.pop();
            const is_compiling = self.state != forth_false;
            if (was_found == forth_true) {
                const header: *const WordHeader = @ptrFromInt(addr);
                const is_immediate = (header.flags & word_immediate_flag) != 0;
                const xt = header.getCfa();
                if (is_compiling and !is_immediate) {
                    try self.push(xt);
                    try self.comma();
                } else {
                    try self.executeLoop(xt);
                }
            } else {
                var str = sliceAt(u8, word_addr, word_len);
                if (parseNumber(str, self.base) catch null) |num| {
                    if (is_compiling) {
                        try self.push(self.lit_address);
                        try self.comma();
                        try self.push(num);
                        try self.comma();
                    } else {
                        try self.push(num);
                    }
                } else if (parseFloat(str) catch null) |fl| {
                    if (is_compiling) {
                        try self.push(self.litFloat_address);
                        try self.comma();
                        try self.fstack.push(fl);
                        try self.fComma();
                        self.current_dictionary.here = alignAddr(Cell, self.current_dictionary.here);
                    } else {
                        try self.fstack.push(fl);
                    }
                } else {
                    self.word_not_found = str;
                    return error.WordNotFound;
                }
            }
        }
    }

    pub fn nextChar(self: *Self) Error!u8 {
        if (self.source_in >= self.source_len) {
            return error.EndOfInput;
        }
        const ch = (try alignedAccess(u8, self.source_ptr + self.source_in)).*;
        self.source_in += 1;
        return ch;
    }

    pub fn interpretBuffer(self: *Self, buf: []const u8) Error!void {
        self.source_user_input = VM.forth_false;
        self.source_ptr = @intFromPtr(buf.ptr);
        self.source_len = buf.len;
        self.source_in = 0;
        try self.interpret();
    }

    // builtins

    pub fn word(self: *Self) Error!void {
        var ch: u8 = ' ';
        while (ch == ' ' or ch == '\n') {
            ch = self.nextChar() catch |err| switch (err) {
                error.EndOfInput => {
                    try self.push(0);
                    try self.push(0);
                    return;
                },
                else => return err,
            };
        }

        const start_idx = self.source_in - 1;
        var len: Cell = 1;

        while (true) {
            ch = self.nextChar() catch |err| switch (err) {
                error.EndOfInput => break,
                else => return err,
            };

            if (ch == ' ' or ch == '\n') {
                break;
            }

            if (len >= word_max_len) {
                return error.WordTooLong;
            }

            len += 1;
        }

        try self.push(self.source_ptr + start_idx);
        try self.push(len);
    }

    pub fn nextCharForth(self: *Self) Error!void {
        try self.push(try self.nextChar());
    }

    pub fn forthFnId(self: *Self) Error!void {
        try self.push(@intFromEnum(XtType.forth));
    }

    pub fn exit_(self: *Self) Error!void {
        self.return_to = try self.rstack.pop();
    }

    pub fn lit(self: *Self) Error!void {
        const data = (try alignedAccess(Cell, self.return_to + @sizeOf(Cell))).*;
        try self.push(data);
        self.return_to += @sizeOf(Cell);
    }

    pub fn litFloat(self: *Self) Error!void {
        const data = (try alignedAccess(Float, self.return_to + @sizeOf(Cell))).*;
        try self.fstack.push(data);
        self.return_to += @sizeOf(Cell);
    }

    pub fn executeForth(self: *Self) Error!void {
        const xt_addr = try self.pop();
        try self.execute(xt_addr);
    }

    pub fn quit(self: *Self) Error!void {
        self.rstack.clear();
        self.should_quit = true;
    }

    pub fn bye(self: *Self) Error!void {
        self.should_bye = true;
    }

    //;

    pub fn memStart(self: *Self) Error!void {
        try self.push(@intFromPtr(self.mem.ptr));
    }

    pub fn memSize(self: *Self) Error!void {
        try self.push(mem_size);
    }

    pub fn dictionaryStart(self: *Self) Error!void {
        try self.push(@intFromPtr(self.current_dictionary.memory.ptr));
    }

    pub fn state(self: *Self) Error!void {
        try self.push(@intFromPtr(&self.state));
    }

    pub fn latest(self: *Self) Error!void {
        try self.push(@intFromPtr(&self.current_dictionary.latest));
    }

    pub fn here(self: *Self) Error!void {
        try self.push(@intFromPtr(&self.current_dictionary.here));
    }

    pub fn base(self: *Self) Error!void {
        try self.push(@intFromPtr(&self.base));
    }

    pub fn s0(self: *Self) Error!void {
        try self.push(self.stack.s0());
    }

    pub fn sp(self: *Self) Error!void {
        try self.push(self.stack.sp());
    }

    pub fn spFetch(self: *Self) Error!void {
        try self.push(self.stack.top);
    }

    pub fn spStore(self: *Self) Error!void {
        const val = try self.pop();
        self.stack.top = val;
    }

    pub fn rs0(self: *Self) Error!void {
        try self.push(self.rstack.s0());
    }

    pub fn rsp(self: *Self) Error!void {
        try self.push(self.rstack.sp());
    }

    pub fn fs0(self: *Self) Error!void {
        try self.push(self.fstack.s0());
    }

    pub fn fsp(self: *Self) Error!void {
        try self.push(self.fstack.sp());
    }

    //;

    pub fn dup(self: *Self) Error!void {
        try self.stack.dup();
    }

    pub fn dupMaybe(self: *Self) Error!void {
        const a = try self.stack.index(0);
        if (a != forth_false) {
            try self.push(a);
        }
    }

    pub fn drop(self: *Self) Error!void {
        try self.stack.drop();
    }

    pub fn swap(self: *Self) Error!void {
        try self.stack.swap();
    }

    pub fn over(self: *Self) Error!void {
        try self.stack.over();
    }

    pub fn tuck(self: *Self) Error!void {
        try self.stack.tuck();
    }

    pub fn nip(self: *Self) Error!void {
        try self.stack.nip();
    }

    pub fn rot(self: *Self) Error!void {
        try self.stack.rot();
    }

    pub fn nrot(self: *Self) Error!void {
        try self.stack.nrot();
    }

    pub fn pick(self: *Self) Error!void {
        const at = try self.pop();
        try self.stack.pick(at);
    }

    pub fn swap2(self: *Self) Error!void {
        try self.stack.swap2();
    }

    //;

    pub fn toR(self: *Self) Error!void {
        try self.rstack.push(try self.pop());
    }

    pub fn fromR(self: *Self) Error!void {
        try self.push(try self.rstack.pop());
    }

    pub fn rFetch(self: *Self) Error!void {
        try self.push(try self.rstack.index(0));
    }

    //;

    pub fn define(self: *Self) Error!void {
        const len = try self.pop();
        const addr = try self.pop();
        if (len == 0) {
            try self.createWordHeader("", word_hidden_flag);
        } else if (len < word_max_len) {
            try self.createWordHeader(sliceAt(u8, addr, len), 0);
        } else {
            return error.WordTooLong;
        }
    }

    //     pub fn word(self: *Self) Error!void {
    //         const slc = try self.nextWord();
    //         try self.push(@intFromPtr(slc.ptr));
    //         try self.push(slc.len);
    //     }

    // TODO 0 0 find should return 0 false always
    pub fn find(self: *Self) Error!void {
        const len = try self.pop();
        const addr = try self.pop();
        const ret = self.findWord(addr, len) catch |err| {
            switch (err) {
                error.WordNotFound => {
                    self.word_not_found = sliceAt(u8, addr, len);
                    try self.push(addr);
                    try self.push(forth_false);
                    return;
                },
                else => return err,
            }
        };

        try self.push(ret);
        try self.push(forth_true);
    }

    pub fn fetch(self: *Self) Error!void {
        const addr = try self.pop();
        const value = (try alignedAccess(Cell, addr)).*;
        try self.push(value);
    }

    pub fn store(self: *Self) Error!void {
        const addr = try self.pop();
        const val = try self.pop();
        (try alignedAccess(Cell, addr)).* = val;
    }

    pub fn comma(self: *Self) Error!void {
        try self.push(self.current_dictionary.here);
        try self.store();
        self.current_dictionary.here += @sizeOf(Cell);
    }

    pub fn fetchByte(self: *Self) Error!void {
        const addr = try self.pop();
        const byte = (try alignedAccess(u8, addr)).*;
        try self.push(byte);
    }

    pub fn storeByte(self: *Self) Error!void {
        const addr = try self.pop();
        const val = try self.pop();
        const byte: u8 = @truncate(val);
        (try alignedAccess(u8, addr)).* = byte;
    }

    pub fn commaByte(self: *Self) Error!void {
        try self.push(self.current_dictionary.here);
        try self.storeByte();
        self.current_dictionary.here += 1;
    }

    pub fn tick(self: *Self) Error!void {
        try self.word();
        const word_len = try self.stack.index(0);
        const word_addr = try self.stack.index(1);
        _ = word_len;
        _ = word_addr;

        try self.find();
        if ((try self.pop()) == forth_false) {
            return error.WordNotFound;
        }
        try self.getCfa();
    }

    pub fn bracketTick(self: *Self) Error!void {
        try self.tick();
        try self.push(self.lit_address);
        try self.comma();
        try self.comma();
    }

    pub fn lBracket(self: *Self) Error!void {
        self.state = forth_false;
    }

    pub fn rBracket(self: *Self) Error!void {
        self.state = forth_true;
    }

    pub fn immediateFlag(self: *Self) Error!void {
        try self.push(word_immediate_flag);
    }

    pub fn hiddenFlag(self: *Self) Error!void {
        try self.push(word_hidden_flag);
    }

    pub fn makeImmediate(self: *Self) Error!void {
        const addr = try self.pop();
        // TODO alignedAccess on these
        const header: *WordHeader = @ptrFromInt(addr);
        header.flags ^= word_immediate_flag;
    }

    pub fn hide(self: *Self) Error!void {
        const addr = try self.pop();
        const header: *WordHeader = @ptrFromInt(addr);
        header.flags ^= word_hidden_flag;
    }

    pub fn getCfa(self: *Self) Error!void {
        const addr = try self.pop();
        const header: *WordHeader = try alignedAccess(WordHeader, addr);
        try self.push(header.getCfa());
    }

    pub fn branch(self: *Self) Error!void {
        const jump_ct = @as(*Cell, @ptrFromInt(self.return_to + @sizeOf(Cell))).*;
        self.return_to +%= jump_ct;
    }

    pub fn zbranch(self: *Self) Error!void {
        if ((try self.pop()) == forth_false) {
            try self.branch();
        } else {
            self.return_to += @sizeOf(Cell);
        }
    }

    // TODO note jump only works with forth words not builtins
    pub fn jump(self: *Self) Error!void {
        const jump_addr = @as(*Cell, @ptrFromInt(self.return_to + @sizeOf(Cell))).*;
        self.return_to = jump_addr;
        self.return_to -= @sizeOf(Cell);
    }

    pub fn nop(_: *Self) Error!void {}

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
        const a: SCell = @bitCast(try self.pop());
        const b: SCell = @bitCast(try self.pop());
        try self.push(if (b < a) forth_true else forth_false);
    }

    pub fn gt(self: *Self) Error!void {
        const a: SCell = @bitCast(try self.pop());
        const b: SCell = @bitCast(try self.pop());
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
        try self.push(a << @truncate(ct));
    }

    pub fn rshift(self: *Self) Error!void {
        const ct = try self.pop();
        const a = try self.pop();
        try self.push(a >> @truncate(ct));
    }

    //;

    pub fn plus(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(b +% a);
    }

    pub fn minus(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(b -% a);
    }

    pub fn times(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        try self.push(b *% a);
    }

    pub fn divMod(self: *Self) Error!void {
        const a: SCell = @bitCast(try self.pop());
        const b: SCell = @bitCast(try self.pop());
        const q = @divTrunc(b, a);
        const mod = @mod(b, a);
        try self.push(@bitCast(mod));
        try self.push(@bitCast(q));
    }

    pub fn uDivMod(self: *Self) Error!void {
        const a = try self.pop();
        const b = try self.pop();
        const q = @divTrunc(b, a);
        const mod = @mod(b, a);
        try self.push(mod);
        try self.push(q);
    }

    pub fn cell(self: *Self) Error!void {
        try self.push(@sizeOf(Cell));
    }

    //     pub fn half(self: *Self) Error!void {
    //         try self.push(@sizeOf(HalfCell));
    //     }

    // TODO this is a pretty basic >number as it doest return where in the string it stopped parsing
    pub fn parseNumberForth(self: *Self) Error!void {
        const len = try self.pop();
        const addr = try self.pop();
        const num = parseNumber(sliceAt(u8, addr, len), self.base) catch |err| switch (err) {
            error.InvalidNumber => {
                try self.push(0);
                try self.push(forth_false);
                return;
            },
            else => return err,
        };
        try self.push(num);
        try self.push(forth_true);
    }

    pub fn plusStore(self: *Self) Error!void {
        const addr = try self.pop();
        const val = try self.pop();
        (try alignedAccess(Cell, addr)).* +%= val;
    }

    //;

    pub fn showStack(self: *Self) Error!void {
        const stk = self.stack.toSlice();

        std.debug.print("stack depth: {}\n", .{stk.len});

        var i: usize = 0;
        while (i < stk.len) : (i += 1) {
            const val = stk[stk.len - i - 1];
            std.debug.print("{}: 0x{x:.>16} {}\n", .{ i, val, val });
        }
    }

    //;

    // TODO test works
    //      seems to work
    pub fn litString(self: *Self) Error!void {
        const len = (try alignedAccess(Cell, self.return_to + @sizeOf(Cell))).*;
        const str_addr = self.return_to + 2 * @sizeOf(Cell);
        try self.push(str_addr);
        try self.push(len);
        self.return_to = alignAddr(Cell, str_addr + len) - @sizeOf(Cell);
    }

    pub fn type_(self: *Self) Error!void {
        const len = try self.pop();
        const addr = try self.pop();
        std.debug.print("{s}", .{sliceAt(u8, addr, len)});
    }

    //     pub fn key(self: *Self) Error!void {
    //         // TODO handle end of input
    //         const ch = try self.nextChar();
    //         try self.push(ch);
    //     }
    //
    //     pub fn keyAvailable(self: *Self) Error!void {
    //         // TODO
    //         //         if (self.currentInput()) |input| {
    //         //             try self.push(if (input.pos < input.str.len) forth_true else forth_false);
    //         //         } else {
    //         //             try self.push(forth_false);
    //         //         }
    //     }

    pub fn char(self: *Self) Error!void {
        try self.word();
        const len = try self.pop();
        const addr = try self.pop();
        try self.push(sliceAt(u8, addr, len)[0]);
    }

    pub fn emit(self: *Self) Error!void {
        std.debug.print("{c}", .{@as(u8, @truncate(try self.pop()))});
    }

    //;

    pub fn allocate(self: *Self) Error!void {
        const size = try self.pop();
        const real_size = alignAddr(Cell, size + @sizeOf(Cell));
        var mem = self.allocator.allocWithOptions(
            u8,
            real_size,
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
        const size_ptr: *Cell = @ptrCast(@alignCast(mem.ptr));
        size_ptr.* = real_size;
        const data_ptr = mem.ptr + @sizeOf(Cell);
        try self.push(@intFromPtr(data_ptr));
        try self.push(forth_true);
    }

    pub fn free_(self: *Self) Error!void {
        const addr = try self.pop();
        const data_ptr: [*]u8 = @ptrFromInt(addr);
        const mem_ptr = data_ptr - @sizeOf(Cell);
        const size_ptr: *Cell = @ptrCast(@alignCast(mem_ptr));
        var mem: []u8 = undefined;
        mem.ptr = mem_ptr;
        mem.len = size_ptr.*;
        self.allocator.free(mem);
    }

    pub fn resize(self: *Self) Error!void {
        // TODO
        const size = try self.pop();
        const addr = try self.pop();
        const data_ptr: [*]u8 = @ptrFromInt(addr);
        const mem_ptr = data_ptr - @sizeOf(Cell);
        const size_ptr: *Cell = @ptrCast(@alignCast(mem_ptr));
        var mem: []u8 = undefined;
        mem.ptr = mem_ptr;
        mem.len = size_ptr.*;
        try self.allocator.realloc(mem, size);
    }

    pub fn cmoveUp(self: *Self) Error!void {
        const len = try self.pop();
        const dest: [*]u8 = @ptrFromInt(try self.pop());
        const src: [*]u8 = @ptrFromInt(try self.pop());
        {
            @setRuntimeSafety(false);
            var i: usize = 0;
            while (i < len) : (i += 1) {
                dest[i] = src[i];
            }
        }
    }

    pub fn cmoveDown(self: *Self) Error!void {
        const len = try self.pop();
        const dest: [*]u8 = @ptrFromInt(try self.pop());
        const src: [*]u8 = @ptrFromInt(try self.pop());
        {
            @setRuntimeSafety(false);
            var i: usize = len;
            while (i > 0) : (i -= 1) {
                dest[i - 1] = src[i - 1];
            }
        }
    }

    pub fn memEql(self: *Self) Error!void {
        const ct = try self.pop();
        const addr_a = try self.pop();
        const addr_b = try self.pop();
        if (addr_a == addr_b) {
            try self.push(forth_true);
            return;
        }
        var i: usize = 0;
        while (i < ct) : (i += 1) {
            const a_val = @as(*u8, @ptrFromInt(addr_a + i)).*;
            const b_val = @as(*u8, @ptrFromInt(addr_b + i)).*;
            if (a_val != b_val) {
                try self.push(forth_false);
                return;
            }
        }
        try self.push(forth_true);
    }

    // ===

    pub fn fPrint(self: *Self) Error!void {
        const float = try self.fstack.pop();
        std.debug.print("{d} ", .{float});
    }

    pub fn fSize(self: *Self) Error!void {
        try self.push(@sizeOf(Float));
    }

    pub fn fPlus(self: *Self) Error!void {
        const a = try self.fstack.pop();
        const b = try self.fstack.pop();
        try self.fstack.push(b + a);
    }

    pub fn fMinus(self: *Self) Error!void {
        const a = try self.fstack.pop();
        const b = try self.fstack.pop();
        try self.fstack.push(b - a);
    }

    pub fn fTimes(self: *Self) Error!void {
        const a = try self.fstack.pop();
        const b = try self.fstack.pop();
        try self.fstack.push(b * a);
    }

    pub fn fDivide(self: *Self) Error!void {
        const a = try self.fstack.pop();
        const b = try self.fstack.pop();
        try self.fstack.push(b / a);
    }

    pub fn fSin(self: *Self) Error!void {
        const val = try self.fstack.pop();
        try self.fstack.push(std.math.sin(val));
    }

    pub fn pi(self: *Self) Error!void {
        try self.fstack.push(std.math.pi);
    }

    pub fn tau(self: *Self) Error!void {
        try self.fstack.push(std.math.tau);
    }

    pub fn fFetch(self: *Self) Error!void {
        const addr = try self.pop();
        const val = (try alignedAccess(Float, addr)).*;
        try self.fstack.push(val);
    }

    pub fn fStore(self: *Self) Error!void {
        const addr = try self.pop();
        const val = try self.fstack.pop();
        (try alignedAccess(Float, addr)).* = val;
    }

    pub fn fComma(self: *Self) Error!void {
        try self.push(self.current_dictionary.here);
        try self.fStore();
        self.current_dictionary.here += @sizeOf(Float);
        // TODO have to align to cell after this
    }

    pub fn fPlusStore(self: *Self) Error!void {
        const addr = try self.pop();
        const val = try self.fstack.pop();
        (try alignedAccess(Float, addr)).* += val;
    }

    pub fn fParse(self: *Self) Error!void {
        const len = try self.pop();
        const addr = try self.pop();
        const str = sliceAt(u8, addr, len);
        const fl = parseFloat(str) catch |err| switch (err) {
            error.InvalidFloat => {
                try self.fstack.push(0);
                try self.push(forth_false);
                return;
            },
            else => return err,
        };
        try self.fstack.push(fl);
        try self.push(forth_true);
    }

    pub fn fDup(self: *Self) Error!void {
        try self.fstack.dup();
    }

    pub fn fDrop(self: *Self) Error!void {
        try self.fstack.drop();
    }

    pub fn fSwap(self: *Self) Error!void {
        try self.fstack.swap();
    }

    pub fn fOver(self: *Self) Error!void {
        try self.fstack.over();
    }

    pub fn fRot(self: *Self) Error!void {
        try self.fstack.rot();
    }

    pub fn fNRot(self: *Self) Error!void {
        try self.fstack.nrot();
    }

    pub fn fPick(self: *Self) Error!void {
        const at = try self.pop();
        try self.fstack.pick(at);
    }

    pub fn fToS(self: *Self) Error!void {
        const f = try self.fstack.pop();
        const s: SCell = @intFromFloat(std.math.trunc(f));
        try self.push(@bitCast(s));
    }

    pub fn sToF(self: *Self) Error!void {
        const s: SCell = @bitCast(try self.pop());
        try self.fstack.push(@floatFromInt(s));
    }

    pub fn flt(self: *Self) Error!void {
        const a = try self.fstack.pop();
        const b = try self.fstack.pop();
        try self.push(if (b < a) forth_true else forth_false);
    }

    pub fn fgt(self: *Self) Error!void {
        const a = try self.fstack.pop();
        const b = try self.fstack.pop();
        try self.push(if (b > a) forth_true else forth_false);
    }

    pub fn fShowStack(self: *Self) Error!void {
        const stk = self.fstack.toSlice();

        std.debug.print("f<{}> ", .{stk.len});

        for (stk) |item| {
            std.debug.print("{d} ", .{item});
        }
    }

    pub fn fFloor(self: *Self) Error!void {
        const f = try self.fstack.pop();
        try self.fstack.push(std.math.floor(f));
    }

    pub fn fPow(self: *Self) Error!void {
        const exp = try self.fstack.pop();
        const f = try self.fstack.pop();
        try self.fstack.push(std.math.pow(Float, f, exp));
    }

    // ===

    pub fn fileRO(self: *Self) Error!void {
        try self.push(file_read_flag);
    }

    pub fn fileWO(self: *Self) Error!void {
        try self.push(file_write_flag);
    }

    pub fn fileRW(self: *Self) Error!void {
        try self.push(file_write_flag | file_read_flag);
    }

    pub fn fileOpen(self: *Self) Error!void {
        const permissions = try self.pop();
        const len = try self.pop();
        const addr = try self.pop();

        var flags = std.fs.File.OpenFlags{ .mode = .read_only };

        const read_access =
            (permissions & file_read_flag) != 0;
        const write_access =
            (permissions & file_write_flag) != 0;

        if (read_access and write_access) {
            flags.mode = .read_write;
        } else if (read_access) {
            flags.mode = .read_only;
        } else if (write_access) {
            flags.mode = .write_only;
        }

        var f = std.fs.cwd().openFile(sliceAt(u8, addr, len), flags) catch {
            try self.push(0);
            try self.push(forth_false);
            return;
        };
        errdefer f.close();

        var file = try self.allocator.create(std.fs.File);
        file.* = f;

        try self.push(@intFromPtr(file));
        try self.push(forth_true);
    }

    pub fn fileClose(self: *Self) Error!void {
        const f = try self.pop();
        var ptr: *std.fs.File = @ptrFromInt(f);
        ptr.close();
        self.allocator.destroy(ptr);
    }

    pub fn fileReposition(self: *Self) Error!void {
        const f = try self.pop();
        const to = try self.pop();
        var ptr: *std.fs.File = @ptrFromInt(f);
        ptr.seekTo(to) catch {
            try self.push(forth_false);
            return;
        };
        try self.push(forth_true);
    }

    pub fn fileSize(self: *Self) Error!void {
        const f = try self.pop();
        var ptr: *std.fs.File = @ptrFromInt(f);
        try self.push(ptr.getEndPos() catch unreachable);
    }

    pub fn fileRead(self: *Self) Error!void {
        const f = try self.pop();
        const n = try self.pop();
        const addr = try self.pop();

        var ptr: *std.fs.File = @ptrFromInt(f);
        var buf = sliceAt(u8, addr, n);
        // TODO handle read errors
        const ct = ptr.read(buf) catch unreachable;

        try self.push(ct);
    }

    // ( buffer n file -- read-ct delimiter-found?/not-eof? )
    pub fn fileReadLine(self: *Self) Error!void {
        const f = try self.pop();
        const n = try self.pop();
        const addr = try self.pop();

        var ptr: *std.fs.File = @ptrFromInt(f);
        var reader = ptr.reader();

        var buf = sliceAt(u8, addr, n);
        // TODO handle read errors
        const slc = reader.readUntilDelimiterOrEof(buf, '\n') catch unreachable;
        if (slc) |s| {
            try self.push(s.len);
            try self.push(forth_true);
        } else {
            try self.push(0);
            try self.push(forth_false);
        }
    }

    // ( buffer n file -- write-ct )
    pub fn fileWrite(self: *Self) Error!void {
        const f = try self.pop();
        const n = try self.pop();
        const addr = try self.pop();

        var ptr: *std.fs.File = @ptrFromInt(f);
        var writer = ptr.writer();
        var buf = sliceAt(u8, addr, n);

        // TODO handle errors
        const ct = writer.write(buf) catch unreachable;
        try self.push(ct);
    }

    // ===

    pub fn setSource(self: *Self, source: []const u8) void {
        self.source_user_input = forth_false;
        self.source_ptr = @intFromPtr(source.ptr);
        self.source_len = source.len;
        self.source_in = 0;
    }

    pub fn sourceUserInput(self: *Self) Error!void {
        try self.push(@intFromPtr(&self.source_user_input));
    }

    pub fn sourcePtr(self: *Self) Error!void {
        try self.push(@intFromPtr(&self.source_ptr));
    }

    pub fn sourceLen(self: *Self) Error!void {
        try self.push(@intFromPtr(&self.source_len));
    }

    pub fn sourceIn(self: *Self) Error!void {
        try self.push(@intFromPtr(&self.source_in));
    }

    pub fn refill(self: *Self) Error!void {
        if (self.source_user_input == forth_true) {
            const reader = std.io.getStdIn().reader();
            const input_buffer = self.input_buffer[0..(input_buffer_size - 1)];
            // TODO this breaks something with current_dictionary.latest
            const line = reader.readUntilDelimiterOrEof(input_buffer, '\n') catch |err| {
                switch (err) {
                    // TODO
                    error.StreamTooLong => unreachable,
                    // TODO
                    else => unreachable,
                }
            };
            if (line) |s| {
                self.input_buffer[s.len] = '\n';
                self.source_ptr = @intFromPtr(self.input_buffer);
                self.source_len = s.len + 1;
                self.source_in = 0;
                try self.push(forth_true);
            } else {
                try self.push(forth_false);
            }
        } else {
            try self.push(forth_false);
        }
    }

    // ===

    pub fn panic_(self: *Self) Error!void {
        _ = self;
        return error.Panic;
    }

    // ===

    pub fn sleep(self: *Self) Error!void {
        std.time.sleep(try self.pop());
    }

    pub fn calcTimestamp(self: *Self) Error!void {
        const time = try self.pop();

        const es: std.time.epoch.EpochSeconds = .{ .secs = @intCast(time) };
        const ed = es.getEpochDay();

        const yd = ed.calculateYearDay();
        const year: Cell = yd.year;
        const md = yd.calculateMonthDay();
        const month: Cell = md.month.numeric();
        const day_of_month: Cell = md.day_index;

        const ds = es.getDaySeconds();
        const hr: Cell = ds.getHoursIntoDay();
        const min: Cell = ds.getMinutesIntoHour();
        const sec: Cell = ds.getSecondsIntoMinute();

        try self.push(sec);
        try self.push(min);
        try self.push(hr);
        try self.push(day_of_month);
        try self.push(month);
        try self.push(year);
    }

    pub fn now(self: *Self) Error!void {
        const time = std.time.timestamp();
        // TODO intcast here? or intCast->SCell then bitCast->Cell ?
        try self.push(@intCast(time));
    }

    pub fn timezone(self: *Self) Error!void {
        const c = @cImport({
            @cInclude("time.h");
        });
        c.tzset();

        const offset = c.timezone;
        try self.push(@intCast(offset));
    }

    // ===

    pub fn allocDictionary(self: *Self) Error!void {
        const sz = try self.pop();
        const new_mem = self.allocator.allocWithOptions(u8, sz, @alignOf(WordHeader), null) catch |err|
            switch (err) {
            error.OutOfMemory => {
                try self.push(0);
                try self.push(forth_false);
                return;
            },
        };
        errdefer self.allocator.free(new_mem);
        // note: this should be Cell aligned
        const dict = self.allocator.create(Dictionary) catch |err|
            switch (err) {
            error.OutOfMemory => {
                try self.push(0);
                try self.push(forth_false);
                return;
            },
        };

        dict.init(new_mem, self.current_dictionary.latest);

        try self.push(@intFromPtr(dict));
    }

    pub fn freeDictionary(self: *Self) Error!void {
        const addr = try self.pop();
        const dictionary: *Dictionary = @ptrFromInt(addr);
        self.allocator.free(dictionary.memory);
        self.allocator.destroy(dictionary);
    }

    pub fn useDictionary(self: *Self) Error!void {
        const addr = try self.pop();
        const dictionary: *Dictionary = @ptrFromInt(addr);
        self.current_dictionary = dictionary;
    }

    pub fn mainDictionary(self: *Self) Error!void {
        try self.push(@intFromPtr(&self.main_dictionary));
    }
};
