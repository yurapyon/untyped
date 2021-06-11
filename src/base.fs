: 0= 0 = ;
: 1+ 1 + ;
: 1- 1 - ;

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
  [compile] then ; immediate
  \ dup here @ swap -
  \ swap ! ; immediate

: begin
  here @
  ; immediate

: until
  ['] 0branch ,
  here @ - , ; immediate

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

( testing )

: newline 10 ;
: bl 32 ;

: cr newline emit ;
: space bl emit ;

: true -1 ;
: false 0 ;
: not 0= ;

: negate 0 swap - ;

: recurse
  latest @ >cfa cell + ,
  ; immediate

\ todo check this works
: tailcall
  ' cell + ,
  ; immediate

: doit'
  dup 72 = not if
    dup emit cr
    1+ recurse
  then
  drop
  ;

: doit 65 doit' ;

\ doit

: decimal 10 base ! ;
: hex 16 base ! ;
: octal 8 base ! ;

: cells cell * ;

: 2dup over over ;
: 2drop drop drop ;

: allot
  here @ + here ! ;

: create
  define
  ['] docol ,
  ['] lit , here @ 2 cells + ,
  ['] exit , ;

: does>,redirect-latest \ ( code-addr -- )
  latest @ >cfa 3 cells + ! ;

: does>
  state @ if
    ['] lit , here @ 3 cells + ,
    ['] does>,redirect-latest ,
    ['] exit ,
  else
    here @ does>,redirect-latest
    latest @ hidden
    ]
  then
  ; immediate

: constant
  create ,
  does> @ ;

5 constant wowo
wowo .s

: >body
  2 cells + @ ;


' wowo >body dup @ .s

10 create something ,
does> @ 2 + ;

something .s

bye


( docol lit data-addr exit      exit ^data-addr )
( docol lit data-addr does-addr exit ^data-addr ..data.. docol )

( ; >> exit )

( .
create wowo 4 cells allot
char a wowo 0 + c!
char b wowo 1 + c!
char c wowo 2 + c!
char d wowo 3 + c!

wowo 0 + c@
wowo 1 + c@
wowo 2 + c@
wowo 3 + c@ .s
)


: ch
  [char] x ;

ch .s

: jkl if swap then ;
: yui if 1 else 2 then ;
\ 1 2 0 jkl
\ 3 4 1 jkl .s
0 yui
1 yui .s
\ create asdf 1234 , .s asdf asdf @ .s
\ : constant create , does> ____ ;
