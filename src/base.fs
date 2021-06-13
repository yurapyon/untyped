\ :
here @
latest @ ,
0 c, 1 c, 58 c,
0 c, 0 c, 0 c, 0 c, 0 c,
' docol ,
' word , ' define ,
' latest , ' @ , ' hide ,
' lit , ' docol , ' , ,
' ] ,
' exit ,
latest !

\ ;
here @
latest @ ,
flag,immediate c, 1 c, 59 c,
0 c, 0 c, 0 c, 0 c, 0 c,
' docol ,
' lit , ' exit , ' , ,
' latest , ' @ , ' hide ,
' [ ,
' exit ,
latest !

\ ===

: immediate latest @ make-immediate ; immediate
: hidden latest @ hide ; immediate

: 2dup over over ;
: 2drop drop drop ;
: 2over 3 pick 3 pick ;
: 3dup 2 pick 2 pick 2 pick ;
: 3drop drop 2drop ;
: flip swap rot ;

\ ;


: 0= 0 = ;
: 0< 0 < ;
: 0> 0 > ;
: 0<> 0 <> ;

: 1+ 1 + ;
: 1- 1 - ;
: negate 0 swap - ;
: / /mod nip ;
: mod /mod drop ;

: <= > 0= ;
: >= < 0= ;

: within \ ( val max min -- t/f )
  >r over r> \ ( val max val min )
  >= -rot < and ;

: cells cell * ;
: chars ;

: decimal 10 base ! ;
: hex 16 base ! ;
: octal 8 base ! ;

\ ;

: [char]
  char ['] lit , ,
  ; immediate

: [compile]
  word find drop >cfa ,
  ; immediate

: if
  ['] 0branch ,
  here @ 0 , ; immediate

: then
  dup here @ swap -
  swap ! ; immediate

: else
  ['] branch ,
  here @ 0 ,
  swap
  dup here @ swap -
  swap ! ; immediate

: begin
  here @
  ; immediate

: again
  ['] branch ,
  here @ - , ; immediate

: until
  ['] 0branch ,
  here @ - , ; immediate

: while
  ['] 0branch ,
  here @
  0 , ; immediate

: repeat
  ['] branch ,
  swap
  here @ - ,
  dup
  here @ swap -
  swap ! ; immediate

: (
  1
  begin
    key dup [char] ( = if
      drop
      1+
    else
      [char] ) = if
        1-
      then
    then
  dup 0= until
  drop
  ; immediate

\ ;

: newline 10 ;
: bl 32 ;
: backslash 92 ;

: cr newline emit ;

\ ;

\ not a tailcalling recurse
: recurse
  latest @ >cfa ,
  ; immediate

\ todo check this works
: tailcall
  ' cell + ,
  ; immediate

\ ;

: allot
  here @ + here ! ;

\ todo check this works
: move ( src n dest )
  3dup nip < if
    cmove>
  else
    cmove<
  then ;

: mem-end
  mem mem-size + ;

: unused
  mem-end here @ - ;

: latestxt
  latest @ >cfa ;

: create
  word define
  ['] docol ,
  ['] lit , here @ 2 cells + ,
  ['] exit , ;

: does>,redirect-latest ( code-addr -- )
  latestxt 3 cells + ! ;

: does>
  state @ if
    ['] lit , here @ 3 cells + ,
    ['] does>,redirect-latest ,
    ['] exit ,
  else
    here @ does>,redirect-latest
    latest @ hide
    ]
  then
  ; immediate

: >body
  2 cells + @ ;

: constant
  create ,
  does> @ ;

: value.field ( val-addr -- field-addr )
  >cfa 2 cells + ;

: value
  word define
  ['] docol ,
  ['] lit ,
  ,
  ['] exit , ;

: to
  word find drop value.field
  state @ if
    ['] lit ,
    ,
    ['] ! ,
  else
    !
  then
  ; immediate

: :noname
  0 0 define
  here @
  ['] docol ,
  ] ;

\ ===

: aligned ( addr -- a-addr )
  dup cell mod ( addr off-aligned )
  dup if
    cell swap - +
  else
    drop
  then ;

: align ( -- )
  here @ aligned here ! ;

: read-string-into-memory ( start-addr -- end-addr )
  begin
    key
    dup [char] " <>
  while
    over c!
    1+
  repeat
  drop ;

: s" ( ( c: -- ) ( i: -- addr len ) )
  state @ if
    ['] litstring ,
    here @ 0 ,
    here @ read-string-into-memory
    here @ -
    dup allot align
    swap !
  else
    here @
    here @ read-string-into-memory
    here @ -
  then
  ; immediate

\ ===

: rstack.at ( idx -- addr )
  2 + cells rsp @ swap - ;

: ?do
  ['] >r ,
  ['] >r ,
  [compile] begin
  ['] r> ,
  ['] r> ,
  ['] 2dup ,
  ['] > ,
  ['] -rot ,
  ['] >r ,
  ['] >r ,
  [compile] while
  ; immediate

: unloop
  ['] r> ,
  ['] r> ,
  ['] 2drop ,
  ; immediate

: loop
  ['] r> ,
  ['] r> ,
  ['] 1+ ,
  ['] >r ,
  ['] >r ,
  [compile] repeat
  [compile] unloop
  ; immediate

\ todo +loop -loop

: i
  ['] lit , 1 ,
  ['] rstack.at ,
  ['] @ ,
  ; immediate

: j
  ['] lit , 3 ,
  ['] rstack.at ,
  ['] @ ,
  ; immediate

: k
  ['] lit , 5 ,
  ['] rstack.at ,
  ['] @ ,
  ; immediate

\ ===

: literal
  ['] lit , , ; immediate

: space bl emit ;

: spaces ( n -- )
  0 ?do space loop ;

: digit>char
  dup 10 < if
    [char] 0
  else
    10 - [char] a
  then
  + ;

: uwidth ( u -- width )
  1 swap ( ct u )
  begin
    base @ / dup
  while
    swap 1+ swap
  repeat
  drop ;

: chop-digit ( u -- u-lastdigit lastdigit )
  base @ /mod swap ;

create u.buffer 8 cell * allot

: u. ( u -- )
  dup uwidth dup >r
  begin                   ( u uwidth-acc )
    1- >r
    chop-digit digit>char ( urest lastchar )
    u.buffer r@ + c!
    r>
  dup 0= until
  2drop
  u.buffer r> type ;

: depth
  sp@ s0 - cell / ;

: .s    ( -- )
  [char] < emit
  depth    u.
  [char] > emit
  space
  \ todo make +loop and factor
  sp@ s0 - cell / 0 ?do
    s0 i cells + @ u. space
  loop ;

: pad-left ( u width -- )
  swap uwidth - spaces ;

: u.r ( u width -- )
  2dup pad-left drop u. ;

: .r ( n width -- )
  over 0< if
    1- swap negate swap
    2dup pad-left drop
    [char] - emit
    u.
  else
    u.r
  then ;

: . 0 .r space ;
: u. u. space ;
: ? @ . ;

\ ===

(

 : looper
   5 0 ?do
     5 0 ?do
       1 0 ?do
         [char] A i + emit bl emit
         [char] A j + emit bl emit
         [char] A k + emit cr
       loop
     loop
   loop
   ;


looper
.s
bye

: looper
  5 0
  >r >r begin
  r> r> 2dup = 0= -rot >r >r while
    [char] * emit cr
  r> r> 1+ >r >r repeat
  r> r> 2drop ;

32 allocate .s
drop
dup 0 + char h swap c!
dup 1 + char e swap c!
dup 2 + char l swap c!
dup 3 + char l swap c!
dup 4 + char o swap c!
dup 5 type cr
free

unused

5 constant something

unused cell /

.s

-
here @
dictionary
-
cell /
.s

bye

5 constant wowo
wowo .s

' wowo >body dup @ .s

10 create something ,
does> @ 2 + ;

something .s

10 3 /
10 3 mod
.s
)
