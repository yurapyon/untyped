here @
word : define
' docol ,
' word , ' define ,
' latest , ' @ , ' hide ,
' lit , ' docol , ' , ,
' ] ,
' exit ,
latest !

here @
word ; define
' docol ,
' lit , ' exit , ' , ,
' latest , ' @ , ' hide ,
' [ ,
' exit ,
latest !
latest @ make-immediate

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

\ todo maybe change to have normal arg order
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

\ ==

: case
  0
  ; immediate

: of
  ['] over ,
  ['] = ,
  [compile] if
  ['] drop ,
  ; immediate

: endof
  [compile] else
  ; immediate

: endcase
  ['] drop ,
  begin
    ?dup
  while
    [compile] then
  repeat
  ; immediate

\ ===

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

: ." ( -- )
  [compile] s"
  state @ if
    ['] type ,
  else
    type
  then ; immediate

\ TODO rename this
: h>u ( hex-char -- u )
  case
  dup [char] 9 [char] 0 within if [char] 0 -      else
  dup [char] Z [char] A within if [char] A - 10 + else
  dup [char] z [char] a within if [char] a - 10 + else
    \ TODO error
    drop 0
  endcase ;

: read-byte ( -- byte )
  key key
  h>u swap h>u 16 * + ;

: read-escaped-string-into-memory ( start-addr -- end-addr )
  begin
    key
    dup [char] " <>
  while
    dup backslash = if
      drop
      key
      \ TODO
      \ [char] m of 13 10
      \ \n does cr lf on windows
      \   newline is cr lf ? how
      \   get rid of 'newline' and have linefeed ?
      case
      [char] "  of [char] "  endof
      [char] n  of newline   endof
      backslash of backslash endof
      [char] x  of read-byte endof
      [char] a  of 7 endof
      [char] b  of 8 endof
      [char] e  of 27 endof
      [char] f  of 12 endof
      [char] l  of 10 endof
      [char] q  of 34 endof
      [char] r  of 13 endof
      [char] t  of 9 endof
      [char] v  of 11 endof
      [char] z  of 0 endof
        \ TODO error
        s" invalid string escape" type cr
        bye
      endcase
    then
    over c!
    1+
  repeat
  drop ;

: s\" ( ( c: -- ) ( i: -- addr len ) )
  state @ if
    ['] litstring ,
    here @ 0 ,
    here @ read-escaped-string-into-memory
    here @ -
    dup allot align
    swap !
  else
    here @
    here @ read-escaped-string-into-memory
    here @ -
  then
  ; immediate

\ ===

: ridx ( idx -- addr )
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
  ['] ridx ,
  ['] @ ,
  ; immediate

: j
  ['] lit , 3 ,
  ['] ridx ,
  ['] @ ,
  ; immediate

: k
  ['] lit , 5 ,
  ['] ridx ,
  ['] @ ,
  ; immediate

\ ===

: literal
  ['] lit , , ; immediate

: space bl emit ;

: repeat-char ( ct char -- )
  swap 0 ( char ct acc )
  begin
    2dup >
  while
    2 pick emit
    1+
  repeat
  3drop ;

: spaces ( n -- )
  space repeat-char ;

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

: .s ( -- )
  [char] < emit
  depth    u.
  [char] > emit
  space
  sp@ s0
  begin
    2dup >
  while
    dup @ u. space
    cell +
  repeat
  2drop ;

: pad-left ( u width char -- )
  >r swap uwidth - r> repeat-char ;

: u.r ( u width -- )
  2dup bl pad-left drop u. ;

: u.0 ( u width -- )
  2dup [char] 0 pad-left drop u. ;

: .r ( n width -- )
  over 0< if
    1- swap negate swap
    2dup bl pad-left drop
    [char] - emit
    u.
  else
    u.r
  then ;

: . 0 .r space ;
: u. u. space ;
: ? @ . ;

\ ===

: cfa> ( cfa -- base-addr/cfa t/f )
  latest @
  begin
    ?dup
  while
    ( cfa latest )
    2dup > if
      nip true
      exit
    then
    @
  repeat
  false ;

: printable? ( ch -- t/f )
  126 32 within ;

: dump ( addr len -- )
  base @ >r
  hex
  over + swap
  ( end-addr start-addr )
  begin
    2dup >
  while
    dup 16 u.r
    16 0 ?do
      dup i + c@
      2 u.0 space
    loop
    16 0 ?do
      dup i + c@
      dup printable? 0= if
        drop [char] .
      then
      emit
    loop
    cr
    16 +
  repeat
  r> base ! ;

\ ===

: >name ( word-addr -- addr len )
  cell + 2 + dup 1- c@ ;

: >flags
  cell + c@ ;

: >next ( addr -- next-addr )
  here @ latest @
  begin
    2 pick over <>
  while
    nip dup @
  repeat
  drop nip ;

: hidden?
  >flags flag,hidden and ;

: immediate?
  >flags flag,immediate and ;

: words
  latest @
  begin
    ?dup
  while
    dup >name type
    dup hidden? if ." (h)" then
    dup immediate? if ." (i)" then
    space
    @
  repeat
  cr ;

: in-memory?
  mem mem-size + mem within ;

: see
  word find drop
  dup >next swap
  dup [char] ( emit >name type [char] ) emit space
  >cfa
  begin
    2dup >
  while
    dup @ case
    ['] lit of ." lit(" cell + dup @ 0 .r ." ) " endof
    ['] 0branch of ." 0branch(" cell + dup @ 0 .r ." ) " endof
    ['] branch of ." branch(" cell + dup @ 0 .r ." ) " endof
    ['] litstring of
      [char] S emit
      [char] " emit
      cell + dup @
      swap cell + swap 2dup type
      + aligned
      cell -
      [char] " emit
      space
    endof
    dup dup in-memory? 0= if
      ." data(" 0 u.r ." ) "
    else
      cfa> drop >name type space
    then
    endcase
    cell +
  repeat
  2drop ;

: recurse
  latest @ >cfa ,
  ; immediate

\ note: if called with an immediate word,
\   assumes that word will compile the address
\   you want to be tailcalled to here @
\ TODO doesnt work with builtins,
\   check if cfa is builitin,
\   dont do anything in that case
: tailcall
  word find drop dup immediate? if
    here @ swap
    >cfa execute
    dup @ cell + swap !
  else
    >cfa cell + ,
  then
  ; immediate

\ ===

(
:noname 1 2 .s cr + . cr ;
execute
1 ' dup execute .s cr

: fn
  1 2
  5000000 0 ?do
    swap
  loop ;

fn

create hello 5 c,
: hello2 5 ;
hello2

' does> cfa> drop 13 dump


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
