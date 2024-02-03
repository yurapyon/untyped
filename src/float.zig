// pub const Float = struct {
//     const Self = @This();
//
//     pub fn Print(self: *Self) Error!void {
//         const float = try self.fstack.pop();
//         std.debug.print("{d} ", .{float});
//     }
//
//     pub fn Size(self: *Self) Error!void {
//         try self.push(@sizeOf(Float));
//     }
//
//     pub fn Plus(self: *Self) Error!void {
//         const a = try self.fstack.pop();
//         const b = try self.fstack.pop();
//         try self.fstack.push(b + a);
//     }
//
//     pub fn Minus(self: *Self) Error!void {
//         const a = try self.fstack.pop();
//         const b = try self.fstack.pop();
//         try self.fstack.push(b - a);
//     }
//
//     pub fn Times(self: *Self) Error!void {
//         const a = try self.fstack.pop();
//         const b = try self.fstack.pop();
//         try self.fstack.push(b * a);
//     }
//
//     pub fn Divide(self: *Self) Error!void {
//         const a = try self.fstack.pop();
//         const b = try self.fstack.pop();
//         try self.fstack.push(b / a);
//     }
//
//     pub fn Sin(self: *Self) Error!void {
//         const val = try self.fstack.pop();
//         try self.fstack.push(std.math.sin(val));
//     }
//
//     pub fn pi(self: *Self) Error!void {
//         try self.fstack.push(std.math.pi);
//     }
//
//     pub fn tau(self: *Self) Error!void {
//         try self.fstack.push(std.math.tau);
//     }
//
//     pub fn Fetch(self: *Self) Error!void {
//         const addr = try self.pop();
//         const val = (try alignedAccess(Float, addr)).*;
//         try self.fstack.push(val);
//     }
//
//     pub fn Store(self: *Self) Error!void {
//         const addr = try self.pop();
//         const val = try self.fstack.pop();
//         (try alignedAccess(Float, addr)).* = val;
//     }
//
//     pub fn Comma(self: *Self) Error!void {
//         try self.push(self.here);
//         try self.fStore();
//         self.here += @sizeOf(Float);
//     }
//
//     pub fn PlusStore(self: *Self) Error!void {
//         const addr = try self.pop();
//         const val = try self.fstack.pop();
//         (try alignedAccess(Float, addr)).* += val;
//     }
//
//     pub fn Parse(self: *Self) Error!void {
//         const len = try self.pop();
//         const addr = try self.pop();
//         const str = sliceAt(u8, addr, len);
//         const fl = parseFloat(str) catch |err| switch (err) {
//             error.InvalidFloat => {
//                 try self.fstack.push(0);
//                 try self.push(forth_false);
//                 return;
//             },
//             else => return err,
//         };
//         try self.fstack.push(fl);
//         try self.push(forth_true);
//     }
//
//     pub fn Dup(self: *Self) Error!void {
//         try self.fstack.dup();
//     }
//
//     pub fn Drop(self: *Self) Error!void {
//         try self.fstack.drop();
//     }
//
//     pub fn Swap(self: *Self) Error!void {
//         try self.fstack.swap();
//     }
//
//     pub fn Over(self: *Self) Error!void {
//         try self.fstack.over();
//     }
//
//     pub fn Rot(self: *Self) Error!void {
//         try self.fstack.rot();
//     }
//
//     pub fn NRot(self: *Self) Error!void {
//         try self.fstack.nrot();
//     }
//
//     pub fn Pick(self: *Self) Error!void {
//         const at = try self.pop();
//         try self.fstack.pick(at);
//     }
//
//     pub fn ToS(self: *Self) Error!void {
//         const f = try self.fstack.pop();
//         const s: SCell = @intFromFloat(std.math.trunc(f));
//         try self.push(@bitCast(s));
//     }
//
//     pub fn sToF(self: *Self) Error!void {
//         const s: SCell = @bitCast(try self.pop());
//         try self.fstack.push(@floatFromInt(s));
//     }
//
//     pub fn lt(self: *Self) Error!void {
//         const a = try self.fstack.pop();
//         const b = try self.fstack.pop();
//         try self.push(if (b < a) forth_true else forth_false);
//     }
//
//     pub fn gt(self: *Self) Error!void {
//         const a = try self.fstack.pop();
//         const b = try self.fstack.pop();
//         try self.push(if (b > a) forth_true else forth_false);
//     }
//
//     pub fn ShowStack(self: *Self) Error!void {
//         const stk = self.fstack.toSlice();
//
//         std.debug.print("f<{}> ", .{stk.len});
//
//         for (stk) |item| {
//             std.debug.print("{d} ", .{item});
//         }
//     }
//
//     pub fn Floor(self: *Self) Error!void {
//         const f = try self.fstack.pop();
//         try self.fstack.push(std.math.floor(f));
//     }
//
//     pub fn Pow(self: *Self) Error!void {
//         const exp = try self.fstack.pop();
//         const f = try self.fstack.pop();
//         try self.fstack.push(std.math.pow(Float, f, exp));
//     }
// };
