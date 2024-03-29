word : define
forth-fn-id ,
' word , ' define ,
' latest , ' @ , ' hide ,
' lit , forth-fn-id , ' , ,
' ] ,
' exit ,

word ; define
forth-fn-id ,
' lit , ' exit , ' , ,
' latest , ' @ , ' hide ,
' [ ,
' exit ,
latest @ make-immediate

: immediate latest @ make-immediate ; immediate
: hidden latest @ hide ; immediate

: abort s0 sp! quit ;

: 2dup over over ;
: 2drop drop drop ;
: 2over 3 pick 3 pick ;
: 3dup 2 pick 2 pick 2 pick ;
: 3drop drop 2drop ;
: flip swap rot ;

: chars ;
: cells cell * ;
: floats float * ;

: 0= 0 = ;
: 0< 0 < ;
: 0> 0 > ;
: 0<> 0 <> ;
: <= > 0= ;
: >= < 0= ;

: 1+ 1 + ;
: 1- 1 - ;
: negate 0 swap - ;
: u/ u/mod nip ;
: umod u/mod drop ;
: / /mod nip ;
: mod /mod drop ;
: 2* 2 * ;

: f2dup fover fover ;
: fflip fswap frot ;

: fnegate -1. f* ;
: frecip 1. fswap f/ ;

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

: unwrap 0= if panic then ;
: abs dup 0< if negate then ;

: [compile]
  word find unwrap >cfa ,
  ; immediate

: literal
  ['] lit , , ; immediate

: [char]
  char [compile] literal
  ; immediate

: [hide]
  word find unwrap hide ;

: \
  begin
    next-char 10 =
  until ; immediate

: (
  1
  begin
    next-char dup [char] ( = if
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

: case
  0 ; immediate

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

: cond
  0 ; immediate

: endcond
  begin
    ?dup
  while
    [compile] then
  repeat
  ; immediate

: ridx ( idx -- addr )
  2 + cells rsp @ swap - ;

: depth
  sp@ s0 - cell / ;

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

: [defined]
  word find nip
  ; immediate

: [undefined]
  [compile] [defined] 0=
  ; immediate

\ ===

: >name ( word-addr -- addr len )
  cell + 2 + dup 1- c@ ;

: >flags
  cell + c@ ;

: hidden?
  >flags flag,hidden and ;

: immediate?
  >flags flag,immediate and ;

: within     ( val min max -- t/f )
  >r over r> ( val min val max )
  < -rot >= and ;

: min ( a b -- min ) 2dup > if swap then drop ;
: max ( a b -- max ) 2dup < if swap then drop ;
: clamp ( val min max -- clamped ) rot min max ;

: decimal 10 base ! ;
: hex 16 base ! ;
: octal 8 base ! ;

: fmin ( f: a b -- f: min ) f2dup f> if fswap then fdrop ;
: fmax ( f: a b -- f: max ) f2dup f< if fswap then fdrop ;
: fclamp ( f: val min max -- f: clamped ) frot fmin fmax ;

\ ===

: bl 32 ;
: backslash 92 ;
: cr 10 emit ;
: space bl emit ;

\ ===

: aligned-to ( addr align -- a-addr )
  2dup mod ( addr align off-aligned )
  ?dup if - + else drop then ;

: align-to ( align -- )
  here @ swap aligned-to here ! ;

: aligned ( addr -- a-addr )
  cell aligned-to ;

: align ( -- )
  cell align-to ;

: faligned ( addr -- a-addr )
  float aligned-to ;

: falign ( -- )
  float align-to ;

: move ( src dest n )
  3dup drop < if
    cmove>
  else
    cmove<
  then ;

: mem-end mem mem-size + ;
: unused mem-end here @ - ;

\ ===

: latestxt
  latest @ >cfa ;

: allot ( ct -- )
  here +! ;

: create
  word define
  forth-fn-id ,
  ['] lit , here @ 3 cells + ,
  ['] exit ,
  ['] nop , ;

: does>,redirect-latest ( code-addr -- )
  ['] jump latestxt 3 cells + !
           latestxt 4 cells + ! ;

: does>
  state @ if
    ['] align ,
    ['] lit , here @ 3 cells + ,
    ['] does>,redirect-latest ,
    ['] exit ,
  else
    align here @
    does>,redirect-latest
    latest @ hide
    ]
  then
  ; immediate

: variable
  create cell allot ;

: constant
  create ,
  does> @ ;

: value
  word define
  forth-fn-id ,
  ['] lit , ,
  ['] exit , ;

: >value-data ( val-addr -- data-addr )
  >cfa 2 cells + ;

: to
  \ todo word not found error here
  word find unwrap >value-data
  state @ if
    ['] lit , ,
    ['] ! ,
  else
    !
  then
  ; immediate

: +to
  \ todo word not found error here
  word find unwrap >value-data
  state @ if
    ['] lit , ,
    ['] +! ,
  else
    +!
  then
  ; immediate

: >fvalue-data ( val-addr -- data-addr )
  >cfa 2 cells + ;

: fvalue
  word define
  forth-fn-id ,
  ['] litfloat , f, align
  ['] exit , ;

: fto
  word find unwrap >fvalue-data
  state @ if
    ['] lit , ,
    ['] f! ,
  else
    f!
  then
  ; immediate

: f+to
  word find unwrap >fvalue-data
  state @ if
    ['] lit , ,
    ['] f+! ,
  else
    f+!
  then
  ; immediate

\ ===

: :noname
  0 0 define
  here @
  forth-fn-id ,
  ] ;

\ ===

: read-string-into-memory ( start-addr -- end-addr )
  begin
    next-char
    dup [char] " <>
  while
    over c!
    1+
  repeat
  drop ;

: s" \ ( c: -- ) ( i: -- addr len )
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

\ todo dont test here, just abort w/ message
: abort"
  [compile] s"
  rot 0= if
    ." abort: "
    type cr abort
  else
    2drop
  then ;

: char>digit ( hex-char -- u )
  case
  dup [char] 0 [char] 9 within if [char] 0 -      else
  dup [char] A [char] Z within if [char] A - 10 + else
  dup [char] a [char] z within if [char] a - 10 + else
    \ TODO error
    drop 0
  endcase ;

: read-byte ( -- byte )
  next-char next-char
  char>digit swap char>digit 16 * + ;

: read-escaped-string-into-memory ( start-addr -- end-addr )
  begin
    next-char
    dup [char] " <>
  while
    dup backslash = if
      drop
      next-char
      \ TODO
      \ [char] m of 13 10 ( cr lf )
      \ \n does cr lf on windows
      case
      [char] "  of [char] "  endof
      backslash of backslash endof
      [char] x  of read-byte endof
      [char] a  of 7 endof
      [char] b  of 8 endof
      [char] n  of 10 endof
      [char] e  of 27 endof
      [char] f  of 12 endof
      [char] l  of 10 endof
      [char] q  of 34 endof
      [char] r  of 13 endof
      [char] t  of 9 endof
      [char] v  of 11 endof
      [char] z  of 0 endof
        \ todo use abort"
        ." invalid string escape" cr
        abort
      endcase
    then
    over c!
    1+
  repeat
  drop ;

: s\" \ ( c: -- ) ( i: -- addr len )
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

: string= ( a alen b blen -- t/f )
  rot over = 0= if 3drop false exit then
  mem= ;

: z"
  state @ if
    ['] lit , here @ 3 cells + ,
    ['] branch , here @ 0 ,
    here @ read-string-into-memory here !
    0 c,
    align
    dup here @ swap - swap !
  else
    [compile] s"
    over + 0 swap c!
  then
  ; immediate

: strlen
  0
  begin
    2dup + c@ 0<>
  while
    1+
  repeat
  nip ;

: ztype
  dup strlen type ;

\ ===

: [if]
  0= if
    begin
      word 2dup
      s" [then]" string= -rot
      s" [else]" string= or
    until
  then ; immediate

: [else]
  begin
    word s" [then]" string=
  until ; immediate

: [then] ; immediate

\ ===

: repeat-char ( ct char -- )
  swap 0 ?do dup emit loop drop ;

: spaces ( n -- )
  space repeat-char ;

: digit>char
  dup 10 <
  if [char] 0 else 10 - [char] a then
  + ;

: uwidth ( u -- width )
  1 swap ( ct u )
  begin
    base @ u/ ?dup
  while
    swap 1+ swap
  repeat ;

: chop-digit ( u -- u-lastdigit lastdigit )
  base @ u/mod swap ;

\ bitSize(byte) * byteSize(cell) is necessary to print cells in binary
create u.buffer 8 cell * allot

: read-to-u.buffer ( u -- uwidth )
  dup uwidth dup >r
  begin                   ( u uwidth-acc )
    1- >r
    chop-digit digit>char ( urest lastchar )
    u.buffer r@ + c!
    r>
  dup 0= until
  2drop r> ;

: u. ( u -- ) read-to-u.buffer u.buffer swap type ;

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
: f? f@ f. ;

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
  32 126 within ;

: dump ( addr len -- )
  base @ >r
  hex
  over + swap
  ( end-addr start-addr )
  begin
    2dup >
  while
    dup 16 u.r space
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
  2drop
  r> base ! ;

\ ===

: >next ( addr -- next-addr )
  here @ latest @
  begin
    2 pick over <>
  while
    nip dup @
  repeat
  drop nip ;

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
  mem mem mem-size + within ;

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
  latestxt , ; immediate

\ note: if called with an immediate word,
\   assumes that word will compile the address
\   you want to be tailcalled to here @
\ TODO doesnt work with builtins,
\   check if cfa is builitin,
\   dont do anything in that case
\ TODO test this doesnt put anything on return stack
\      seems to work
: tailcall
  word find unwrap dup immediate? if
    ['] jump ,
    here @ swap  ( tod to-tailcall )
    >cfa execute ( old-tod )
    cell swap +! ( )
  else
    ['] jump ,
    >cfa cell + ,
  then
  ; immediate

\ ===

: +field ( start this-size "name" -- end )
  over + swap
  create ,
  does> @ + ;

: field ( start this-size "name" -- end-aligned )
  over aligned   ( start this-size aligned-start )
  flip drop      ( aligned-start this-size )
  +field ;

\ TODO this should be [compile] +field
: cfield +field ;

: ffield ( start this-size "name" -- end-aligned )
  over faligned   ( start this-size aligned-start )
  flip drop       ( aligned-start this-size )
  +field ;

: enum ( value "name" -- value+1 )
  dup constant 1+ ;

\ todo use lshift
: flag ( value "name" -- value<<1 )
  dup constant 2* ;

\ ===

: file-read-all ( file -- mem len )
  dup file-size dup allocate if
    flip ( mem file-size file )
    3dup read-file 2drop
  else
    \ TODO error
    bye
  then ;

: file>string ( filepath n -- addr n )
  r/o open-file unwrap ( file )
  dup file-read-all    ( file addr n )
  rot close-file ;

\ ===

: source
  source-ptr @ source-len @ ;

: is-int? 1 = ;

\ 1 for number, -1 for float, 0 for not numeric
: >numeric ( addr len -- _/value/f:value type )
  2dup >number if
    -rot 1
  else
    drop
    2dup >float if
      -1
    else
      fdrop
      0
    then
  then
  -rot 2drop
  ;

: compile-numeric ( value/f:value type -- )
  is-int? if
    ['] lit , ,
  else
    ['] litfloat , f, align
  then
  ;

: basic-prompt ." > " ;

' basic-prompt value prompt-hook

: interpret ( -- )
  word dup 0= if
    2drop
    source-user-input if
      prompt-hook execute
    then
    refill 0= if
      exit
    then
  else
    2dup find if
      -rot 2drop
      dup immediate? 0= state @ and if
        >cfa ,
      else
        >cfa execute
      then
    else
      drop
      2dup >numeric ?dup if
        state @ if
          compile-numeric
        else
          drop -rot
        then
        2drop
      else
        ." word not found: " type cr
      then
    then
  then
  tailcall recurse
  ;

0 cell field saved-source.user-input
  cell field saved-source.ptr
  cell field saved-source.len
  cell field saved-source.in
constant saved-source

8 saved-source * constant include-buf-size
create include-buf include-buf-size allot
0 value include-buf-at

: last-saved-input
  include-buf include-buf-at saved-source * + ;

: save-input
  last-saved-input
  dup saved-source.user-input source-user-input @ swap !
  dup saved-source.ptr source-ptr @ swap !
  dup saved-source.len source-len @ swap !
      saved-source.in >in @ swap !
  1 +to include-buf-at ;

: restore-input
  -1 +to include-buf-at
  last-saved-input
  dup saved-source.user-input @ source-user-input !
  dup saved-source.ptr @ source-ptr !
  dup saved-source.len @ source-len !
      saved-source.in @ >in ! ;

: evaluate ( addr len -- )
  save-input
  source-len ! source-ptr !
  false source-user-input !
  0 >in !
  interpret
  restore-input ;

: include-file ( file -- )
  dup file-read-all ( file read-all n )
  >r >r >r
  1 ridx @ 2 ridx @ evaluate
  r> r> r>
  drop free drop ;

: included ( filename n -- )
  2dup r/o open-file if
    -rot 2drop
    dup >r include-file r>
    close-file
  else
    \ todo err
    ." file not found: " type cr
    bye
  then ;

: include
  word included ;

\ ===

: date now timezone + calc-timestamp ;

\ ===

: builtin? @ forth-fn-id = 0= ;
: forth-word? builtin? 0= ;

: expect ( "predicate" -- )
  word find unwrap >cfa
  ['] dup ,
  ,
  ['] 0= ,
  [compile] if
  ['] drop ,
  ['] panic ,
  [compile] then
  ; immediate

