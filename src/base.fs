here @
word : define
forth-fn-id ,
' word , ' define ,
' latest , ' @ , ' hide ,
' lit , forth-fn-id , ' , ,
' ] ,
' exit ,
latest !

here @
word ; define
forth-fn-id ,
' lit , ' exit , ' , ,
' latest , ' @ , ' hide ,
' [ ,
' exit ,
latest !
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
: halfs half * ;
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
: / /mod nip ;
: mod /mod drop ;
: 2* 2 * ;

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

\ todo change to have normal arg order
: within     ( val max min -- t/f )
  >r over r> ( val max val min )
  >= -rot < and ;

: decimal 10 base ! ;
: hex 16 base ! ;
: octal 8 base ! ;

\ ===

: bl 32 ;
: backslash 92 ;
: cr 10 emit ;
: space bl emit ;

\ ===

: aligned-to ( addr align -- a-addr )
  2dup mod ( addr align off-aligned )
  ?dup if
    - +
  else
    drop
  then ;

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
  ['] nop ,
  ['] exit , ;

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
  word find unwrap >value-data
  state @ if
    ['] lit , ,
    ['] ! ,
  else
    !
  then
  ; immediate

: +to
  word find unwrap >value-data
  state @ if
    ['] lit , ,
    ['] +! ,
  else
    +!
  then
  ; immediate

\ TODO float values

\ ===

: :noname
  0 0 define
  here @
  forth-fn-id ,
  ] ;

\ ===
