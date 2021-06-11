: 2dup over over ;

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

key # .s
\ asdf

: jkl if swap then ;
: yui if 1 else 2 then ;
\ 1 2 0 jkl
\ 3 4 1 jkl .s
0 yui
1 yui .s
\ : cells cell * ;
\ : create define ['] docol , ['] lit , here @ 3 cells + , ['] exit , ['] exit , ;
\ create asdf 1234 , .s asdf asdf @ .s
\ : constant create , does> ____ ;
